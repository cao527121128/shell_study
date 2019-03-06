#!/bin/bash
#set -x

SCRIPT=$(readlink -f $0)
CWD=$(dirname ${SCRIPT})

function usage()
{
    echo "Usage:"
    echo "    bootstrap.sh [-b <bootstrap_mode>] [-p <pitrix_disk>] [-m <mgmt_address>] -i [<pxe_interface>] -n [<ipmi_interface>] -t [<ipmi_network>]"
    echo "      <bootstrap_mode> means the bootstrap mode, such as deploy or upgrade, auto identify is default."
    echo "      <pitrix_disk> is for [deploy] mode, the disk to mount the /pitrix directory."
    echo "      <mgmt_address> is for [deploy] mode, the network address for qingcloud management."
    echo "      <pxe_interface> is for [deploy] mode, the interface to config pxe network for bm installation ."
    echo "      <ipmi_interface> is for [deploy] mode, the interface to config ipmi network for bm installation ."
    echo "      <ipmi_network> is for [deploy] mode, the ipmi network for bm installation ."
    echo "Example:"
    echo "    bootstrap.sh"
    echo "    bootstrap.sh -p sdb1"
    echo "    bootstrap.sh -p sda3 -m 10.16.100.10"
    echo "    bootstrap.sh -p sda3 -m 10.16.100.10 -i eth0 -n eth1 -t 172.30.10.46/24"
    echo "    bootstrap.sh -b upgrade"
}

if [[ "x$1" == "x-h" ]] || [[ "x$1" == "x--help" ]]; then
    usage
    exit 1
fi

BOOTSTRAP_MODE=""
PITRIX_DISK=""
MGMT_ADDRESS=""
PXE_INTERFACE=""
IPMI_INTERFACE=""
IPMI_NETWORK=""
while [[ "x$1" != "x" ]]
do
    case $1 in
        -b)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                BOOTSTRAP_MODE=$2
                shift
            fi
            shift
            ;;
        -p)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                PITRIX_DISK=$2
                shift
            fi
            shift
            ;;
        -m)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                MGMT_ADDRESS=$2
                shift
            fi
            shift
            ;;
        -i)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                PXE_INTERFACE=$2
                shift
            fi
            shift
            ;;
        -n)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                IPMI_INTERFACE=$2
                shift
            fi
            shift
            ;;
        -t)
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
    os_version=`grep -i description /etc/lsb-release | cut -d ' ' -f 2`
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

    if [[ "x`whoami`" != "xroot" ]]; then
        echo "Error: You are not a root user. Please change to the root user and retry!"
        return 1
    fi
}

function check_installer_package()
{
    if [ ! -d $CWD/repo ] || [ ! -d $CWD/kernels ]; then
        echo "Error: The installer is not integrated! [repo/kernels] may not exist!"
        return 1
    fi

    if echo $CWD | grep -q "^/pitrix/" ; then
        echo "Error: The installer package can not be bootstrapped in /pitrix!"
        return 1
    fi
}

