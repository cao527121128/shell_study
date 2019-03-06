#!/usr/bin/env python
'''
Created on 2012-5-27

@author: yunify
'''

import os
import sys
from optparse import OptionParser
from yaml import load, dump
try:
    from yaml import CLoader as Loader, CDumper as Dumper
except ImportError:
    from yaml import Loader, Dumper
    
CWD = os.path.abspath(os.path.dirname(sys.argv[0]))
os.chdir(CWD)

# global
g_project_home = None
g_output_dir = None
g_compile_mode = "binary"

# for compile
g_dst_dir = None
g_included_dirs = None
g_excluded_dirs = None

def yaml_load(stream):
    ''' load from yaml stream and create a new python object 
    
    @return object or None if failed
    ''' 
    try:
        obj = load(stream, Loader=Loader)
    except Exception, e:
        obj = None
        print ("load yaml failed: %s" % e)       
    return obj

def explode_array(list_str, separator=","):
    ''' explode list string into array '''
    result = []
    disk_list = list_str.split(separator)
    for disk in disk_list:
        disk = disk.strip()
        if disk != "":
            result.append(disk)
    return result

def safe_exec(cmd):
    #print "Executing [%s] ..." % cmd
    if 0 != os.system(cmd):
        sys.exit(-1)

def compile_file(src_file):
    global g_dst_dir, g_compile_mode
    file_name = os.path.basename(src_file)
    dir_name = os.path.dirname(src_file)
    
    global g_included_dirs, g_excluded_dirs
    if len(g_included_dirs) != 0:
        found = False
        for dir in g_included_dirs:
            if dir_name.startswith(dir):
                found = True
                break
        if not found:
            return 0
    if len(g_excluded_dirs) != 0:
        found = False
        for dir in g_excluded_dirs:
            if dir_name.startswith(dir):
                found = True
                break
        if found:
            return 0
        
    if file_name.startswith("test"):
        return 0
    
    # copy source file directly
    if file_name.endswith(".sh") or \
            file_name.endswith(".bash") or \
            file_name.endswith(".yaml") or \
            file_name.endswith(".tpl") or \
            file_name.endswith(".ps1") or \
            "." not in file_name or \
            file_name == "__init__.py":
        tmp_path = g_dst_dir + "/" + os.path.dirname(src_file)
        os.system("mkdir -p %s" % tmp_path)
        safe_exec("cp -f %s %s" % (src_file, tmp_path))
        return 0
    
    if not file_name.endswith(".py"):
        return 0
    
    if g_compile_mode == "source" and dir_name != "script/guest":
        tmp_path = g_dst_dir + "/" + os.path.dirname(src_file)
        os.system("mkdir -p %s" % tmp_path)
        safe_exec("cp -f %s %s" % (src_file, tmp_path))
        return 0        

    is_executable = False
    with open(src_file) as fp:
        head_line = fp.readline()
        if head_line.strip() == "#!/usr/bin/env python":
            is_executable = True
            
    # if this source file is executable, it shall be compiled to exe
    if is_executable:
        base_name = src_file.split(".")[0]  
        safe_exec("cython -D -2 --embed %s" % src_file)
        safe_exec("gcc -c -fPIC -fwrapv -O2 -Wall -fno-strict-aliasing -I/usr/include/python2.7 -o %s.o %s.c" % (base_name, base_name))
        safe_exec("gcc -I/usr/include/python2.7 -o %s %s.o -lpython2.7" % (base_name, base_name))
        if not os.path.exists(base_name):
            print "compile [%s] failed" % src_file
            return -1
        tmp_path = g_dst_dir + "/" + dir_name
        os.system("mkdir -p %s" % tmp_path)
        safe_exec("cp -f %s %s" % (base_name, tmp_path))
        os.system("strip -s %s/%s" % (tmp_path, os.path.basename(base_name)))
        os.system("rm -f %s" % base_name) 
        return 0

    # if this source file is not executable, it shall be compiled to dynamic library
    base_name = src_file.split(".")[0]  
    safe_exec("cython -D -2 %s" % src_file)
    safe_exec("gcc -shared -pthread -fPIC -fwrapv -O2 -Wall -fno-strict-aliasing -I/usr/include/python2.7 -o %s.so %s.c" % (base_name, base_name))
    if not os.path.exists("%s.so" % base_name):
        print "compile [%s] failed" % src_file
        return -1
    tmp_path = g_dst_dir + "/" + dir_name
    os.system("mkdir -p %s" % tmp_path)
    os.system("cp -f %s.so %s" % (base_name, tmp_path))
    os.system("strip -s %s/%s.so" % (tmp_path, os.path.basename(base_name)))

