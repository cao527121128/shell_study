#!/bin/bash
#set -x

SCRIPT=$(readlink -f $0)
CWD=$(dirname ${SCRIPT})
PKG_DIR=$(dirname ${CWD})

function usage()
{
    echo "Usage:"
    echo "    deploy.sh [-i <ipmi_interface>] [-n <ipmi_network>]"
    echo "      <ipmi_interface> means the interface to config ipmi network for bm provision."
    echo "      <ipmi_network> means the ipmi network for bm provision."
    echo "Example:"
    echo "    deploy.sh"
    echo "    deploy.sh -i eth1 -n 172.30.10.46/24"
}

if [[ "x$1" == "x-h" ]] || [[ "x$1" == "x--help" ]]; then
    usage
    exit 1
fi

IPMI_INTERFACE=""
IPMI_NETWORK=""
while [[ "x$1" != "x" ]]
do
    case $1 in
        -i)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                IPMI_INTERFACE=$2
                shift
            fi
            shift
            ;;
        -n)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                IPMI_NETWORK=$2
                shift
            fi
            shift
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

function check_os_environment()
{
    os_version=$(lsb_release -d -s | awk '{print $2}')
    if [[ ${os_version} == "14.04"* ]]; then
        os_name="trusty"
        apt_options="--yes --force-yes --allow-unauthenticated"
    elif [[ ${os_version} == "16.04"* ]]; then
        os_name="xenial"
        # --force-yes is deprecated after Ubuntu 16.04.x
        apt_options="--yes --allow-unauthenticated"

        # workaround for the incorrect os version node
        if [[ "x${os_version}" == "x16.04.4" ]]; then
            os_version="16.04.3"
        fi
    else
        echo "Error: Please use Ubuntu 14.04.x or 16.04.x in firstbox!"
        return 1
    fi

    if [[ "x$(whoami)" != "xroot" ]]; then
        echo "Error: You are not a root user. Please change to the root user and retry!"
        return 1
    fi
}

function check_installer_package()
{
    if [ ! -d ${PKG_DIR}/repo ] || [ ! -d ${PKG_DIR}/kernels ]; then
        echo "Error: The installer is not integrated! [repo/kernels] may not exist!"
        return 1
    fi

    if echo ${PKG_DIR} | grep -q "^/pitrix/" ; then
        echo "Error: The installer package can not be bootstrapped in /pitrix!"
        return 1
    fi
}