function prepare_pitrix_directory()
{
    os_disk_root_part=`lsblk | grep -w "/$" | awk '{print $1}' | awk -F'─' '{print $2}'`
    os_disk=`echo "${os_disk_root_part}" | sed "s/[0-9]//g"`
    data_disk_num=`lsblk | grep disk | grep -v "${os_disk}" | grep -v SWAP | wc -l`
    if [[ "x${PITRIX_DISK}" != "x" ]]; then
        if [[ ${PITRIX_DISK} == "nvme"* ]]; then
            pitrix_disk=`echo ${PITRIX_DISK} | awk -F'p' '{print $1}'`
            pitrix_disk_part=${pitrix_disk}"p1"
            pitrix_disk_part_num="1"
            pitrix_disk_part_start="1G"
            pitrix_disk_part_end="-1"
        else
            pitrix_disk=`echo "${PITRIX_DISK}" | sed "s/[0-9]//g"`
            if [[ "x${pitrix_disk}" == "x${os_disk}" ]]; then
                pitrix_disk_part=${PITRIX_DISK}
                pitrix_disk_part_num=`echo "${PITRIX_DISK}" | sed "s/[a-zA-Z]//g"`
                lsblk | grep '${pitrix_disk}' | grep -q 'SWAP'
                if [ $? -eq 0 ]; then
                    pitrix_disk_part_start=`parted /dev/${pitrix_disk} 'print' | grep swap | awk '{print $3}'`
                else
                    pitrix_disk_part_start=`parted /dev/${pitrix_disk} 'print' | grep -A 10 'Number' | grep '^ '$((pitrix_disk_part_num-1)) | awk '{print $3}'`
                fi
                pitrix_disk_part_end="-1"
            else
                pitrix_disk_part=${pitrix_disk}"1"
                pitrix_disk_part_num="1"
                pitrix_disk_part_start="1G"
                pitrix_disk_part_end="-1"
            fi
        fi
    else
        if [[ "x${data_disk_num}" != "x0" ]]; then
            pitrix_disk=`lsblk | grep disk | grep -v "${os_disk}" | grep -v SWAP | head -n 1 | awk '{print $1}'`
            if [[ ${pitrix_disk} == "nvme"* ]]; then
                pitrix_disk_part=${pitrix_disk}"p1"
            else
                pitrix_disk_part=${pitrix_disk}"1"
            fi
            pitrix_disk_part_num="1"
            pitrix_disk_part_start="1G"
            pitrix_disk_part_end="-1"
        else
            pitrix_disk=""
        fi
    fi

    if [[ "x${pitrix_disk}" != "x" ]]; then
        ls -l /dev/${pitrix_disk}
        if [ $? -ne 0 ]; then
            echo "Error: Can find the pitrix disk [${pitrix_disk}], please check it!"
            return 1
        fi

        # format the pitrix disk and mount the pitrix directory
        umount /pitrix
        umount /dev/${pitrix_disk_part}
        for version in 14.04.5 16.04.3 16.04.3-arm
        do
            umount /var/www/repo/$version/iso
        done
        sed -i "/.*pitrix.*/d" /etc/fstab
        sed -i "/.*iso9660.*/d" /etc/fstab

        parted -a optimal -s /dev/${pitrix_disk} "mklabel gpt"
        parted -a optimal -s /dev/${pitrix_disk} "rm ${pitrix_disk_part_num}"
        parted -a optimal -s /dev/${pitrix_disk} "mkpart primary ${pitrix_disk_part_start} ${pitrix_disk_part_end}"

        # umount before mkfs, important
        umount /pitrix
        umount /dev/${pitrix_disk_part}
        if ! mkfs.ext4 /dev/${pitrix_disk_part}; then
            sleep 10
            # umount before mkfs, important
            umount /pitrix
            umount /dev/${pitrix_disk_part}
            mkfs.ext4 /dev/${pitrix_disk_part}
            if [ $? -ne 0 ]; then
                echo "Error: Can not make ext4 file system on [${pitrix_disk_part}]!"
                return 1
            fi
        fi

        devid=`blkid /dev/${pitrix_disk_part} -o value | head -1`
        echo "UUID=$devid /pitrix ext4  defaults    0  2" >> /etc/fstab

        mkdir -p /pitrix
        mount -a
        if [ $? -ne 0 ]; then
            echo "Error: Auto mount the pitrix disk [${pitrix_disk}] to [/pitrix] directory failed!"
            return 1
        fi
    else
        mkdir -p /pitrix
    fi
}

function get_management_network()
{
    mkdir -p $CWD/conf/variables
    if [[ "x${MGMT_ADDRESS}" != 'x' ]]; then
        firstbox_address=`ip -o addr | grep -v inet6 | grep ${MGMT_ADDRESS} | awk '{print $4}' | awk -F'/' '{print $1}'`
        echo ${firstbox_address} > $CWD/conf/variables/firstbox_address
    else
        mgmt_network_num=`ip -o addr | grep -v inet6 | grep -v '127.0.0.1' | grep -v '192.168.254.' | grep -v '100.100.1.' | wc -l`
        if [[ "x${mgmt_network_num}" == "x1" ]]; then
            firstbox_address=`ip -o addr | grep -v inet6 | grep -v '127.0.0.1' | grep -v '192.168.254.' | grep -v '100.100.1.' | awk '{print $4}' | awk -F'/' '{print $1}'`
            echo ${firstbox_address} > $CWD/conf/variables/firstbox_address
        else
            echo "Error: There are more than one management networks, please specify one!"
            return 1
        fi
    fi
}

function config_ssh_service()
{
    if [[ ! -f /root/.ssh/id_rsa ]]; then
        ssh-keygen -f /root/.ssh/id_rsa -t rsa -N ''
    fi
    sed -i "s/\S*$/node@qingcloud.com/" /root/.ssh/id_rsa.pub
    if ! cat /root/.ssh/authorized_keys | grep "`cat /root/.ssh/id_rsa.pub`" ; then
        cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
    fi
    > /root/.ssh/known_hosts

    ssh_port=`grep Port /etc/ssh/sshd_config | awk '{print $2}'`
    if [[ "x${ssh_port}" == "x" ]]; then
        ssh_port=22
    fi
    echo ${ssh_port} > $CWD/conf/variables/ssh_port
    cp -f $CWD/conf/templates/ssh_config.template /etc/ssh/ssh_config
    cp -f $CWD/conf/templates/sshd_config.template /etc/ssh/sshd_config
    sed -i "s/{{ssh_port}}/${ssh_port}/g" /etc/ssh/ssh_config
    sed -i "s/{{ssh_port}}/${ssh_port}/g" /etc/ssh/sshd_config
    service ssh restart
}

