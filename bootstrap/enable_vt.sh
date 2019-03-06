#!/bin/bash
#set -x

SCRIPT=$(readlink -f $0)
CWD=$(dirname ${SCRIPT})
PKG_DIR=$(dirname ${CWD})

function usage()
{
    echo "Usage:"
    echo "    enable_vt.sh"
    echo "Example:"
    echo "    enable_vt.sh"
}

if [[ "x$1" == "x-h" ]] || [[ "x$1" == "x--help" ]]; then
    usage
    exit 1
fi

function check_environment()
{
    os_version=$(lsb_release -d -s | awk '{print $2}')
    if [[ ${os_version} == "14.04"* ]]; then
        os_name="trusty"
        apt_options="--yes --force-yes --allow-unauthenticated"
    elif [[ ${os_version} == "16.04"* ]]; then
        os_name="xenial"
        # --force-yes is deprecated after Ubuntu 16.04.x
        apt_options="--yes --allow-unauthenticated"
    else
        echo "Error: Please use Ubuntu 14.04.x or 16.04.x in host node!"
        return 1
    fi

    if [[ "x$(whoami)" != "xroot" ]]; then
        echo "Error: You are not a root user. Please change to the root user and retry!"
        return 1
    fi

    if [ ! -d ${PKG_DIR}/repo ] || [ ! -d ${PKG_DIR}/kernels ]; then
        echo "Error: The installer is not integrated! [repo/kernels] may not exist!"
        return 1
    fi
}

function prepare_repository()
{
    cpu_arch=$(arch)
    if [[ "x${cpu_arch}" == "xx86_64" ]]; then
        arch_flag=""
        arch_name="amd64"
    elif [[ "x${cpu_arch}" == "xaarch64" ]]; then
        arch_flag="-arm"
        arch_name="arm64"
    fi

    # bugfix: couldn't be accessed by user '_apt'. - pkgAcquire::Run (13: Permission denied)
    rm -rf /tmp/repo && mkdir -p /tmp/repo

    # mount the iso file
    if ! mount -v | grep "ubuntu-${os_version}-server-${arch_name}.iso" ; then
        mkdir -p /tmp/repo/iso
        mount -o loop -t iso9660 ${PKG_DIR}/kernels/ubuntu-${os_version}-server-${arch_name}.iso /tmp/repo/iso
    fi

    rsync -azPS ${PKG_DIR}/repo/os/${os_version}${arch_flag}/add_ons /tmp/repo/

    mkdir -p /tmp/repo/pitrix
    rsync -azPS ${PKG_DIR}/repo/pitrix/${os_version}${arch_flag}/ /tmp/repo/pitrix/

    cp -f /etc/apt/sources.list /etc/apt/sources.list.bak # backup
    echo "deb file:///tmp/repo/iso/ubuntu ${os_name} main" > /etc/apt/sources.list
    echo "deb file:///tmp/repo/add_ons/ /" >> /etc/apt/sources.list
    echo "deb file:///tmp/repo/pitrix/ /" >> /etc/apt/sources.list

    apt-get update
    apt-get ${apt_options} install dpkg-dev
    if [ $? -ne 0 ]; then
        echo "Error: Install the dpkg packages failed!"
        return 1
    fi

    if [[ -d /tmp/repo/add_ons ]]; then
        cd /tmp/repo/add_ons
        dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz
        cd ${CWD}
    fi

    if [[ -d /tmp/repo/pitrix ]]; then
        cd /tmp/repo/pitrix
        dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz
        cd ${CWD}
    fi
}

function install_packages()
{
    apt-get update
    apt-get ${apt_options} install bash openssl binutils vim ntp xfsprogs wput acpid iproute tcpdump ethtool bridge-utils dpkg-dev \
        ebtables arptables ifenslave net-tools pv sysstat iotop flex gawk conntrack screen numactl memcached intltool iputils-arping \
        pm-utils expect parallel build-essential autoconf automake pkg-config python python-dev python-bcrypt python-pkg-resources \
        python-pcapy python-netaddr python-meld3 python-setuptools python-pip python-simplejson python-yaml python-m2crypto \
        libssh2-1 libaio1 libnss3 libnetcf1 libyajl2 libnss3 librbd1 libopus0 libaio-dev libavahi-common3 libavahi-client3 \
        libasound2 libjpeg8 libsdl1.2debian libfdt1 libpixman-1-0 libnl-3-200 libxslt1-dev libyaml-0-2 libpq-dev libssl1.0.0 \
        libtool libncurses5 librdmacm1 libcurl3 parted bsdmainutils
    if [ $? -ne 0 ]; then
        echo "Error: Install the base packages failed!"
        return 1
    fi

    # workaround for pitrix-libneonsan
    dpkg -l | grep "pitrix-libneonsan" >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        apt-get ${apt_options} purge pitrix-libneonsan
    fi

    if [[ ${os_version} == "14.04"* ]]; then
        apt-get ${apt_options} install libicu52
    elif [[ ${os_version} == "16.04"* ]]; then
        apt-get ${apt_options} install libicu55
        # workaround for qemu problem on Ubuntu 16.04
        apt-get ${apt_options} install libnfs8
    fi

    apt-get ${apt_options} --reinstall install pitrix-dep-supervisor pitrix-dep-qemu pitrix-dep-libiscsi \
        pitrix-dep-usbredir pitrix-dep-utils pitrix-dep-libvirt pitrix-dep-libvirt-python pitrix-dep-spice pitrix-dep-celt
    if [ $? -ne 0 ]; then
        echo "Error: Install the pitrix packages failed!"
        return 1
    fi

    # set locale
    echo 'LANG="en_US.UTF-8"' > /etc/default/locale
    echo 'LANGUAGE="en_US:en"' >> /etc/default/locale
    echo 'LC_ALL="en_US.UTF-8"' >> /etc/default/locale

    # add supervisord in rc.local
    grep -rqn "/usr/bin/supervisord" /etc/rc.local
    if [ $? -ne 0 ]; then
        sed -i "/^exit/d" /etc/rc.local
        echo "# supervisord" >> /etc/rc.local
        echo "/usr/bin/supervisord" >> /etc/rc.local
        echo "exit 0" >> /etc/rc.local
    fi
    # start supervisord
    if [[ ! -S /var/run/supervisor.sock ]]; then
        /usr/bin/supervisord
    fi
}

function clean_environment()
{
    # umount the iso file
    if mount -v | grep "ubuntu-${os_version}-server-${arch_name}.iso" ; then
        umount /tmp/repo/iso >/dev/null 2>&1
        umount ${PKG_DIR}/kernels/ubuntu-${os_version}-server-${arch_name}.iso >/dev/null 2>&1
    fi

    rm -rf /tmp/repo

    # recovery sources.list
    mv -f /etc/apt/sources.list.bak /etc/apt/sources.list
}

log_file="/root/enable_vt.log"
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
echo -n "${date} Checking whether the host environment is valid ... "
SafeExecFunc check_environment

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Preparing the virtualization packages repository ... "
SafeExecFunc prepare_repository

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Installing the virtualization packages ... "
SafeExecFunc install_packages

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Cleaning and Recovering the host environment ... "
SafeExecFunc clean_environment

date=$(date +'%Y-%m-%d %H:%M:%S')
echo "${date} The virtualization packages has been installed successfully!"
log "The virtualization packages has been installed successfully!"

