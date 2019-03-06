#!/bin/bash
#set -x

SCRIPT=$(readlink -f $0)
CWD=$(dirname ${SCRIPT})
PKG_DIR=$(dirname ${CWD})

function usage()
{
    echo "Usage:"
    echo "    upgrade.sh"
    echo "      means upgrade installer and qingcloud(repos, kernels)"
    echo "Example:"
    echo "    upgrade.sh"
}

while [[ "x$1" != "x" ]]
do
    case $1 in
        *)
            usage
            exit 1
            ;;
    esac
done

function _convert_version()
{
    # original 4.1.2 ---> target 40102
    current_version=$1
    current_major_version="$(echo ${current_version} | awk -F'.' '{print $1}')"
    current_minor_version="$(echo ${current_version} | awk -F'.' '{print $2}')"
    current_revision_version="$(echo ${current_version} | awk -F'.' '{print $3}')"
    if [[ ${current_minor_version} -lt 10 ]]; then
        current_minor_version="0${current_minor_version}"
    fi
    if [[ ${current_revision_version} -lt 10 ]]; then
        current_revision_version="0${current_revision_version}"
    fi
    echo "${current_major_version}${current_minor_version}${current_revision_version}"
}

function check_os_environment()
{
    os_version="$(grep -i description /etc/lsb-release | cut -d ' ' -f 2)"
    if [[ ${os_version} == "14.04"* ]]; then
        os_name="trusty"
        apt_options="--yes --force-yes --allow-unauthenticated"
    elif [[ ${os_version} == "16.04"* ]]; then
        os_name="xenial"
        # --force-yes is deprecated after Ubuntu 16.04.x
        apt_options="--yes --allow-unauthenticated"
    else
        echo "Error: Please use Ubuntu 14.04.x or 16.04.x in firstbox!"
        return 1
    fi

    if [[ "x$(whoami)" != "xroot" ]]; then
        echo "Error: You are not a root user. Please change to the root user and retry!"
        return 1
    fi
}

function check_upgrade_condition()
{
    if [ ! -d ${PKG_DIR}/repo ] || [ ! -d ${PKG_DIR}/kernels ]; then
        echo "Error: The installer is not integrated! [repo/kernels] may not exist!"
        return 1
    fi

    if echo ${PKG_DIR} | grep -q "^/pitrix/" ; then
        echo "Error: The installer package can not be upgrade in /pitrix!"
        return 1
    fi

    if [ ! -d /pitrix ]; then
        echo "Error: The pitrix directory does not exist, please check it!"
        return 1
    fi

    /pitrix/cli/describe-qingcloud.py | grep -q '"status": "running"'
    if [ $? -ne 0 ]; then
        echo "Error: The platform status is not [running], please check it!"
        return 1
    fi

    # compare installer and qingcloud versions
    current_installer=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['installer'])")
    if [[ "x${current_installer}" == "x" ]]; then
        echo "Error: The installer version in the file [/pitrix/version.json] does not exist, please check it!"
        return 1
    fi

    upgrade_installer=$(python -c "import json; print(json.load(open('${PKG_DIR}/version.json', 'r'))['current']['installer'])")
    if [[ "x${upgrade_installer}" == "x" ]]; then
        echo "Error: The installer version in the file [${PKG_DIR}/version.json] does not exist, please check it!"
        return 1
    fi

    current_version=$(_convert_version ${current_installer})
    new_version=$(_convert_version ${upgrade_installer})
    if [[ ${new_version} -le ${current_version} ]]; then
        echo "Error: The new installer version [${upgrade_installer}] is less than or equal to the current installer version [${current_installer}]!"
        return 1
    fi

    current_qingcloud=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['qingcloud'])")
    upgrade_qingcloud=$(python -c "import json; print(json.load(open('${PKG_DIR}/version.json', 'r'))['current']['qingcloud'])")
    if [ ${upgrade_qingcloud} -le ${current_qingcloud} ]; then
        echo "Error: The new qingcloud version [${upgrade_qingcloud}] is less than or equal to the current qingcloud version [${current_qingcloud}]!"
        return 1
    fi
}