function sync_pitrix_installer()
{
    # need 5 minutes
    rsync -azPS --exclude="/bootstrap.sh" --exclude="/repo" ${CWD}/ /pitrix/

    # make a soft link for pitrix kernels
    if [ ! -L /kernels ]; then
        ln -s /pitrix/kernels /kernels
    fi
}

function prepare_qingcloud_repository()
{
    mkdir -p /var/www/repo
    rsync -azPS $CWD/repo/os/ /var/www/repo/

    # delete old mount point
    sed -i "/.*iso9660.*/d" /etc/fstab
    if [ -f /pitrix/kernels/ubuntu-14.04.5-server-amd64.iso ]; then
        mkdir -p /var/www/repo/14.04.5/iso/
        echo "/pitrix/kernels/ubuntu-14.04.5-server-amd64.iso /var/www/repo/14.04.5/iso iso9660 loop 0  0" >> /etc/fstab
    fi
    if [ -f /pitrix/kernels/ubuntu-16.04.3-server-amd64.iso ]; then
        mkdir -p /var/www/repo/16.04.3/iso/
        echo "/pitrix/kernels/ubuntu-16.04.3-server-amd64.iso /var/www/repo/16.04.3/iso iso9660 loop 0  0" >> /etc/fstab
    fi
    if [ -f /pitrix/kernels/ubuntu-16.04.3-server-arm64.iso ]; then
        mkdir -p /var/www/repo/16.04.3-arm/iso/
        echo "/pitrix/kernels/ubuntu-16.04.3-server-arm64.iso /var/www/repo/16.04.3-arm/iso iso9660 loop 0  0" >> /etc/fstab
    fi
    mount -a
    if [ $? -ne 0 ]; then
        echo "Error: Auto mount the system iso file to corresponding repo iso directory failed!"
        return 1
    fi

    mkdir -p /pitrix/repo
    rsync -azPS $CWD/repo/pitrix/ /pitrix/repo/

    cpu_arch=`arch`
    if [[ "x${cpu_arch}" == "xx86_64" ]]; then
        arch_flag=""
    elif [[ "x${cpu_arch}" == "xaarch64" ]]; then
        arch_flag="-arm"
    fi

    cp -f /etc/apt/sources.list /etc/apt/sources.list.bak # backup
    echo "deb file:///var/www/repo/${os_version}${arch_flag}/iso/ubuntu ${os_name} main" > /etc/apt/sources.list
    echo "deb file:///var/www/repo/${os_version}${arch_flag}/add_ons/ /" >> /etc/apt/sources.list
    echo "deb file:///pitrix/repo/${os_version}${arch_flag}/ /" >> /etc/apt/sources.list
    echo "deb file:///pitrix/repo/indep${arch_flag}/ /" >> /etc/apt/sources.list

    if [[ ${os_version} == "16.04"* ]]; then
        systemctl stop apt-daily.timer; systemctl disable apt-daily.timer
        systemctl stop apt-daily-upgrade.timer; systemctl disable apt-daily-upgrade.timer
        systemctl stop apt-daily.service; systemctl disable apt-daily.service
        systemctl stop apt-daily-upgrade.service; systemctl disable apt-daily-upgrade.service
    fi

    # clean the process using apt or dpkg
    apt_process=`ps -aux | grep -E 'apt|dpkg' | grep -v 'grep' | awk '{print $2}'`
    for process in ${apt_process}
    do
        kill -9 $process
    done
    # remove the apt lock
    rm -f /var/lib/apt/lists/lock

    # make sure the apt-get service is OK
    dpkg --configure -a; apt-get autoclean; apt-get clean
    if [ $? -ne 0 ]; then
        echo "Error: There may be something wrong with apt-get service!"
        return 1
    fi

    apt-get update
    apt-get ${apt_options} install dpkg-dev
    if [ $? -ne 0 ]; then
        echo "Error: Install the dpkg packages failed!"
        return 1
    fi

    # scan all repo
    /pitrix/bin/scan_all.sh
}