function prepare_qingcloud_repository()
{
    # sync version file
    rsync -azPS ${PKG_DIR}/version.json /pitrix/

    # sync kernels
    mkdir -p /pitrix/kernels/
    rsync -azPS ${PKG_DIR}/kernels/ /pitrix/kernels/

    # make a soft link for pitrix kernels
    if [ ! -L /kernels ]; then
        ln -s /pitrix/kernels /kernels
    fi

    mkdir -p /var/www/repo
    rsync -azPS ${PKG_DIR}/repo/os/ /var/www/repo/

    # delete old mount point
    sed -i "/.*iso9660.*/d" /etc/fstab
    if [ -f "/pitrix/kernels/ubuntu-14.04.5-server-amd64.iso" ]; then
        mkdir -p /var/www/repo/14.04.5/iso/
        echo "/pitrix/kernels/ubuntu-14.04.5-server-amd64.iso /var/www/repo/14.04.5/iso iso9660 loop 0  0" >> /etc/fstab
    fi
    if [ -f "/pitrix/kernels/ubuntu-16.04.3-server-amd64.iso" ]; then
        mkdir -p /var/www/repo/16.04.3/iso/
        echo "/pitrix/kernels/ubuntu-16.04.3-server-amd64.iso /var/www/repo/16.04.3/iso iso9660 loop 0  0" >> /etc/fstab
    fi
    if [ -f "/pitrix/kernels/ubuntu-16.04.3-server-arm64.iso" ]; then
        mkdir -p /var/www/repo/16.04.3-arm/iso/
        echo "/pitrix/kernels/ubuntu-16.04.3-server-arm64.iso /var/www/repo/16.04.3-arm/iso iso9660 loop 0  0" >> /etc/fstab
    fi
    if [ -f "/pitrix/kernels/ubuntu-16.04.5-server-amd64.iso" ]; then
        mkdir -p /var/www/repo/16.04.5/iso/
        echo "/pitrix/kernels/ubuntu-16.04.5-server-amd64.iso /var/www/repo/16.04.5/iso iso9660 loop 0  0" >> /etc/fstab
    fi
    mount -a
    if [ $? -ne 0 ]; then
        echo "Error: Auto mount the system iso file to corresponding repo iso directory failed!"
        return 1
    fi

    mkdir -p /pitrix/repo
    rsync -azPS ${PKG_DIR}/repo/pitrix/ /pitrix/repo/
    rsync -azPS ${PKG_DIR}/repo/installer /pitrix/repo/
    rsync -azPS ${PKG_DIR}/repo/test /pitrix/repo/

    cpu_arch=$(arch)
    if [[ "x${cpu_arch}" == "xx86_64" ]]; then
        arch_flag=""
    elif [[ "x${cpu_arch}" == "xaarch64" ]]; then
        arch_flag="-arm"
    fi

    # backup
    cp -f /etc/apt/sources.list /etc/apt/sources.list.bak
    echo "deb file:///var/www/repo/${os_version}${arch_flag}/iso/ubuntu ${os_name} main" > /etc/apt/sources.list
    echo "deb file:///var/www/repo/${os_version}${arch_flag}/add_ons/ /" >> /etc/apt/sources.list
    echo "deb file:///pitrix/repo/${os_version}${arch_flag}/ /" >> /etc/apt/sources.list
    echo "deb file:///pitrix/repo/indep${arch_flag}/ /" >> /etc/apt/sources.list
    echo "deb file:///pitrix/repo/installer/code/ /" >> /etc/apt/sources.list

    if [[ ${os_version} == "16.04"* ]]; then
        systemctl stop apt-daily.timer; systemctl disable apt-daily.timer
        systemctl stop apt-daily-upgrade.timer; systemctl disable apt-daily-upgrade.timer
        systemctl stop apt-daily.service; systemctl disable apt-daily.service
        systemctl stop apt-daily-upgrade.service; systemctl disable apt-daily-upgrade.service
    fi

    # clean the process using apt or dpkg
    apt_process=$(ps -aux | grep -E 'apt|dpkg' | grep -v 'grep' | awk '{print $2}')
    for process in ${apt_process}
    do
        kill -9 ${process}
    done
    # remove the apt lock
    rm -f /var/lib/apt/lists/lock

    # make sure the apt-get service is OK
    dpkg --configure -a && apt-get autoclean && apt-get clean
    if [ $? -ne 0 ]; then
        echo "Error: There may be something wrong with apt-get service!"
        return 1
    fi

    apt-get update
    # apt upgrde ssh may cause ssh start failed
    sed -i '/Ciphers/d' /etc/ssh/sshd_config
    service ssh restart

    apt-get ${apt_options} install dpkg-dev
    if [ $? -ne 0 ]; then
        echo "Error: Install the dpkg packages failed!"
        return 1
    fi

    for version in 12.04.4 14.04.3 14.04.5 16.04.3 16.04.3-arm 16.04.5
    do
        if [ -d "/var/www/repo/${version}/add_ons" ]; then
            cd /var/www/repo/${version}/add_ons
            dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz
            cd ${CWD}
        fi
        if [ -d "/pitrix/repo/${version}" ]; then
            cd /pitrix/repo/${version}
            dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz
            cd ${CWD}
        fi
    done

    if [ -d "/pitrix/repo/indep" ]; then
        cd /pitrix/repo/indep
        dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz
        cd ${CWD}
    fi
    if [ -d "/pitrix/repo/indep-arm" ]; then
        cd /pitrix/repo/indep-arm
        dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz
        cd ${CWD}
    fi
    if [ -d "/pitrix/repo/installer/code" ]; then
        cd /pitrix/repo/installer/code
        dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz
        cd ${CWD}
    fi
    if [ -d "/pitrix/repo/test/16.04.3" ]; then
        cd /pitrix/repo/test/16.04.3
        dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz
        cd ${CWD}
    fi
    if [ -d "/pitrix/repo/test/16.04.5" ]; then
        cd /pitrix/repo/test/16.04.5
        dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz
        cd ${CWD}
    fi
    if [ -d "/pitrix/repo/test/vpn" ]; then
        cd /pitrix/repo/test/vpn
        dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz
        cd ${CWD}
    fi
}

