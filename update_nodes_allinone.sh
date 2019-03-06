#!/bin/bash
# set -x

SCRIPT="$(readlink -f $0)"
CWD="$(dirname ${SCRIPT})"

function usage()
{
    echo "Usage:"
    echo "    update_nodes_allinone.sh [-i/--interactive-mode]"
    echo "      -i/--interactive-mode means interactive mode, need to confirm before update packages"
    echo "Example:"
    echo "    update_nodes_allinone.sh -i"
}

interactive_mode="false"

while [[ "x$1" != "x" ]]
do
    case $1 in
        -i)
            interactive_mode="true"
            shift
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

mkdir -p /pitrix/log/update_nodes
log_file="/pitrix/log/update_nodes/update_nodes_allinone.log"
if [ -f ${log_file} ]; then
    echo "" >> ${log_file}
fi

function log()
{
    msg=$*
    date="$(date +'%Y-%m-%d %H:%M:%S')"
    echo "${date} ${msg}" >> ${log_file}
}

function confirm()
{
    local msg=$*
    while [ 1 -eq 1 ]
    do
        read -r -p "${msg}" response
        case ${response} in
            [yY][eE][sS]|[yY])
                echo 0
                return
                ;;
            [nN][oO]|[nN])
                echo 1
                return
                ;;
        esac
    done
}