function install_base_packages()
{
    # remove apparmor
    ln -s /etc/apparmor.d/usr.sbin.dhcpd /etc/apparmor.d/disable/
    apparmor_parser -R /etc/apparmor.d/usr.sbin.dhcpd
    service apparmor stop
    update-rc.d -f apparmor remove

    apt-get update
    apt-get ${apt_options} install bash openssl binutils vim ntp xfsprogs wput acpid iproute tcpdump ethtool bridge-utils \
        ebtables arptables ifenslave net-tools pv sysstat iotop flex gawk conntrack screen numactl memcached intltool iputils-arping \
        pm-utils expect parallel build-essential autoconf automake pkg-config python python-dev python-bcrypt python-pkg-resources \
        python-pcapy python-netaddr python-meld3 python-setuptools python-pip python-simplejson python-yaml python-m2crypto \
        libssh2-1 libaio1 libnss3 libnetcf1 libyajl2 libnss3 librbd1 libopus0 libaio-dev libavahi-common3 libavahi-client3 \
        libasound2 libjpeg8 libsdl1.2debian libfdt1 libpixman-1-0 libnl-3-200 libxslt1-dev libyaml-0-2 libpq-dev libssl1.0.0 \
        libtool libncurses5 librdmacm1 isc-dhcp-server openipmi ipmitool open-iscsi iscsitarget
    if [ $? -ne 0 ]; then
        echo "Error: Install the base packages failed!"
        return 1
    fi

    if [[ ${os_version} == "14.04"* ]]; then
        # ssh, keep the old ssh configuration, and use DEBIAN_FRONTEND=xxx to jump the package configuration window
        DEBIAN_FRONTEND=noninteractive apt-get ${apt_options} -q install -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" openssh-server openssh-client
        if ! grep -q Ciphers /etc/ssh/sshd_config ; then
            ciphers=`ssh -Q cipher localhost | paste -d , -s`
            if [[ "x$ciphers" != "x" ]]; then
                echo "Ciphers $ciphers" >> /etc/ssh/sshd_config
                service ssh reload
            fi
        fi
    fi

    if [[ ${os_version} == "14.04"* ]]; then
        apt-get ${apt_options} install libicu52
    else
        apt-get ${apt_options} install libicu55
    fi

    # workaround for qemu problem on Ubuntu 16.04
    if [[ ${os_version} == "16.04"* ]]; then
        apt-get ${apt_options} install libnfs8
    fi

    # pitrix-common is used to generate the secret key
    # pitrix-dep-qemu is used to launch vms
    # pitrix-deploy-docs includes all docs for qingcloud
    apt-get ${apt_options} --reinstall install pitrix-common pitrix-dep-qemu pitrix-dep-nbd pitrix-dep-libiscsi pitrix-dep-usbredir pitrix-dep-utils pitrix-libneonsan pitrix-deploy-docs
    if [ $? -ne 0 ]; then
        echo "Error: Install the pitrix packages failed!"
        return 1
    fi

    # highlight prompt
    grep -q '93m' /root/.bashrc
    if [ $? -ne 0 ]; then
        echo 'PS1="\u@\[\e[1;93m\]\h\[\e[m\]:\w\\$\[\e[m\] "' >> /root/.bashrc
    fi

    # modify the timezone to CST(Asia/Shanghai)
    # timedatectl set-timezone Asia/Shanghai
    cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    echo "Asia/Shanghai" > /etc/timezone
}

function install_config_postgresql()
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
    # the pitrix pg package need to install independently
    apt-get ${apt_options} install pitrix-dep-psycopg2
    if [ $? -ne 0 ]; then
        echo "Error: Install the pitrix postgresql packages failed!"
        return 1
    fi

    sed -i "s|5432|5433|g" /etc/postgresql/${pg_version}/main/postgresql.conf
    service postgresql restart

    # create role 'yunify' with password 'pgpasswd'
    su - postgres -c "psql -c \"CREATE ROLE yunify;\" -U postgres"
    su - postgres -c "psql -c \"ALTER ROLE yunify WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION PASSWORD 'pgpasswd';\" -U postgres"

    # create database 'installer'
    su - postgres -c "psql -c \"CREATE DATABASE installer;\" -U postgres"
    su - postgres -c "psql -c \"ALTER DATABASE installer OWNER TO yunify;\" -U postgres"
    su - postgres -c "psql -c \"GRANT ALL ON DATABASE installer TO yunify;\" -U postgres"

    # create and init tables for database 'installer'
    su - postgres -c "psql -f /pitrix/common/installer.sql -d installer -U postgres"
}

function install_config_supervisor()
{
    apt-get ${apt_options} install pitrix-dep-supervisor
    if [ $? -ne 0 ]; then
        echo "Error: Install the supervisor package failed!"
        return 1
    fi

    sed -i "s/exit.*//g" /etc/rc.local
    echo "/usr/bin/supervisord" >> /etc/rc.local
    echo "exit 0" >> /etc/rc.local

    # enable installer webservice in supervisord
    cp -f /pitrix/api/webservice/webservice.conf /etc/supervisor/conf.d/webservice.conf
    if [[ ! -S /var/run/supervisor.sock ]]; then
        /usr/bin/supervisord
    fi
    supervisorctl status
}