def compile_folder(src_dir):
    files = os.listdir(src_dir)
    for f in files:
        fpath = src_dir + "/" + f
        if os.path.isdir(fpath):
            compile_folder(fpath)
        elif os.path.isfile(fpath):
            compile_file(fpath)

def compile(src_dir, dst_dir, included_dirs=[], excluded_dirs=[]): 
    '''
    @param src_dir - root source directory, absolute path
    @param dst_dir - root destination directory, absolute path
    @param home_dir - the build directory relative to root source directory
    '''
    if not dst_dir or dst_dir == "/":
        print "Error: invalid dst dir"
        return -1
    
    global g_dst_dir, g_included_dirs, g_excluded_dirs
    g_dst_dir = dst_dir
    g_included_dirs = included_dirs
    g_excluded_dirs = excluded_dirs

    # change to src dir and build to dst dir
    os.chdir(src_dir)
    files = os.listdir("./")
    for f in files:
        if os.path.isdir(f):
            compile_folder(f)
        elif os.path.isfile(f):
            compile_file(f)       
            
    # clean intermediate files 
    os.system("find %s -name \"*.pyc\" | xargs rm -f" % src_dir)     
    os.system("find %s -name \"*.so\" | xargs rm -f" % src_dir)     
    os.system("find %s -name \"*.o\" | xargs rm -f" % src_dir)     
    os.system("find %s -name \"*.c\" | xargs rm -f" % src_dir)    
    
    os.chdir(CWD) 
    return 0

def create_file_by_tpl(tpl_file, params, out_file):
    from string import Template
    with open(tpl_file, "r") as fp:
        tpl = fp.read()
    if not tpl:
        return -1
    
    with open(out_file, "w") as fp:
        s = Template(tpl)
        fp.write(s.safe_substitute(params))
    return 0
    
def get_deb_size(deb_home):
    if 0 != os.system("du -sx --exclude DEBIAN %s | awk '{print $1}' > /tmp/.deb.size" % deb_home):
        return -1
    with open("/tmp/.deb.size", "r") as fp:
        return int(fp.read().strip())
    return -1