function SafeUpdate()
{
    local NODE=$1
    if [ -f /pitrix/conf/settings/${NODE} ]; then
        nodes=(${NODE})
    elif [ -f /pitrix/conf/nodes/${NODE} ]; then
        . /pitrix/conf/nodes/${NODE}
        if [ ${#nodes[@]} -eq 0 ]; then
            return
        fi
    else
        echo "Error: The node [${NODE}] is invalid, please check it!"
        exit 1
    fi

    local PACKAGE=$2
    count=$(find /pitrix/repo -name "${PACKAGE}*" | wc -l)
    if [ ${count} -gt 0 ]; then
        packages=(${PACKAGE})
    elif [ -f /pitrix/upgrade/packages/${PACKAGE} ]; then
        . /pitrix/upgrade/packages/${PACKAGE}
        if [ ${#packages[@]} -eq 0 ]; then
            return
        fi
    else
        echo "Error: The package [${PACKAGE}] is invalid, please check it!"
        exit 1
    fi

    date="$(date +'%Y-%m-%d %H:%M:%S')"
    echo -n "${date} Updating [${NODE}] nodes with [${PACKAGE}] packages ... "
    log "Updating [${NODE}] nodes with [${PACKAGE}] packages ..."

    nodes_str=$(IFS=, ; echo "${nodes[*]}")
    packages_str=$(IFS=, ; echo "${packages[*]}")

    if [[ "x${interactive_mode}" == "xtrue" ]]; then
        echo "" # start a new line when in interactive mode
        value=$(confirm "Are you sure to update [${NODE}] nodes with [${PACKAGE}] packages [y/N]?")
        if [ ${value} -eq 1 ]; then
            date="$(date +'%Y-%m-%d %H:%M:%S')"
            echo "${date} Update [${NODE}] nodes with [${PACKAGE}] packages Ignored!"
            log "Update [${NODE}] nodes with [${PACKAGE}] packages Ignored!"
        else
            /pitrix/upgrade/update_nodes.sh -f ${nodes_str} ${packages_str} 2>&1 | tee -a ${log_file}
            # PIPESTATUS means the last command status array, $? is ${PIPESTATUS[-1]} for default
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                date="$(date +'%Y-%m-%d %H:%M:%S')"
                echo "${date} Update [${NODE}] nodes with [${PACKAGE}] packages OK."
                log "Update [${NODE}] nodes with [${PACKAGE}] packages OK."
            else
                date="$(date +'%Y-%m-%d %H:%M:%S')"
                echo "${date} Update [${NODE}] nodes with [${PACKAGE}] packages Error!"
                value=$(confirm "Do you want to ignore the failed nodes and fix them manually later [y/N]?")
                if [ ${value} -eq 0 ]; then
                    log "Update [${NODE}] nodes with [${PACKAGE}] packages Error! And the error is ignored manually!"
                else
                    log "Update [${NODE}] nodes with [${PACKAGE}] packages Error!"
                    exit 1
                fi
            fi
        fi
    else
        /pitrix/upgrade/update_nodes.sh -f ${nodes_str} ${packages_str} >>${log_file} 2>&1
        if [ $? -eq 0 ]; then
            echo -n "OK." && echo ""
            log "Update [${NODE}] nodes with [${PACKAGE}] packages OK."
        else
            echo -n "Error!" && echo ""
            log "Update [${NODE}] nodes with [${PACKAGE}] packages Error!"
            exit 1
        fi
    fi
}

if [ ! -f ${CWD}/pre_upgrade.Done ]; then
    echo "The [pre_upgrade.sh] has not been executed successfully. Please check!"
    exit 1
fi

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Testing [all] nodes whether are ready for updating packages ... "
log "Testing [all] nodes whether are ready for updating packages ..."
if [[ "x${interactive_mode}" == "xtrue" ]]; then
    echo "" # start a new line when in interactive mode
    value=$(confirm "Are you sure to test [all] nodes whether are ready for updating packages [y/N]?")
    if [ ${value} -eq 1 ]; then
        date="$(date +'%Y-%m-%d %H:%M:%S')"
        echo "${date} Test [all] nodes whether are ready for updating packages Ignored!"
        log "Test [all] nodes whether are ready for updating packages Ignored!"
    else
        /pitrix/upgrade/exec_nodes.sh -f all "date" 2>&1 | tee -a ${log_file}
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            date="$(date +'%Y-%m-%d %H:%M:%S')"
            echo "${date} Test [all] nodes whether are ready for updating packages OK."
            log "Test [all] nodes whether are ready for updating packages OK."
        else
            date="$(date +'%Y-%m-%d %H:%M:%S')"
            echo "${date} Test [all] nodes whether are ready for updating packages Error!"
            value=$(confirm "Do you want to ignore the failed nodes and fix them manually later [y/N]?")
            if [ ${value} -eq 0 ]; then
                log "Test [all] nodes whether are ready for updating packages Error! And the error is ignored manually!"
            else
                log "Test [all] nodes whether are ready for updating packages Error!"
                exit 1
            fi
        fi
    fi
else
    /pitrix/upgrade/exec_nodes.sh -f all "date" >>${log_file} 2>&1
    if [ $? -eq 0 ]; then
        echo -n "OK." && echo ""
        log "Test [all] nodes whether are ready for updating packages OK."
    else
        echo -n "Error!" && echo ""
        echo "Warning: There may be some problems with some nodes because of executing command failing on them!"
        echo "Hint: You can find them using the command [/pitrix/upgrade/exec_nodes.sh all \"date\"]."
        echo "Suggestion: You can upgrade packages using the command [/pitrix/upgrade/update_nodes_allinone.sh -i]."
        log "Test [all] nodes whether are ready for updating packages Error!"
        exit 1
    fi
fi

# some common pitrix packages
SafeUpdate all common

is_region=$(cat /pitrix/conf/variables/is_region)
ZONE_IDS=($(cat /pitrix/conf/variables/zone_ids))

for ZONE_ID in ${ZONE_IDS[@]}
do
    if [[ "x${is_region}" == "x1" ]]; then
        ZONE_PREFIX="${ZONE_ID}-"
    else
        ZONE_PREFIX=""
    fi

    is_global_zone=$(cat /pitrix/conf/variables/is_global_zone.${ZONE_ID})
    if [[ "x${is_global_zone}" == "x1" ]]; then
        SafeUpdate ${ZONE_PREFIX}webservice global-website
        SafeUpdate ${ZONE_PREFIX}webservice global-webservice
    else
        SafeUpdate ${ZONE_PREFIX}webservice zone-website
        SafeUpdate ${ZONE_PREFIX}webservice zone-webservice
    fi
done

SafeUpdate proxy proxy

# if dns use master-slave mode, it can not update dns pkgs in slave node
. /pitrix/conf/nodes/dns
for dns_node in ${nodes[@]}
do
    ssh ${dns_node} 'grep -rqn "type master" /etc/bind/named.conf'
    if [ $? -eq 0 ]; then
        SafeUpdate ${dns_node} dns
    fi
done
SafeUpdate bm bm
SafeUpdate vdi vdi
SafeUpdate boss boss
SafeUpdate seed seed
SafeUpdate vbr vbr
SafeUpdate vgateway vgateway
SafeUpdate hyper hyper

for ZONE_ID in ${ZONE_IDS[@]}
do
    cloud_type="$(cat /pitrix/conf/variables/cloud_type.${ZONE_ID})"
    if [[ "x${cloud_type}" != "xpublic" ]]; then
        SafeUpdate hyper pitrix-boss-daemon
    fi
done

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo "${date} All nodes and packages are updated successfully."
touch ${CWD}/upgrade_pkgs.Done
log "All nodes and packages are updated successfully."