function install_base_packages()
{
    # remove apparmor
    ln -s /etc/apparmor.d/usr.sbin.dhcpd /etc/apparmor.d/disable/
    apparmor_parser -R /etc/apparmor.d/usr.sbin.dhcpd
    service apparmor stop
    update-rc.d -f apparmor remove

    apt-get update
    apt-get ${apt_options} install bash openssl binutils vim ntp xfsprogs wput acpid iproute tcpdump ethtool bridge-utils dpkg-dev \
        ebtables arptables ifenslave net-tools pv sysstat iotop flex gawk conntrack screen numactl memcached intltool iputils-arping \
        pm-utils expect parallel build-essential autoconf automake pkg-config python python-dev python-bcrypt python-pkg-resources \
        python-pcapy python-netaddr python-meld3 python-setuptools python-pip python-simplejson python-yaml python-m2crypto \
        libssh2-1 libaio1 libnss3 libnetcf1 libyajl2 libnss3 librbd1 libopus0 libaio-dev libavahi-common3 libavahi-client3 \
        libasound2 libjpeg8 libsdl1.2debian libfdt1 libpixman-1-0 libnl-3-200 libxslt1-dev libyaml-0-2 libpq-dev libssl1.0.0 \
        libtool libncurses5 librdmacm1 isc-dhcp-server openipmi ipmitool open-iscsi iscsitarget libcurl3
    if [ $? -ne 0 ]; then
        echo "Error: Install the base packages failed!"
        return 1
    fi

    if [[ ${os_version} == "14.04"* ]] || [[ "${os_version}" == "16.04"* ]]; then
        # ssh, keep the old ssh configuration, and use DEBIAN_FRONTEND=xxx to jump the package configuration window
        DEBIAN_FRONTEND=noninteractive apt-get install ${apt_options} -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" openssh-server openssh-client
    fi
    if ! grep -q Ciphers /etc/ssh/sshd_config ; then
        ciphers=`ssh -Q cipher localhost | paste -d , -s`
        if [[ "x$ciphers" != "x" ]]; then
            echo "Ciphers $ciphers" >> /etc/ssh/sshd_config
            service ssh reload
        else
            echo "Error: The ciphers is null after upgrade ssh, please check it!"
            return 1
        fi
    fi

    if [[ ${os_version} == "14.04"* ]]; then
        apt-get ${apt_options} install libicu52
    else
        apt-get ${apt_options} install libicu55
    fi

    # workaround for pitrix-libneonsan
    dpkg -l | grep "pitrix-libneonsan" >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        apt-get ${apt_options} purge pitrix-libneonsan
    fi

    # workaround for qemu problem on Ubuntu 16.04
    if [[ ${os_version} == "16.04"* ]]; then
        apt-get ${apt_options} install libnfs8
    fi

    # pitrix-dep-qemu is used to launch vms
    # pitrix-deploy-docs includes all docs for qingcloud
    apt-get ${apt_options} --reinstall install pitrix-dep-supervisor pitrix-dep-qemu pitrix-dep-nbd pitrix-dep-libiscsi \
        pitrix-dep-usbredir pitrix-dep-utils pitrix-dep-psycopg2 pitrix-deploy-docs pitrix-dep-spice \
        pitrix-dep-celt
    if [ $? -ne 0 ]; then
        echo "Error: Install the pitrix packages failed!"
        return 1
    fi

    # add supervisord in rc.local
    grep -rqn "/usr/bin/supervisord" /etc/rc.local
    if [ $? -ne 0 ]; then
        sed -i "/^exit/d" /etc/rc.local
        echo "/usr/bin/supervisord" >> /etc/rc.local
        echo "exit 0" >> /etc/rc.local
    fi
    # start supervisord
    if [[ ! -S /var/run/supervisor.sock ]]; then
        /usr/bin/supervisord
    fi

    # nginx
    apt-get ${apt_options} install nginx-full nginx-common
    if [ $? -ne 0 ]; then
        echo "Error: Install the nginx packages failed!"
        return 1
    fi

    # nginx repo
    cp -f ${CWD}/templates/nginx.conf /etc/nginx
    rm -f /etc/nginx/sites-enabled/default
    rm -rf /var/www/html
    cp -f ${CWD}/templates/repo.conf.nginx /etc/nginx/sites-available/repo.conf
    ln -s /etc/nginx/sites-available/repo.conf /etc/nginx/sites-enabled/
    service nginx restart

    # highlight prompt
    grep '93m' /root/.bashrc
    if [ $? -ne 0 ]; then
        echo 'PS1="\u@\[\e[1;93m\]\h\[\e[m\]:\w\\$\[\e[m\] "' >> /root/.bashrc
    fi

    # modify the timezone to CST(Asia/Shanghai)
    # timedatectl set-timezone Asia/Shanghai
    cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    echo "Asia/Shanghai" > /etc/timezone
}

