#!/bin/bash
#set -x

SCRIPT=$(readlink -f $0)
CWD=$(dirname ${SCRIPT})
PKG_DIR=$(dirname ${CWD})

function usage()
{
    echo "Usage:"
    echo "    launch_fb.sh [-p <pitrix_disk>] [-o <os_version>] [-m <mgmt_interface>] -a <mgmt_address> [-n <mgmt_netmask>] [-g <mgmt_gateway>] [-i <pxe_interface>] [-f]"
    echo "      <pitrix_disk> means the disk to mount the /pitrix directory."
    echo "      <os_version> means the qingcloud-firstbox os version, version of the current physical is default."
    echo "      <mgmt_interface> means the interface to create bridge to host qingcloud-firstbox"
    echo "      <mgmt_address> means the qingcloud-firstbox mgmt address, do not conflict."
    echo "      <mgmt_netmask> means the qingcloud-firstbox mgmt netmask, 255.255.255.0 is default."
    echo "      <mgmt_gateway> means the qingcloud-firstbox mgmt gateway, .254 is default."
    echo "      <pxe_interface> means the interface to config pxe network for bm provision."
    echo "      <-f> launch the firstbox no matter the firstbox have been launched"
    echo "Example:"
    echo "    launch_fb.sh -a 10.16.100.2"
    echo "    launch_fb.sh -a 10.16.100.2 -f"
    echo "    launch_fb.sh -p sdb1 -a 10.16.100.2"
    echo "    launch_fb.sh -p sda3 -o 16.04.3 -m bond0 -a 10.16.100.2 -i eth0"
}

if [[ "x$1" == "x-h" ]] || [[ "x$1" == "x--help" ]]; then
    usage
    exit 1
fi

PITRIX_DISK=""
OS_VERSION=""
MGMT_INTERFACE=""
MGMT_ADDRESS=""
MGMT_NETMASK=""
MGMT_GATEWAY=""
PXE_INTERFACE=""
FORCE="False"

while [[ "x$1" != "x" ]]
do
    case $1 in
        -p)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                PITRIX_DISK=$2
                shift
            fi
            shift
            ;;
        -o)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                OS_VERSION=$2
                shift
            fi
            shift
            ;;
        -m)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                MGMT_INTERFACE=$2
                shift
            fi
            shift
            ;;
        -a)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                MGMT_ADDRESS=$2
                shift
            fi
            shift
            ;;
        -n)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                MGMT_NETMASK=$2
                shift
            fi
            shift
            ;;
        -g)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                MGMT_GATEWAY=$2
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
        -f)
            FORCE="True"
            shift
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

if [ -f "/pitrix/kernels/qingcloud-firstbox.Done" ]; then
    if [[ "x${FORCE}" == "xFalse" ]]; then
        echo "The VM [qingcloud-firstbox] has been launched."
        exit 1
    else
        date=$(date +'%Y-%m-%d %H:%M:%S')
        echo -n "${date} Deleting old qingcloud-firstbox ... "
        virsh destroy qingcloud-firstbox >/dev/null 2>&1
        virsh undefine qingcloud-firstbox >/dev/null 2>&1
        rm -f /pitrix/kernels/qingcloud-firstbox*
        echo -n "OK." && echo ""
    fi
fi

if [[ "x${OS_VERSION}" == "x" ]]; then
    OS_VERSION=$(lsb_release -d -s | awk '{print $2}')
fi

if [[ "x${MGMT_ADDRESS}" == "x" ]]; then
    echo "Error: The argument [mgmt_address] is empty, please check!"
    exit 1
fi

ip route get ${MGMT_ADDRESS} >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: The address [${MGMT_ADDRESS}] may be invalid, please check!"
    exit 1
fi

ip route get ${MGMT_ADDRESS} | head -n 1 | grep "via" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Error: Can not find the direct link interface for address [${MGMT_ADDRESS}]!"
    exit 1
fi

ip route get ${MGMT_ADDRESS} | head -n 1 | grep "local" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Error: The address [${MGMT_ADDRESS}] may be local exist, please check!"
    exit 1
fi

# eth0 / bond0 / br0 / ...
EXPECTED_MGMT_INTERFACE=$(ip route get ${MGMT_ADDRESS} | head -n 1 | awk '{print $3}')
if [[ "x${MGMT_INTERFACE}" == "x" ]] || [[ "x${EXPECTED_MGMT_INTERFACE}" == "xbr0" ]]; then
    MGMT_INTERFACE="${EXPECTED_MGMT_INTERFACE}"