def build_package(pkg_name, pkg_info):
    global CWD, g_compile_mode, g_project_home, g_output_dir

    src_dir = g_project_home + "/src"
    deb_home = CWD + "/.deb/" + pkg_name

    # clean deb home
    os.system("rm -rf %s" % deb_home)
    os.system("mkdir -p %s" % deb_home)
    os.system("mkdir -p %s" % g_output_dir)
    
    # compile src
    if 'src' in pkg_info:
        lib_dir = os.path.abspath(deb_home + pkg_info['src']['lib_home'])
        if 0 != compile(src_dir, lib_dir, pkg_info['src']['include'], pkg_info['src']['exclude']):
            print "Error: compile failed"
            return -1
        
    # copy others
    if 'non-src' in pkg_info:
        for sfile, tfile in pkg_info['non-src'].iteritems():
            src_file = "%s/%s" % (g_project_home, sfile)
            if os.path.exists("%s.%s" % (src_file, g_compile_mode)):
                src_file = "%s.%s" % (src_file, g_compile_mode)
            dst_file = "%s/%s" % (deb_home, tfile)
            if not os.path.exists(src_file):
                print "Error: file [%s] not exists" % src_file
                return -1
            os.system("mkdir -p %s" % os.path.dirname(dst_file))
            os.system("cp %s %s" % (src_file, dst_file))
    
    os.system("mkdir -p %s/DEBIAN" % deb_home)
            
    # pre install 
    if 'preinst' in pkg_info and pkg_info['preinst']['template']:
        tpl_file = g_project_home + "/" + pkg_info['preinst']['template']
        out_file = deb_home + "/DEBIAN/preinst"
        params = pkg_info['preinst']['params']
        create_file_by_tpl(tpl_file, params, out_file)
        os.system("chmod 755 %s" % out_file)

    # post install 
    if 'postinst' in pkg_info and pkg_info['postinst']['template']:
        tpl_file = g_project_home + "/" + pkg_info['postinst']['template']
        out_file = deb_home + "/DEBIAN/postinst"
        params = pkg_info['postinst']['params']
        create_file_by_tpl(tpl_file, params, out_file)
        os.system("chmod 755 %s" % out_file)

    # pre removal 
    if 'prerm' in pkg_info and pkg_info['prerm']['template']:
        tpl_file = g_project_home + "/" + pkg_info['prerm']['template']
        out_file = deb_home + "/DEBIAN/prerm"
        params = pkg_info['prerm']['params']
        create_file_by_tpl(tpl_file, params, out_file)
        os.system("chmod 755 %s" % out_file)

    # deb control
    tpl_file = g_project_home + "/" + pkg_info['control']['template']
    out_file = deb_home + "/DEBIAN/control"
    params = pkg_info['control']['params']
    params.update({"package" : pkg_name, "size" : get_deb_size(deb_home), "version" : pkg_info['version']})
    create_file_by_tpl(tpl_file, params, out_file)
    os.system("chmod 644 %s" % out_file)

    # make deb
    cmd = "dpkg -b %s %s/%s-%s.deb > /dev/null" % (deb_home, g_output_dir, pkg_name, pkg_info['version'])
    safe_exec(cmd)
    
    os.system("rm -rf %s" % deb_home)
    return 0

opt_parser = OptionParser()     
opt_parser.add_option("-p", "--project_home", action="store", type="string", \
                     dest="project_home", help='project home', default="") 
opt_parser.add_option("-m", "--mode", action="store", type="string", \
                     dest="compile_mode", help='compile mode', default="binary") 
opt_parser.add_option("-o", "--output_dir", action="store", type="string", \
                     dest="output_dir", help='output directory', default="") 
(options, _) = opt_parser.parse_args(sys.argv)
g_compile_mode = options.compile_mode
print "  compile mode : %s" % g_compile_mode

# project home
g_project_home = options.project_home
if g_project_home == "":
    opt_parser.print_help()
    sys.exit(-1)
if not g_project_home.startswith("/"):
    g_project_home = os.path.abspath(CWD + "/" + g_project_home) 
print "  project home : %s" % g_project_home

if "pitrix-bot-router2" in g_project_home:
    g_compile_mode = "binary"
if "pitrix-bot-bm" in g_project_home:
    g_compile_mode = "binary"
if "pitrix-bot-swctl" in g_project_home:
    g_compile_mode = "binary"
if "pitrix-bot-cm" in g_project_home:
    g_compile_mode = "binary"
if "pitrix-bot-repl" in g_project_home:
    g_compile_mode = "binary"
  
# destination directory  
g_output_dir = options.output_dir
if g_output_dir == "":
    g_output_dir = "%s/output" % CWD
if not g_output_dir.startswith("/"):
    g_output_dir = os.path.abspath(CWD + "/" + g_output_dir) 
os.system("mkdir -p %s" % g_output_dir)
print "    output dir : %s" % g_output_dir

# configuration
conf_file = "%s/build/build.yaml" % g_project_home
if not os.path.exists(conf_file):
    print "  Error: can't find [%s]" % conf_file
    opt_parser.print_help()
    sys.exit(-1)
    
print

# load config
with open(conf_file, "r") as fd:
    conf = yaml_load(fd)    
  
for pkg_name, pkg_info in conf.iteritems():
    print "  building [%s] ..." % pkg_name
    if 0 != build_package(pkg_name, pkg_info):
        print "failed"
        sys.exit(-1)
    print "  OK."
    print 

sys.exit(0)









  