function install_pip_packages()
{
    # pip.conf file may does not make sense
    mkdir -p /root/.pip
    echo "[global]" > /root/.pip/pip.conf
    echo "find-links = http://qingcloud-firstbox/repo/pip" >> /root/.pip/pip.conf
    echo "trusted-host = qingcloud-firstbox" >> /root/.pip/pip.conf
    echo "no-index = yes" >> /root/.pip/pip.conf
    echo "disable-pip-version-check = true" >> /root/.pip/pip.conf
    echo "timeout = 120" >> /root/.pip/pip.conf

    if [[ ${os_version} == "14.04"* ]]; then
        # old version pip may has no option [--trusted-host], such as version 1.5.4
        pip install --upgrade --no-index -f http://127.0.0.1/repo/pip pip
        # new version pip is located in /usr/local/bin/pip, the command pip will make senses after reboot
        pip_command="/usr/local/bin/pip"
        pip_options="--upgrade --no-index --trusted-host 127.0.0.1 -f http://127.0.0.1/repo/pip"
    elif [[ ${os_version} == "16.04"* ]]; then
        pip_command="pip"
        pip_options="--upgrade --no-index --trusted-host 127.0.0.1 -f http://127.0.0.1/repo/pip"
    fi

    # setuptools should be installed firstly, because pip install may use it
    ${pip_command} install ${pip_options} wheel
    ${pip_command} install ${pip_options} setuptools
    ${pip_command} install ${pip_options} setuptools_scm

    ${pip_command} install ${pip_options} requests pyaml pyzmq Django coffin hamlish-jinja jinja2 python-memcached configparser uwsgi
    if [ $? -ne 0 ]; then
        echo "Error: Install the pip packages failed!"
        return 1
    fi

    mkdir -p /etc/uwsgi
}

function install_installer_packages()
{
    apt-get ${apt_options} install --reinstall pitrix-installer-common pitrix-installer-apiserver pitrix-installer-cli pitrix-installer-webserver \
        pitrix-installer-docs pitrix-installer-node-proxy pitrix-installer-node-server pitrix-installer-node-script pitrix-installer-node-patch \
        pitrix-installer-qingcloud-proxy pitrix-installer-qingcloud-server pitrix-installer-qingcloud-script pitrix-installer-qingcloud-patch pitrix-installer-qingcloud-upgrade
    if [ $? -ne 0 ]; then
        echo "Error: Install the installer packages failed!"
        return 1
    fi

    # Create soft link
    if [[ ! -L '/pitrix/docs' ]]; then
        ln -sf /pitrix/lib/pitrix-installer-docs /pitrix/docs
    fi

    mkdir -p /pitrix/log/api
    touch /pitrix/log/api/apiserver.log
    touch /pitrix/log/api/apiserver.log.wf
    chmod 777 /pitrix/log/api/apiserver.log
    chmod 777 /pitrix/log/api/apiserver.log.wf

    touch /pitrix/log/installer.log
    touch /pitrix/log/installer.log.wf
    chmod 777 /pitrix/log/installer.log
    chmod 777 /pitrix/log/installer.log.wf
}

