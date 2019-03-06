#!/bin/bash
# set -x

SCRIPT=`readlink -f $0`
CWD=`dirname $SCRIPT`

function usage()
{
    echo "Usage:"
    echo "    _update_node.sh <node> <packages>"
    echo "      <node> can be found in /pitrix/conf/settings"
    echo "      <packages> can be found in /pitrix/repo or /pitrix/upgrade/packages"
    echo "Example:"
    echo "    _update_node.sh testr01n01 pitrix-hosts"
    echo "    _update_node.sh testr01n01 pitrix-alert-agent,hosts"
    echo "    _update_node.sh testr01n01 pitrix-global-conf hosts"
}

if [[ "x$1" == "x-h" ]] || [[ "x$1" == "x--help" ]]; then
    usage
    exit 1
fi

if [ $# -lt 2 ]; then
    usage
    exit 1
fi

node=$1
shift
PACKAGES=$@

if [ ! -f /pitrix/conf/settings/$node ]; then
    echo "Error: The node [$node] is invalid, can not find it in /pitrix/conf/settings!"
    exit 1
fi

. /pitrix/conf/templates/empty_setting >/dev/null 2>&1
. /pitrix/conf/settings/$node >/dev/null 2>&1

ping -w 1 -c 1 ${mgmt_network_address} >/dev/null 2>&1
if [ $? -ne 0 ]; then
    ping -w 1 -c 1 ${mgmt_network_address} >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: The node [$node] is unreachable. Please check the network!"
        exit 1
    fi
fi

echo $PACKAGES | grep -q ','
if [ $? -eq 0 ]; then
    # comma to blank
    PACKAGES=`echo $PACKAGES | tr ',' ' '`
fi

new_packages=()
for PACKAGE in $PACKAGES
do
    if [[ -z "$PACKAGE" ]]; then
        continue
    fi
    if [ -f /pitrix/upgrade/packages/$PACKAGE ]; then
        . /pitrix/upgrade/packages/$PACKAGE
    else
        packages=( "$PACKAGE" )
    fi
    new_packages=(${new_packages[@]} ${packages[@]})
done
packages=(${new_packages[@]})

for package in ${packages[@]}
do
    count=`find /pitrix/repo /var/www/repo -name "$package*" | wc -l`
    if [ $count -eq 0 ]; then
        echo "Error: The package [$package] is invalid, can not find it in /pitrix/repo!"
        exit 1
    fi
done

mkdir -p /pitrix/log/update_nodes
log_file="/pitrix/log/update_nodes/update_${node}.log"
if [ -f ${log_file} ]; then
    echo "" >> ${log_file}
fi

function log()
{
   msg=$*
   DATE=`date +'%Y-%m-%d %H:%M:%S'`
   echo "$DATE $msg" >> ${log_file}
}

if [[ ${os_version} == "12.04"* ]]; then
    apt_options="--yes --force-yes --allow-unauthenticated --reinstall"
elif [[ ${os_version} == "14.04"* ]]; then
    apt_options="--yes --force-yes --allow-unauthenticated --reinstall"
elif [[ ${os_version} == "16.04"* ]]; then
    # --force-yes is deprecated after Ubuntu 16.xx
    apt_options="--yes --allow-unauthenticated --reinstall"
fi

if [ ${#packages[@]} -ge 2 ]; then
    echo -n "  Updating [$node] with [${packages[0]} ~ ] ... "
else
    echo -n "  Updating [$node] with [${packages[@]}] ... "
fi
log "Updating [$node] with [${packages[@]}] ..."
# update apt, remove old deb packages is needed
ssh -o ConnectTimeout=3 -o ConnectionAttempts=1 $node "dpkg --configure -a; rm -f /var/cache/apt/archives/*.deb; \
    apt-get autoclean; apt-get clean; apt-get update" >>${log_file} 2>&1
# upgrade packages
ssh -o ConnectTimeout=3 -o ConnectionAttempts=1 $node "apt-get ${apt_options} install ${packages[@]}" >>${log_file} 2>&1
if [ $? -eq 0 ]; then
    echo -n "OK." && echo ""
    log "Update [$node] with [${packages[@]}] OK."
    exit 0
else
    echo -n "Error!" && echo ""
    log "Update [$node] with [${packages[@]}] Error!"
    exit 1
fi