elif [[ "x${MGMT_INTERFACE}" != "x${EXPECTED_MGMT_INTERFACE}" ]]; then
    echo "Error: The interface [${MGMT_INTERFACE}] you provide is not matched to address [${MGMT_ADDRESS}]!"
    exit 1
fi

EXPECTED_MGMT_NETMASK=$(ifconfig | grep -A 5 "${MGMT_INTERFACE}" | grep "Mask:" | awk '{print $4}' | awk -F ':' '{print $2}')
if [[ "x${MGMT_NETMASK}" == "x" ]]; then
    MGMT_NETMASK="${EXPECTED_MGMT_NETMASK}"
elif [[ "x${MGMT_NETMASK}" != "x${EXPECTED_MGMT_NETMASK}" ]]; then
    echo "Error: The netmask [${MGMT_NETMASK}] you provide is not matched to address [${MGMT_ADDRESS}]!"
    exit 1
fi

mgmt_has_default_gw="false"
if [[ "x${MGMT_GATEWAY}" == "x" ]]; then
    ip route | grep "default" | grep "${MGMT_INTERFACE}" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        MGMT_GATEWAY=$(ip route | grep "default" | awk '{print $3}')
        mgmt_has_default_gw="true"
    else
        echo "Error: The gateway [mgmt_gateway] is empty, please check!"
        exit 1
    fi
else
    ip route | grep "default" | grep ${MGMT_GATEWAY} >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        mgmt_has_default_gw="true"
    fi
    ip route get ${MGMT_GATEWAY} | head -n 1 | grep "${MGMT_INTERFACE}" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: The gateway [${MGMT_GATEWAY}] you provide is not matched address [${MGMT_ADDRESS}]!"
        exit 1
    fi
fi