function get_management_network()
{
    mkdir -p /pitrix/conf/variables
    firstbox_address=$(ip -o addr | grep -v inet6 | grep eth0 | awk '{print $4}' | awk -F '/' '{print $1}')
    echo ${firstbox_address} > /pitrix/conf/variables/firstbox_address
}

function config_ssh_service()
{
    if [[ ! -f /root/.ssh/id_rsa ]]; then
        ssh-keygen -f /root/.ssh/id_rsa -t rsa -N ''
    fi
    sed -i "s/\S*$/node@qingcloud.com/" /root/.ssh/id_rsa.pub
    if ! cat /root/.ssh/authorized_keys | grep "$(cat /root/.ssh/id_rsa.pub)" ; then
        cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
    fi
    > /root/.ssh/known_hosts
    rm -f /root/.ssh/known_hosts.old

    ssh_port=$(grep Port /etc/ssh/sshd_config | awk '{print $2}')
    if [[ "x${ssh_port}" == "x" ]]; then
        ssh_port=22
    fi
    echo ${ssh_port} > /pitrix/conf/variables/ssh_port
    cp -f /pitrix/conf/templates/ssh_config.template /etc/ssh/ssh_config
    cp -f /pitrix/conf/templates/sshd_config.template /etc/ssh/sshd_config
    sed -i "s/{{ssh_port}}/${ssh_port}/g" /etc/ssh/ssh_config
    sed -i "s/{{ssh_port}}/${ssh_port}/g" /etc/ssh/sshd_config
    service ssh restart
}

function init_postgresql_database()
{
    if [[ ${os_version} == "14.04"* ]]; then
        pg_version="9.3"
    elif [[ ${os_version} == "16.04"* ]]; then
        pg_version="9.5"
    fi

    apt-get ${apt_options} install postgresql-${pg_version} postgresql-contrib-${pg_version} postgresql-client-${pg_version} postgresql-client-common libpq-dev
    if [ $? -ne 0 ]; then
        echo "Error: Install the base postgresql packages failed!"
        return 1
    fi

    sed -i "s|5432|5433|g" /etc/postgresql/${pg_version}/main/postgresql.conf
    sed -i "/^listen_addresses/d" /etc/postgresql/${pg_version}/main/postgresql.conf
    echo "listen_addresses = '*'" >> /etc/postgresql/${pg_version}/main/postgresql.conf
    service postgresql restart

    # copy ssh key
    cp -ar /root/.ssh /var/lib/postgresql/

    # create role 'yunify' with password 'pgpasswd'
    su - postgres -c "psql -c \"CREATE ROLE yunify;\" -U postgres"
    su - postgres -c "psql -c \"ALTER ROLE yunify WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION PASSWORD 'pgpasswd';\" -U postgres"

    # create database 'installer'
    su - postgres -c "psql -c \"CREATE DATABASE installer;\" -U postgres"
    su - postgres -c "psql -c \"ALTER DATABASE installer OWNER TO yunify;\" -U postgres"
    su - postgres -c "psql -c \"GRANT ALL ON DATABASE installer TO yunify;\" -U postgres"

    # create and init tables for database 'installer'
    su - postgres -c "psql -f /pitrix/lib/pitrix-installer-common/pg/installer.sql -d installer -U postgres"

    # enable qingcloud product
    su - postgres -c "psql -c \"update product set is_enabled = 1 where product_name = 'qingcloud';\" -d installer -U postgres"
}

