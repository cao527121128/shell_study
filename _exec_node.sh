#!/bin/bash
# set -x

SCRIPT=`readlink -f $0`
CWD=`dirname $SCRIPT`

function usage()
{
    echo "Usage:"
    echo "    _exec_node.sh <node> <cmd>"
    echo "      <node> can be found in /pitrix/conf/settings"
    echo "Example:"
    echo "    _exec_node.sh testr01n01 \"apt-get update\""
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
cmd=$@

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

mkdir -p /pitrix/log/exec_nodes
log_file="/pitrix/log/exec_nodes/exec_${node}.log"
if [ -f ${log_file} ]; then
    echo "" >> ${log_file}
fi

function log()
{
   msg=$*
   DATE=`date +'%Y-%m-%d %H:%M:%S'`
   echo "$DATE $msg" >> ${log_file}
}

echo "Execing [$node] with [$cmd] ..."
log "Execing [$node] with [$cmd] ..."
ssh -o ConnectTimeout=3 -o ConnectionAttempts=1 $node $cmd 2>&1 | tee -a ${log_file}
if [ $? -eq 0 ]; then
    echo ""
    log "Exec [$node] with [$cmd] OK."
    exit 0
else
    echo ""
    log "Exec [$node] with [$cmd] Error!"
    exit 1
fi