function create_network_bridge()
{
    HOST_MGMT_ADDRESS=$(ifconfig | grep -A 5 "${MGMT_INTERFACE}" | grep "Mask:" | awk '{print $2}' | awk -F':' '{print $2}')

    > /etc/rc.local.qingcloud-firstbox
    echo "#!/bin/bash" >> /etc/rc.local.qingcloud-firstbox
    echo "" >> /etc/rc.local.qingcloud-firstbox

    # get real mgmt interface, br0 --> eth0
    if [[ "x${MGMT_INTERFACE}" == "xbr0" ]]; then
        interface_count=$(ls /sys/devices/virtual/net/br0/brif | grep -v vnet | wc -l)
        if [ ${interface_count} -ne 1 ]; then
            echo "Error: Can get the real mgmt interface from br0 bridge!"
            return 1
        fi
        REAL_MGMT_INTERFACE=$(ls /sys/devices/virtual/net/br0/brif | grep -v vnet)
    else
        REAL_MGMT_INTERFACE="${MGMT_INTERFACE}"
    fi

    if [[ "x${mgmt_has_default_gw}" == "xtrue" ]]; then
        echo "# add br0 for qingcloud-firstbox mgmt network" >> /etc/rc.local.qingcloud-firstbox
        echo "ifconfig | grep '^br0'" >> /etc/rc.local.qingcloud-firstbox
        echo "if [ \$? -ne 0 ]; then" >> /etc/rc.local.qingcloud-firstbox
        echo "    brctl addbr br0" >> /etc/rc.local.qingcloud-firstbox
        echo "    ifconfig ${REAL_MGMT_INTERFACE} 0.0.0.0" >> /etc/rc.local.qingcloud-firstbox
        echo "    brctl addif br0 ${REAL_MGMT_INTERFACE}" >> /etc/rc.local.qingcloud-firstbox
        echo "    ifconfig br0 ${HOST_MGMT_ADDRESS} netmask ${MGMT_NETMASK} up" >> /etc/rc.local.qingcloud-firstbox
        echo "    route add default gw ${MGMT_GATEWAY}" >> /etc/rc.local.qingcloud-firstbox
        echo "fi" >> /etc/rc.local.qingcloud-firstbox
        echo "" >> /etc/rc.local.qingcloud-firstbox
    else
        echo "# add br0 for qingcloud-firstbox mgmt network" >> /etc/rc.local.qingcloud-firstbox
        echo "ifconfig | grep '^br0'" >> /etc/rc.local.qingcloud-firstbox
        echo "if [ \$? -ne 0 ]; then" >> /etc/rc.local.qingcloud-firstbox
        echo "    brctl addbr br0" >> /etc/rc.local.qingcloud-firstbox
        echo "    ifconfig ${REAL_MGMT_INTERFACE} 0.0.0.0" >> /etc/rc.local.qingcloud-firstbox
        echo "    brctl addif br0 ${REAL_MGMT_INTERFACE}" >> /etc/rc.local.qingcloud-firstbox
        echo "    ifconfig br0 ${HOST_MGMT_ADDRESS} netmask ${MGMT_NETMASK} up" >> /etc/rc.local.qingcloud-firstbox
        echo "fi" >> /etc/rc.local.qingcloud-firstbox
        echo "" >> /etc/rc.local.qingcloud-firstbox
    fi

    if [[ "x${PXE_INTERFACE}" != "x" ]]; then
        echo "# add br_pxe for qingcloud-firstbox mgmt network" >> /etc/rc.local.qingcloud-firstbox
        echo "ifconfig | grep '^br_pxe'" >> /etc/rc.local.qingcloud-firstbox
        echo "if [ \$? -ne 0 ]; then" >> /etc/rc.local.qingcloud-firstbox
        echo "    brctl addbr br_pxe" >> /etc/rc.local.qingcloud-firstbox
        echo "    brctl addif br_pxe ${PXE_INTERFACE}" >> /etc/rc.local.qingcloud-firstbox
        echo "    ifconfig br_pxe up" >> /etc/rc.local.qingcloud-firstbox
        echo "fi" >> /etc/rc.local.qingcloud-firstbox
        echo "" >> /etc/rc.local.qingcloud-firstbox
    else
        echo "# add br_pxe for qingcloud-firstbox mgmt network" >> /etc/rc.local.qingcloud-firstbox
        echo "ifconfig | grep '^br_pxe'" >> /etc/rc.local.qingcloud-firstbox
        echo "if [ \$? -ne 0 ]; then" >> /etc/rc.local.qingcloud-firstbox
        echo "    brctl addbr br_pxe" >> /etc/rc.local.qingcloud-firstbox
        echo "    ifconfig br_pxe up" >> /etc/rc.local.qingcloud-firstbox
        echo "fi" >> /etc/rc.local.qingcloud-firstbox
        echo "" >> /etc/rc.local.qingcloud-firstbox
    fi

    # add rc.local.qingcloud-firstbox to rc.local
    chmod +x /etc/rc.local.qingcloud-firstbox
    bash /etc/rc.local.qingcloud-firstbox

    grep -rqn "/etc/rc.local.qingcloud-firstbox" /etc/rc.local
    if [ $? -ne 0 ]; then
        match="# supervisord"
        str="/etc/rc.local.qingcloud-firstbox\n"
        sed -i "/^${match}/i ${str}" /etc/rc.local
    fi
}