function config_bm_server()
{
    # isc-dhcp-server
    service isc-dhcp-server stop
    update-rc.d -f isc-dhcp-server remove

    # set interface for pxe dhcp server
    sed -i "/^INTERFACES/s/.*/INTERFACES=\"eth1\"/g" /etc/default/isc-dhcp-server

    # config ipmi network
    if [[ "x${IPMI_INTERFACE}" != "x" ]]; then
        if [[ "x${IPMI_NETWORK}" == "x" ]]; then
            echo "Error: Please specify ipmi network!"
            return 1
        fi
        ip addr add ${IPMI_NETWORK} dev ${IPMI_INTERFACE}
        sed -i "s/exit.*//g" /etc/rc.local
        echo "ip addr add ${IPMI_NETWORK} dev ${IPMI_INTERFACE}" >> /etc/rc.local
        echo "exit 0" >> /etc/rc.local
    fi

    # enable iscsitarget
    sed -i 's/false/true/g' /etc/default/iscsitarget
    service iscsitarget restart

    # install tftpd-hpa
    if [[ ${os_version} == "14.04"* ]]; then
        apt-get ${apt_options} install tftpd-hpa syslinux
        if [ $? -ne 0 ]; then
            echo "Error: Install the base tftpd packages failed!"
            return 1
        fi
        cp -f /usr/lib/syslinux/pxelinux.0 /var/lib/tftpboot/
    elif [[ ${os_version} == "16.04"* ]]; then
        apt-get ${apt_options} install tftpd-hpa pxelinux
        if [ $? -ne 0 ]; then
            echo "Error: Install the base tftpd packages failed!"
            return 1
        fi
        cp -f /usr/lib/PXELINUX/pxelinux.0 /var/lib/tftpboot/
        mkdir -p /var/lib/tftpboot/boot
        cp -rf /usr/lib/syslinux/modules/bios /var/lib/tftpboot/boot/isolinux
    fi
}

function install_config_webinstaller()
{
    rm -rf /pitrix/lib/pitrix-webinstaller
    tar -zxf /pitrix/repo/web/pitrix-webinstaller.tar.gz -C /pitrix/lib/

    # connect to installer apiserver, port 9999
    cp -f /pitrix/lib/pitrix-webinstaller/server/mysite/settings.py.example /pitrix/lib/pitrix-webinstaller/server/mysite/settings.py
    sed -i "s/{{api_server_host}}/127.0.0.1/g" /pitrix/lib/pitrix-webinstaller/server/mysite/settings.py
    sed -i "s/{{api_server_port}}/9999/g" /pitrix/lib/pitrix-webinstaller/server/mysite/settings.py
    sed -i "s/{{api_server_protocol}}/http/g" /pitrix/lib/pitrix-webinstaller/server/mysite/settings.py

    # uwsgi webinstaller
    cp -f ${CWD}/templates/webinstaller.ini.uwsgi /etc/uwsgi/webinstaller.ini
    uwsgi --ini /etc/uwsgi/webinstaller.ini
    sed -i "s/exit.*//g" /etc/rc.local
    echo "uwsgi --ini /etc/uwsgi/webinstaller.ini" >> /etc/rc.local
    echo "exit 0" >> /etc/rc.local

    # prepare for installer webconsole, port 9998
    cp -f ${CWD}/templates/webinstaller.conf.nginx /etc/nginx/sites-available/webinstaller.conf
    ln -s /etc/nginx/sites-available/webinstaller.conf /etc/nginx/sites-enabled/
    service nginx restart
}

log_file="/root/deploy.log"
if [ -f ${log_file} ]; then
    echo "" >> ${log_file}
fi

function log()
{
    msg=$*
    date=$(date +'%Y-%m-%d %H:%M:%S')
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

date=$(date +'%Y-%m-%d %H:%M:%S')
echo "${date} Info: The bootstrap mode is [deploy]."
log "Info: The bootstrap mode is [deploy]."

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Checking whether the os environment is valid ... "
SafeExecFunc check_os_environment

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Checking whether the installer package is ready ... "
SafeExecFunc check_installer_package

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Preparing the qingcloud repository ... "
SafeExecFunc prepare_qingcloud_repository

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Installing the base packages ... "
SafeExecFunc install_base_packages

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Installing the pip packages ... "
SafeExecFunc install_pip_packages

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Installing the installer packages ... "
SafeExecFunc install_installer_packages

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Getting the qingcloud management network ... "
SafeExecFunc get_management_network

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Configuring the firstbox ssh service ... "
SafeExecFunc config_ssh_service

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Initiating the postgresql database ... "
SafeExecFunc init_postgresql_database

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Installing and Configuring the bm module ... "
SafeExecFunc config_bm_server

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Installing and Configuring webinstaller ... "
SafeExecFunc install_config_webinstaller

date=$(date +'%Y-%m-%d %H:%M:%S')
echo "${date} The installer is bootstrapped successfully. Reboot please!"
log "The installer is bootstrapped successfully. Reboot please!"