function backup_current_installer()
{
    backup_dir="/pitrix/backup"

    # get installer current version
    current_installer=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['installer'])")

    # get qingcloud current version
    current_qingcloud=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['qingcloud'])")

    mkdir -p ${backup_dir}/${current_installer}-${current_qingcloud}
    installer_backup="${backup_dir}/${current_installer}-${current_qingcloud}/installer"
    mkdir -p ${installer_backup}

    # back up installer code
    rsync -azPS --include="/bin" --include="/build" --include="/check" --include="/conf" --include="/config" --include="/deploy" \
        --include="/install" --include="/node" --include="/test" --include="/upgrade" --include="/version.json" --exclude="/*" /pitrix/ ${installer_backup}/

    # installer repo
    mkdir -p ${installer_backup}/installer-repo
    rsync -azPS --include='/installer' --exclude='/*' /pitrix/repo/ ${installer_backup}/installer-repo/

    # back up installer postgresql
    su - postgres -c "pg_dumpall --clean | gzip > /tmp/installer_pg_dumpall.gz"
    mv -f /tmp/installer_pg_dumpall.gz ${installer_backup}/

    # back up qingcloud repo
    qingcloud_backup="${backup_dir}/${current_installer}-${current_qingcloud}/qingcloud/"
    mkdir -p ${qingcloud_backup}

    # pitrix repo
    mkdir -p ${qingcloud_backup}/pitrix-repo
    rsync -azPS --exclude="/installer/code" /pitrix/repo/ ${qingcloud_backup}/pitrix-repo/

    # os repo
    mkdir -p ${qingcloud_backup}/os-repo
    rsync -azPS --exclude='*/iso' /var/www/repo/ ${qingcloud_backup}/os-repo/
}

function update_current_installer()
{
    rsync -azPS --include="/kernels" --exclude="/*" ${PKG_DIR}/ /pitrix/

    os_versions=('14.04.5' '16.04.3' '16.04.5')

    for os_version in ${os_versions[@]}
    do
        if [[ -f ${PKG_DIR}/repo/pitrix/${os_version} ]]; then
            rsync -azPS --delete ${PKG_DIR}/repo/pitrix/${os_version} /pitrix/repo/
        fi

        if [[ -f ${PKG_DIR}/repo/os/${os_version} ]]; then
            rsync -azPS --delete ${PKG_DIR}/repo/os/${os_version} /var/www/repo/
        fi
    done

    cloud_type="$(cat /pitrix/conf/variables/cloud_type*)"
    if [[ ${cloud_type} != *"public"* ]]; then
        rsync -azPS --delete ${PKG_DIR}/repo/pitrix/indep /pitrix/repo/
    fi

    rsync -azPS --delete ${PKG_DIR}/repo/os/pip /var/www/repo/
    rsync -azPS --delete ${PKG_DIR}/repo/test /pitrix/repo/
    rsync -azPS --delete ${PKG_DIR}/repo/installer /pitrix/repo/
    /pitrix/upgrade/build_global_conf.sh

    # upgrade version.json
    old_installer=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['installer'])")
    old_patch=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['patch'])")
    old_upgrade=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['upgrade'])")
    old_qingcloud=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['qingcloud'])")
    python -c "import json; obj = json.load(open('/pitrix/version.json', 'r')); obj['old'].insert(0, {'installer': '${old_installer}', 'patch': '${old_patch}', 'upgrade': '${old_upgrade}', 'qingcloud': '${old_qingcloud}'}); json.dump(obj, open('/pitrix/version.json', 'w'), sort_keys=True, indent=4, separators=(',', ': '));"

    new_installer=$(python -c "import json; print(json.load(open('${PKG_DIR}/version.json', 'r'))['current']['installer'])")
    new_patch=$(python -c "import json; print(json.load(open('${PKG_DIR}/version.json', 'r'))['current']['patch'])")
    new_upgrade=$(python -c "import json; print(json.load(open('${PKG_DIR}/version.json', 'r'))['current']['upgrade'])")
    new_qingcloud=$(python -c "import json; print(json.load(open('${PKG_DIR}/version.json', 'r'))['current']['qingcloud'])")
    python -c "import json; obj = json.load(open('/pitrix/version.json', 'r')); obj['current'] = {'installer': '${new_installer}', 'patch': '${new_patch}', 'old_upgrade': '${old_upgrade}', 'new_upgrade': '${new_upgrade}', 'qingcloud': '${new_qingcloud}'}; json.dump(obj, open('/pitrix/version.json', 'w'), sort_keys=True, indent=4, separators=(',', ': '));"

    # scan the new repo
    /pitrix/bin/scan_all.sh

    # update installer packages
    apt-get clean
    apt-get autoclean
    apt-get update
    apt-get ${apt_options} install --reinstall pitrix-installer-common pitrix-installer-apiserver pitrix-installer-cli pitrix-installer-webserver \
        pitrix-installer-docs pitrix-installer-node-proxy pitrix-installer-node-server pitrix-installer-node-script pitrix-installer-node-patch \
        pitrix-installer-qingcloud-proxy pitrix-installer-qingcloud-server pitrix-installer-qingcloud-script pitrix-installer-qingcloud-patch pitrix-installer-qingcloud-upgrade
    if [ $? -ne 0 ]; then
        echo "Error: Update the installer packages failed!"
        return 1
    fi

    uwsgi --reload /var/run/apiserver.pid
    service nginx restart

    supervisorctl restart all
}