function install_config_webinstaller()
{
    mkdir -p /pitrix/web
    rm -rf /pitrix/web/pitrix-webinstaller
    tar zxf /pitrix/repo/web/pitrix-webinstaller.tar.gz -C /pitrix/web/

    cp -f /pitrix/web/pitrix-webinstaller/mysite/settings.py.example /pitrix/web/pitrix-webinstaller/mysite/settings.py
    if [[ "x${firstbox_address}" == "x" ]]; then
        firstbox_address="localhost"
    fi
    sed -i "s/{{api_server_host}}/${firstbox_address}/g" /pitrix/web/pitrix-webinstaller/mysite/settings.py
    sed -i "s/{{api_server_port}}/9999/g" /pitrix/web/pitrix-webinstaller/mysite/settings.py
    sed -i "s/{{api_server_protocol}}/http/g" /pitrix/web/pitrix-webinstaller/mysite/settings.py
}

function install_config_apache2()
{
    apt-get ${apt_options} install apache2 libapache2-mod-wsgi
    if [ $? -ne 0 ]; then
        echo "Error: Install the apache2 packages failed!"
        return 1
    fi

    # enable wsgi
    a2enmod wsgi

    # prepare for software repository, port 80
    grep "/var/www/html" /etc/apache2/sites-available/000-default.conf 2>&1 > /dev/null
    if [[ $? == 0 ]]; then
        sed -i "s/\/var\/www\/html/\/var\/www/g" /etc/apache2/sites-available/000-default.conf
        service apache2 restart
    fi

    # prepare for installer apiserver, port 9999
    cp -f /pitrix/api/apiserver/conf/apiserver.conf.apache2 /etc/apache2/sites-available/apiserver.conf
    a2ensite apiserver.conf

    # prepare for installer webconsole, port 9998
    cp -f /pitrix/web/pitrix-webinstaller/conf/webinstaller.conf.apache2 /etc/apache2/sites-available/webinstaller.conf
    a2ensite webinstaller.conf

    service apache2 restart

    mkdir -p /pitrix/log/api
    touch /pitrix/log/api/apiserver.log
    touch /pitrix/log/api/apiserver.log.wf
    chmod 777 /pitrix/log/api/apiserver.log
    chmod 777 /pitrix/log/api/apiserver.log.wf

    touch /pitrix/log/web_installer.log
    touch /pitrix/log/web_installer.log.wf
    chmod 777 /pitrix/log/web_installer.log
    chmod 777 /pitrix/log/web_installer.log.wf

    touch /pitrix/log/installer.log
    touch /pitrix/log/installer.log.wf
    chmod 777 /pitrix/log/installer.log
    chmod 777 /pitrix/log/installer.log.wf
}

function install_pip_packages()
{
    # pip.conf file may does not make sense
    mkdir -p /root/.pip
    cat << EOF > /root/.pip/pip.conf
[global]
find-links = http://firstbox/repo/pip
trusted-host = firstbox
no-index = yes
disable-pip-version-check = true
timeout = 120
EOF

    if [[ "x${firstbox_address}" == "x" ]]; then
        firstbox_address="127.0.0.1"
    fi

    # add firstbox resolution for pip installation
    if ! grep -q "firstbox" /etc/hosts; then
        echo "${firstbox_address} firstbox" >> /etc/hosts
    fi

    if [[ ${os_version} == "14.04"* ]]; then
        # old version pip may has no option [--trusted-host], such as version 1.5.4
        pip install --upgrade --no-index -f http://${firstbox_address}/repo/pip pip
        # new version pip is located in /usr/local/bin/pip, the command pip will make senses after reboot
        pip_command="/usr/local/bin/pip"
        pip_options="--upgrade --no-index --trusted-host ${firstbox_address} -f http://${firstbox_address}/repo/pip"
    elif [[ ${os_version} == "16.04"* ]]; then
        pip_command="pip"
        pip_options="--upgrade --no-index --trusted-host ${firstbox_address} -f http://${firstbox_address}/repo/pip"
    fi

    # setuptools should be installed firstly, because pip install may use it
    ${pip_command} install ${pip_options} wheel
    ${pip_command} install ${pip_options} setuptools
    ${pip_command} install ${pip_options} setuptools_scm

    ${pip_command} install ${pip_options} pyaml pyzmq Django coffin hamlish-jinja jinja2 python-memcached
    if [ $? -ne 0 ]; then
        echo "Error: Install the pip packages failed!"
        return 1
    fi
}