function prepare_pitrix_directory()
{
    os_disk_root_part=$(lsblk | grep -w "/$" | awk '{print $1}' | awk -F '─' '{print $2}')
    os_disk=$(echo "${os_disk_root_part}" | sed "s/[0-9]//g")
    data_disk_num=$(lsblk | grep disk | grep -v "${os_disk}" | grep -v 'SWAP' | wc -l)
    if [[ "x${PITRIX_DISK}" != "x" ]]; then
        if [[ ${PITRIX_DISK} == "nvme"* ]]; then
            pitrix_disk=$(echo ${PITRIX_DISK} | awk -F 'p' '{print $1}')
            pitrix_disk_part="${pitrix_disk}p1"
            pitrix_disk_part_num="1"
            pitrix_disk_part_start="1G"
            pitrix_disk_part_end="-1"
        else
            pitrix_disk=$(echo "${PITRIX_DISK}" | sed "s/[0-9]//g")
            if [[ "x${pitrix_disk}" == "x${os_disk}" ]]; then
                pitrix_disk_part=${PITRIX_DISK}
                pitrix_disk_part_num=$(echo "${PITRIX_DISK}" | sed "s/[a-zA-Z]//g")
                lsblk | grep "${pitrix_disk}" | grep -q 'SWAP'
                if [ $? -eq 0 ]; then
                    pitrix_disk_part_start=$(parted /dev/${pitrix_disk} 'print' | grep swap | awk '{print $3}')
                else
                    pitrix_disk_part_start=$(parted /dev/${pitrix_disk} 'print' | grep -A 10 'Number' | grep '^ '$((pitrix_disk_part_num-1)) | awk '{print $3}')
                fi
                pitrix_disk_part_end="-1"
            else
                pitrix_disk_part="${pitrix_disk}1"
                pitrix_disk_part_num="1"
                pitrix_disk_part_start="1G"
                pitrix_disk_part_end="-1"
            fi
        fi
    else
        if [[ "x${data_disk_num}" != "x0" ]]; then
            pitrix_disk=$(lsblk | grep disk | grep -v "${os_disk}" | grep -v SWAP | head -n 1 | awk '{print $1}')
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
        for version in 14.04.5 16.04.3 16.04.3-arm 16.04.5
        do
            umount /var/www/repo/${version}/iso
        done
        sed -i "/.*pitrix.*/d" /etc/fstab
        sed -i "/.*iso9660.*/d" /etc/fstab

        parted -a optimal -s /dev/${pitrix_disk} "mklabel gpt"
        parted -a optimal -s /dev/${pitrix_disk} "rm ${pitrix_disk_part_num}"
        parted -a optimal -s /dev/${pitrix_disk} "mkpart primary ${pitrix_disk_part_start} ${pitrix_disk_part_end}"

        # umount before mkfs, important
        umount /pitrix
        umount /dev/${pitrix_disk_part}
        if ! mkfs.ext4 -F /dev/${pitrix_disk_part}; then
            sleep 10
            # umount before mkfs, important
            umount /pitrix
            umount /dev/${pitrix_disk_part}
            mkfs.ext4 -F /dev/${pitrix_disk_part}
            if [ $? -ne 0 ]; then
                echo "Error: Can not make ext4 file system on [${pitrix_disk_part}]!"
                return 1
            fi
        fi

        dev_id=$(blkid /dev/${pitrix_disk_part} -o value | head -1)
        echo "UUID=${dev_id} /pitrix ext4  defaults    0  2" >> /etc/fstab

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

function generate_firstbox_setting()
{
    if [[ ${OS_VERSION} == "14.04"* ]]; then
        OS_NAME="trusty"
    elif [[ ${OS_VERSION} == "16.04"* ]]; then
        OS_NAME="xenial"
    else
        echo "Error: OS version [${OS_VERSION}] is not supported!"
        return 1
    fi

    # general settings
    cpu_arch=$(arch)
    cpu_cores="4"
    memory_size="4096"
    os_name=${OS_NAME}
    os_version=${OS_VERSION}
    hostname="qingcloud-firstbox"

    # mgmt network settings
    mgmt_network_interface="eth0"
    mgmt_network_address=${MGMT_ADDRESS}
    mgmt_network_netmask=${MGMT_NETMASK}
    mgmt_network_gateway=${MGMT_GATEWAY}
    mgmt_network_dns_servers="114.114.114.114 119.29.29.29 1.2.4.8"
    mgmt_network_mac_address="$(hexdump -n3 -e'/3 "00:16:3e" 3/1 ":%02x"' /dev/random)"

    # bm pxe network settings
    bm_pxe_network_interface="eth1"
    bm_pxe_network_address="100.100.0.2"
    bm_pxe_network_netmask="255.255.0.0"
    bm_pxe_network_mac_address="$(hexdump -n3 -e'/3 "00:16:3e" 3/1 ":%02x"' /dev/random)"

    # physical host
    physical_host=${HOST_MGMT_ADDRESS}
    physical_host_mgmt_network_interface="br0"
    physical_host_pxe_network_interface="br_pxe"
}

function create_firstbox_image()
{
    mkdir -p /pitrix/kernels/
    # make a soft link for pitrix kernels
    if [ ! -L /kernels ]; then
        ln -s /pitrix/kernels /kernels
    fi

    # copy the base img
    cp -af ${PKG_DIR}/kernels/*.img /pitrix/kernels/

    cd /pitrix/kernels/
    if [[ "x${os_version}" == "x14.04.5" ]]; then
        # there is CPU 100% bug when apache2 run on ubuntu 14.04.5
        base_file="/pitrix/kernels/ksnode16043c.img"
    elif [[ "x${os_version}" == "x16.04.3" ]]; then
        base_file="/pitrix/kernels/ksnode16043c.img"
    elif [[ "x${os_version}" == "x16.04.5" ]]; then
        base_file="/pitrix/kernels/ksnode16045a.img"
    fi
    img_file="/pitrix/kernels/${hostname}.img"
    rm -f ${img_file}
    qemu-img create -f qcow2 -b ${base_file} ${img_file}
    cd ${CWD}
}

function mount_firstbox_image()
{
    img_mnt="/mnt/${hostname}"
    if [[ -d ${img_mnt} ]]; then
        umount ${img_mnt}
        rm -rf ${img_mnt}
        qemu-nbd -d /dev/nbd0
    fi
    modprobe nbd
    qemu-nbd -d /dev/nbd0
    sleep 3
    qemu-nbd -c /dev/nbd0 ${img_file}

    count=10
    while [ $(lsblk | grep nbd0 | wc -l) -le 1 ]
    do
        if [ ${count} -le 0 ]; then
            echo 'Connect to nbd0 error!'
            return 1
        fi
        # workaround about mounting nbd no partition in ubuntu16045
        # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=824553
        partprobe /dev/nbd0
        sleep 1
        count=$((count-1))
    done

    # get the nbd partition number which the vm root disk partition is mapped
    partition_num=$(parted /dev/nbd0 'p' | grep -vE 'EFI|swap' | grep 'ext4' | awk '{print $1}')
    umount "/dev/nbd0p${partition_num}"
    mkdir -p ${img_mnt}
    mount "/dev/nbd0p${partition_num}" ${img_mnt}

    # copy qingcloud-installer*.tar.gz
    package_file=$(find /root/ -type f -name "qingcloud-installer*.tar.gz" | sort | tail -n 1)
    if [[ -f "${package_file}" ]]; then
        rsync -azPS ${package_file} ${img_mnt}/root/
    fi

    # set locale
    echo 'LANG="en_US.UTF-8"' > ${img_mnt}/etc/default/locale
    echo 'LANGUAGE="en_US:en"' >> ${img_mnt}/etc/default/locale
    echo 'LC_ALL="en_US.UTF-8"' >> ${img_mnt}/etc/default/locale
}

function config_firstbox_network_interfaces()
{
    iffile="/tmp/${hostname}.iffile"
    > ${iffile}

    echo "auto lo" >> ${iffile}
    echo "iface lo inet loopback" >> ${iffile}
    echo "" >> ${iffile}

    echo "# mgmt network" >> ${iffile}
    echo "auto ${mgmt_network_interface}" >> ${iffile}
    echo "iface ${mgmt_network_interface} inet static" >> ${iffile}
    echo "  address ${mgmt_network_address}" >> ${iffile}
    echo "  netmask ${mgmt_network_netmask}" >> ${iffile}
    echo "  dns-nameservers ${mgmt_network_dns_servers}" >> ${iffile}
    if [[ "x${mgmt_network_gateway}" != "x" ]]; then
        echo "  gateway ${mgmt_network_gateway}" >> ${iffile}
    fi
    echo "" >> ${iffile}

    if [[ "x${bm_pxe_network_address}" != "x" ]]; then
        echo "# bm pxe network" >> ${iffile}
        echo "auto ${bm_pxe_network_interface}" >> ${iffile}
        echo "iface ${bm_pxe_network_interface} inet static" >> ${iffile}
        echo "  address ${bm_pxe_network_address}" >> ${iffile}
        echo "  netmask ${bm_pxe_network_netmask}" >> ${iffile}
        echo "" >> ${iffile}
    fi
    echo "" >> ${iffile}

    mv ${iffile} ${img_mnt}/etc/network/interfaces

    # set the hostname and hosts
    echo "${hostname}" > ${img_mnt}/etc/hostname
    echo "127.0.0.1    localhost" > ${img_mnt}/etc/hosts
    echo "127.0.1.1    ${hostname}" >> ${img_mnt}/etc/hosts
}

function config_firstbox_ssh_service()
{
    if [ ! -f /root/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -P "" -C "QingCloud" -f '/root/.ssh/id_rsa'
    fi
    if ! cat /root/.ssh/id_rsa.pub | xargs -I R grep R /root/.ssh/authorized_keys; then
        echo -e "\n" >> /root/.ssh/authorized_keys
        cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
    fi
    rm -rf ${img_mnt}/root/.ssh
    cp -rf ~/.ssh ${img_mnt}/root/
    cp -f /etc/ssh/ssh_config ${img_mnt}/etc/ssh/
    cp -f /etc/ssh/sshd_config ${img_mnt}/etc/ssh/
}

function config_firstbox_systemd()
{
    system_file="/tmp/qingcloud_continue.service"
    echo "[Unit]" > ${system_file}
    echo "Description=QingCloud Installer Reboot" >> ${system_file}
    echo "After=network.target postgresql@9.5-main.service apache2.service rc-local.service" >> ${system_file}
    echo "" >> ${system_file}
    echo "[Service]" >> ${system_file}
    echo "Type=simple" >> ${system_file}
    echo "ExecStart=/pitrix/install/qingcloud_continue.py" >> ${system_file}
    echo "" >> ${system_file}
    echo "[Install]" >> ${system_file}
    echo "WantedBy=multi-user.target" >> ${system_file}

    mv ${system_file} ${img_mnt}/etc/systemd/system/
}

function umount_firstbox_image()
{
    # umount the vm image
    umount ${img_mnt}
    rm -rf ${img_mnt}
    qemu-nbd -d /dev/nbd0
}

function prepare_firstbox_xml()
{
    xml_file="/pitrix/kernels/${hostname}.xml"
    xml_template="${CWD}/templates/qingcloud-firstbox.xml.template"
    cp -f ${xml_template} ${xml_file}

    sed -i "s/{{cpu_cores}}/${cpu_cores}/g" ${xml_file}
    sed -i "s/{{memory_size}}/${memory_size}/g" ${xml_file}

    vm_image="/pitrix/kernels/${hostname}.img"
    sed -i "s|{{vm_image}}|${vm_image}|g" ${xml_file}

    sed -i "s/{{mgmt_mac}}/${mgmt_network_mac_address}/g" ${xml_file}
    sed -i "s/{{mgmt_bridge}}/${physical_host_mgmt_network_interface}/g" ${xml_file}

    sed -i "s/{{pxe_mac}}/${bm_pxe_network_mac_address}/g" ${xml_file}
    sed -i "s/{{pxe_bridge}}/${physical_host_pxe_network_interface}/g" ${xml_file}

    sed -i "s/{{physical_host}}/${physical_host}/g" ${xml_file}
}

function launch_firstbox_vm()
{
    xml_file="/pitrix/kernels/${hostname}.xml"
    virsh define ${xml_file}
    virsh start ${hostname}
    virsh autostart ${hostname}
    virsh list | grep -w ${hostname} | grep -qw "running"
    if [ $? -eq 0 ]; then
        echo "The VM [${hostname}] is already running."
        # "Done" represents a status, do not change
        touch /pitrix/kernels/${hostname}.Done
        return 0
    else
        echo "Fail to launch [${xml_file}] on [${physical_host}]!"
        return 1
    fi
}

log_file="/root/launch_fb.log"
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
echo -n "${date} Creating the network bridge for qingcloud-firstbox vm ... "
SafeExecFunc create_network_bridge

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Preparing the pitrix directory ... "
SafeExecFunc prepare_pitrix_directory

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Generating the qingcloud-firstbox setting file ... "
SafeExecFunc generate_firstbox_setting

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Creating the qingcloud-firstbox image ... "
SafeExecFunc create_firstbox_image

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Mounting the qingcloud-firstbox image ... "
SafeExecFunc mount_firstbox_image

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Configuring the qingcloud-firstbox network interfaces ... "
SafeExecFunc config_firstbox_network_interfaces

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Configuring the qingcloud-firstbox ssh service ... "
SafeExecFunc config_firstbox_ssh_service

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Configuring the qingcloud-firstbox systemd ... "
SafeExecFunc config_firstbox_systemd

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Umounting the qingcloud-firstbox image ... "
SafeExecFunc umount_firstbox_image

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Preparing the qingcloud-firstbox xml file ... "
SafeExecFunc prepare_firstbox_xml

date=$(date +'%Y-%m-%d %H:%M:%S')
echo -n "${date} Launching the qingcloud-firstbox ... "
SafeExecFunc launch_firstbox_vm

date=$(date +'%Y-%m-%d %H:%M:%S')
echo "${date} The qingcloud-firstbox vm has been launched successfully!"
log "The qingcloud-firstbox vm has been launched successfully!"