function update_current_webinstaller()
{
    rm -rf /pitrix/lib/pitrix-webinstaller
    tar -zxf /pitrix/repo/web/pitrix-webinstaller.tar.gz -C /pitrix/lib/

    # connect to installer apiserver, port 9999
    cp -f /pitrix/lib/pitrix-webinstaller/server/mysite/settings.py.example /pitrix/lib/pitrix-webinstaller/server/mysite/settings.py
    sed -i "s/{{api_server_host}}/127.0.0.1/g" /pitrix/lib/pitrix-webinstaller/server/mysite/settings.py
    sed -i "s/{{api_server_port}}/9999/g" /pitrix/lib/pitrix-webinstaller/server/mysite/settings.py
    sed -i "s/{{api_server_protocol}}/http/g" /pitrix/lib/pitrix-webinstaller/server/mysite/settings.py

    # prepare for installer webconsole, port 9998
    uwsgi --reload /var/run/webinstaller.pid
    service nginx restart
}

log_file="/root/upgrade.log"
if [ -f ${log_file} ]; then
    echo "" >> ${log_file}
fi

function log()
{
    msg=$*
    date="$(date +'%Y-%m-%d %H:%M:%S')"
    echo "${date} ${msg}" >> ${log_file}
}

function SafeExecFunc()
{
    local func=$1
    log "Execing the function [${func}] ..."
    ${func} >>${log_file} 2>&1
    if [ $? -eq 0 ]; then
        echo -n "OK." && echo ""
        log "Exec the function [${func}] OK."
    else
        echo -n "Error!" && echo ""
        log "Exec the function [${func}] Error!"
        exit 1
    fi
}

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo "${date} Info: Begin to upgrade platform ..."
log "Info: Begin to upgrade platform..."

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Checking whether the os environment is valid ... "
SafeExecFunc check_os_environment

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Checking whether the upgrade condition is met ... "
SafeExecFunc check_upgrade_condition

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Backing up the current installer ... "
SafeExecFunc backup_current_installer

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Updating the current installer ... "
SafeExecFunc update_current_installer

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Updating the current webinstaller ..."
SafeExecFunc update_current_webinstaller

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo "${date} The installer is upgraded successfully. Check it please!"
log "The installer is upgraded successfully. Check it please!"