function config_bm_server()
{
    # config pxe network
    mgmt_address=`cat ${CWD}/conf/variables/firstbox_address`
    MGMT_INTERFACE=`ip -o addr | grep ${mgmt_address} | awk '{print $2}'`
    if [[ "x${PXE_INTERFACE}" == "x" ]] || [[ "x${PXE_INTERFACE}" == "x${MGMT_INTERFACE}" ]]; then
        echo "Info: If PXE interface is not specified, use MGMT interface as PXE interface by default!"

        PXE_INTERFACE=${MGMT_INTERFACE}
        ip addr add 100.100.0.2/16 dev ${PXE_INTERFACE}
        sed -i "s/exit.*//g" /etc/rc.local
        echo "ip addr add 100.100.0.2/16 dev ${PXE_INTERFACE}" >> /etc/rc.local
        echo "exit 0" >> /etc/rc.local
    else
        # here assign a special subnet for pxe
        grep "100.100.0." /etc/network/interfaces
        if [ $? -ne 0 ]; then
            echo "auto ${PXE_INTERFACE}" >> /etc/network/interfaces
            echo "iface ${PXE_INTERFACE} inet static" >> /etc/network/interfaces
            echo "  address 100.100.0.2" >> /etc/network/interfaces
            echo "  netmask 255.255.0.0" >> /etc/network/interfaces
            echo "" >> /etc/network/interfaces
        fi
        ifdown ${PXE_INTERFACE}; ifup ${PXE_INTERFACE}
    fi

    # isc-dhcp-server
    service isc-dhcp-server stop
    update-rc.d -f isc-dhcp-server remove
    # set interface for pxe dhcp server
    sed -i "/^INTERFACES/s/.*/INTERFACES=\"${PXE_INTERFACE}\"/g" /etc/default/isc-dhcp-server

    # config ipmi network
    if [[ "x${IPMI_INTERFACE}" == "x" ]]; then
        echo "Info: If IPMI interface is not specified, the IPMI network can be connected from firstbox by default!"
    else
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

function check_upgrade_condition()
{
    if [ ! -d /pitrix ]; then
        echo "Error: The pitrix directory does not exist, please check it!"
        return 1
    fi
}

function backup_current_installer()
{
    current_upgrade=`cat /pitrix/version | grep -A 4 '=== current ===' | grep 'upgrade' | awk '{print $2}'`
    if [[ "x${current_upgrade}" == "x" ]]; then
        current_upgrade=`cat /pitrix/version | grep 'upgrade' | awk '{print $2}'`
    fi
    if [[ "x${current_upgrade}" == "x" ]]; then
        current_upgrade="20170924"
        sed -i '2i/upgrade: 20170924' /pitrix/version
    fi

    new_upgrade=`cat $CWD/version | grep 'upgrade' | awk '{print $2}'`
    if [ ${new_upgrade} -lt ${current_upgrade} ]; then
        echo "Error: The new upgrade [${new_upgrade}] is behind the current upgrade [${current_upgrade}]!"
        return 1
    fi

    backup_dir="/pitrix/backup"
    new_backup=${backup_dir}/installer_${current_upgrade}
    mkdir -p ${new_backup}

    # installer code
    rsync -azPS --include="/api" --include="/bin" --include="/build" --include="/check" --include="/common" --include="/conf" --include="/config" --include="/deploy" \
        --include="/devops" --include="/install" --include="/node" --include="/test" --include="/upgrade" --include="/version" --exclude="/*" /pitrix/ ${new_backup}/
    # pitrix repo
    mkdir -p ${new_backup}/pitrix-repo
    rsync -azPS /pitrix/repo/ ${new_backup}/pitrix-repo/
    # os repo
    mkdir -p ${new_backup}/os-repo
    rsync -azPS --exclude='*/iso' /var/www/repo/ ${new_backup}/os-repo/

    su - postgres -c "pg_dumpall --clean | gzip > /tmp/installer_pg_dumpall.gz"
    mv /tmp/installer_pg_dumpall.gz ${new_backup}/
}

function update_new_installer()
{
    rsync -azPS ${CWD}/conf/templates/ /pitrix/conf/templates/
    rsync -azPS --exclude="/bootstrap.sh" --exclude="/version" --exclude="/repo" --exclude="/conf" ${CWD}/ /pitrix/

    if [ ! -d /var/www/repo/16.04.3 ]; then
        mkdir -p /var/www/repo/16.04.3/iso
        echo "/pitrix/kernels/ubuntu-16.04.3-server-amd64.iso /var/www/repo/16.04.3/iso iso9660 loop 0  0" >> /etc/fstab
        mount -a
    fi

    cloud_type=`cat /pitrix/conf/variables/cloud_type`
    if [[ "x${cloud_type}" == "xpublic" ]]; then
        # do not update /pitrix/repo/indep in public cloud
        rsync -azPS --exclude='/indep' $CWD/repo/pitrix/ /pitrix/repo/
        rsync -azPS $CWD/repo/os/ /var/www/repo/
    else
        rsync -azPS $CWD/repo/pitrix/ /pitrix/repo/
        rsync -azPS $CWD/repo/os/ /var/www/repo/
    fi

    # scan the new repo
    /pitrix/bin/scan_all.sh

    # restart the webservice
    supervisorctl restart webservice

    # new version file
    if ! grep -q '=== current ===' /pitrix/version ; then
        sed -i "1i\=== current ===" /pitrix/version
        echo "" >> /pitrix/version
    fi
    echo "== upgrading ==" > /tmp/new_version
    cat $CWD/version >> /tmp/new_version
    echo "" >> /tmp/new_version
    # the content blew current need to add into new version file
    grep -A 1000 '=== current ===' /pitrix/version >> /tmp/new_version
    mv /tmp/new_version /pitrix/version
}

function prepare_installer_patches()
{
    current_installer=`cat /pitrix/version | grep -A 4 '=== current ===' | grep 'installer' | awk '{print $2}'` # 3.1
    current_installer_a=`echo ${current_installer} | awk -F'.' '{print $1}'` # 3
    current_installer_b=`echo ${current_installer} | awk -F'.' '{print $2}'` # 1
    if [ ${current_installer_b} -lt 10 ]; then
        current_installer_b="0"${current_installer_b}
    fi
    current_installer_c=`echo ${current_installer} | awk -F'.' '{print $3}'` # Null
    if [[ "x${current_installer_c}" == "x" ]]; then
        current_installer_c="00"
    elif [ ${current_installer_c} -lt 10 ]; then
        current_installer_c="0"${current_installer_c}
    fi
    current_installer_int=${current_installer_b}${current_installer_b}${current_installer_c}

    new_installer=`cat /pitrix/version | grep -A 4 '== upgrading ==' | grep 'installer' | awk '{print $2}'` # 3.2.4
    new_installer_a=`echo ${new_installer} | awk -F'.' '{print $1}'` # 3
    new_installer_b=`echo ${new_installer} | awk -F'.' '{print $2}'` # 2
    if [ ${new_installer_b} -lt 10 ]; then
        new_installer_b="0"${new_installer_b}
    fi
    new_installer_c=`echo ${new_installer} | awk -F'.' '{print $3}'` # 4
    if [[ "x${new_installer_c}" == "x" ]]; then
        new_installer_c="00"
    elif [ ${new_installer_c} -lt 10 ]; then
        new_installer_c="0"${new_installer_c}
    fi
    new_installer_int=${new_installer_b}${new_installer_b}${new_installer_c}

    patches_dir=/pitrix/upgrade/patches/*
    new_patches_dir=/pitrix/upgrade/new_patches/
    rm -rf ${new_patches_dir}
    mkdir -p ${new_patches_dir}

    for patch_dir in ${patches_dir}
    do
        patch_name=`basename ${patch_dir}`
        if [[ "x${patch_name}" == "xchangelog" ]]; then
            continue
        fi

        patch_name_a=`echo ${patch_name} | awk -F'.' '{print $1}'`
        patch_name_b=`echo ${patch_name} | awk -F'.' '{print $2}'`
        if [ ${patch_name_b} -lt 10 ]; then
            patch_name_b="0"${patch_name_b}
        fi
        patch_name_c=`echo ${patch_name} | awk -F'.' '{print $3}'`
        if [[ "x${patch_name_c}" == "x" ]]; then
            patch_name_c="00"
        elif [ ${patch_name_c} -lt 10 ]; then
            patch_name_c="0"${patch_name_c}
        fi
        patch_name_int=${patch_name_b}${patch_name_b}${patch_name_c}

        if [ ${patch_name_int} -ge ${current_installer_int} ] && [ ${patch_name_int} -le ${new_installer_int} ]; then
            rsync -azPS ${patch_dir} ${new_patches_dir}
        fi
    done
}

function apply_installer_patches()
{
    new_patches=/pitrix/upgrade/new_patches/*

    for new_patch in ${new_patches}
    do
        scripts=${new_patch}/*patch*.sh
        ls -1 $scripts >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            for script in $scripts
            do
                $script
                if [ $? -ne 0 ]; then
                    echo "Error: Exec the script [$script] failed!"
                    return 1
                fi
            done
        fi

        sqls=${new_patch}/*sql
        ls -1 $sqls >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            rsync -azPS ${sqls} /tmp/
            for sql in $sqls
            do
                # /tmp/test.sql --> test.sql
                sqlfile=${sql##*/}
                # test.sql --> test
                db=${sqlfile%.sql}
                su - postgres -c "psql -d $db -f /tmp/${sqlfile}"
            done
        fi
    done

    # clean
    rm -rf /pitrix/upgrade/new_patches
}

function upgrade_config_webinstaller()
{
    rm -rf /pitrix/web/pitrix-webinstaller
    tar zxf /pitrix/repo/web/pitrix-webinstaller.tar.gz -C /pitrix/web/

    firstbox_address=`cat /pitrix/conf/variables/firstbox_address`
    cp -f /pitrix/web/pitrix-webinstaller/mysite/settings.py.example /pitrix/web/pitrix-webinstaller/mysite/settings.py
    sed -i "s/{{api_server_host}}/${firstbox_address}/g" /pitrix/web/pitrix-webinstaller/mysite/settings.py
    sed -i "s/{{api_server_port}}/9999/g" /pitrix/web/pitrix-webinstaller/mysite/settings.py
    sed -i "s/{{api_server_protocol}}/http/g" /pitrix/web/pitrix-webinstaller/mysite/settings.py

    service apache2 restart
}

log_file=/root/bootstrap.log
if [ -f ${log_file} ]; then
    echo "" >> ${log_file}
fi

function log()
{
    msg=$*
    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo "$date $msg" >> ${log_file}
}

function SafeExecFunc()
{
    local func=$1
    log "Execing the function [$func] ..."
    $func >>${log_file} 2>&1
    if [ $? -eq 0 ]; then
        echo -n "OK." && echo ""
        log "Exec the function [$func] OK."
    else
        echo -n "Error!" && echo ""
        log "Exec the function [$func] Error!"
        exit 1
    fi
}

if [[ "x${BOOTSTRAP_MODE}" == "x" ]]; then
    ret1=`ping -c 1 -w 1 proxy >/dev/null 2>&1 && echo 0 || echo 1`
    ret2=`ping -c 1 -w 1 pgpool >/dev/null 2>&1 && echo 0 || echo 1`
    if [[ "x$ret1" == "x1" ]] && [[ "x$ret2" == "x1" ]]; then
        bootstrap_mode="deploy"
    else
        bootstrap_mode="upgrade"
    fi
elif [[ "x${BOOTSTRAP_MODE}" == "xdeploy" ]] || [[ "x${BOOTSTRAP_MODE}" == "xupgrade" ]]; then
    bootstrap_mode="${BOOTSTRAP_MODE}"
else
    echo "Error: The bootstrap mode [${BOOTSTRAP_MODE}] you provide in invalid, please check it!"
    exit 1
fi

date=`date +'%Y-%m-%d %H:%M:%S'`
echo "$date Info: The bootstrap mode is [${bootstrap_mode}]."
log "Info: The bootstrap mode is [${bootstrap_mode}]."

if [[ "x${bootstrap_mode}" == "xdeploy" ]]; then
    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Checking whether the os environment is valid ... "
    SafeExecFunc check_os_environment

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Checking whether the installer package is ready ... "
    SafeExecFunc check_installer_package

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Preparing the pitrix directory ... "
    SafeExecFunc prepare_pitrix_directory

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Getting the qingcloud management network ... "
    SafeExecFunc get_management_network

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Configuring the firstbox ssh service ... "
    SafeExecFunc config_ssh_service

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Syncing the installer to pitrix directory ... "
    SafeExecFunc sync_pitrix_installer

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Preparing the qingcloud repository ... "
    SafeExecFunc prepare_qingcloud_repository

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Installing the base packages ... "
    SafeExecFunc install_base_packages

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Installing and Configuring postgresql ... "
    SafeExecFunc install_config_postgresql

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Installing and Configuring supervisord ... "
    SafeExecFunc install_config_supervisor

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Installing and Configuring webinstaller ... "
    SafeExecFunc install_config_webinstaller

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Installing and Configuring apache2 ... "
    SafeExecFunc install_config_apache2

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Installing the pip packages ... "
    SafeExecFunc install_pip_packages

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Installing and Configuring the bm module ... "
    SafeExecFunc config_bm_server
else
    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Checking whether the os environment is valid ... "
    SafeExecFunc check_os_environment

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Checking whether the installer package is ready ... "
    SafeExecFunc check_installer_package

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Checking whether the upgrade condition is met ... "
    SafeExecFunc check_upgrade_condition

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Backing up the current installer ... "
    SafeExecFunc backup_current_installer

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Updating the installer using new installer ... "
    SafeExecFunc update_new_installer

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Preparing the installer patches ..."
    SafeExecFunc prepare_installer_patches

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Applying the installer patches ..."
    SafeExecFunc apply_installer_patches

    date=`date +'%Y-%m-%d %H:%M:%S'`
    echo -n "$date Upgrading and Configuring webinstaller ..."
    SafeExecFunc upgrade_config_webinstaller
fi

date=`date +'%Y-%m-%d %H:%M:%S'`
echo "$date The installer is bootstrapped successfully. Reboot please!"
log "The installer is bootstrapped successfully. Reboot please!"
