#!/bin/bash
# set -x

SCRIPT=$(readlink -f $0)
CWD=$(dirname ${SCRIPT})

function usage()
{
    echo "Usage:"
    echo "    update_nodes.sh [-f/--force-yes] <nodes> <packages>"
    echo "      -f/--force-yes means force yes"
    echo "      <nodes> can be found in /pitrix/conf/settings or /pitrix/conf/nodes"
    echo "      <packages> can be found in /pitrix/repo or /pitrix/upgrade/packages"
    echo "Example:"
    echo "    update_nodes.sh -f testr01n01 pitrix-hosts"
    echo "    update_nodes.sh testr01n01 pitrix-hosts,pitrix-global-conf"
    echo "    update_nodes.sh hyper pitrix-hosts pitrix-hyper"
    echo "    update_nodes.sh testr01n01,testr01n02 pitrix-alert-agent,hosts"
    echo "    update_nodes.sh testr01n01,hyper pitrix-hosts pitrix-alert-agent"
}

if [[ "x$1" == "x-h" ]] || [[ "x$1" == "x--help" ]]; then
    usage
    exit 1
fi

if [ $# -lt 2 ]; then
    usage
    exit 1
fi

if [[ "x$1" == "x-f" ]] || [[ "x$1" == "x--force-yes" ]]; then
    option="--force-yes"
    shift
else
    option=""
fi
NODES=$1
shift
PACKAGES=$@

echo ${NODES} | grep -q ','
if [ $? -eq 0 ]; then
    # comma to blank
    NODES=($(echo ${NODES} | tr ',' ' '))
fi

new_nodes=()
for NODE in ${NODES[@]}
do
    if [[ -z "${NODE}" ]]; then
        continue
    fi
    if [ -f /pitrix/conf/nodes/${NODE} ]; then
        . /pitrix/conf/nodes/${NODE}
    else
        nodes=(${NODE})
    fi
    new_nodes=(${new_nodes[@]} ${nodes[@]})
done
nodes=(${new_nodes[@]})

if [ ${#nodes[@]} -eq 0 ]; then
    echo "Error: the argument <nodes> is empty, please input a valid one."
    exit 1
fi

# remove repeating node
nodes=($(echo ${nodes[@]} | sed 's/ /\n/g' | sort | uniq))

# nodes is array
for node in ${nodes[@]}
do
    if [ ! -f /pitrix/conf/settings/${node} ]; then
        echo "Error: The node [${node}] is invalid, can not find it in /pitrix/conf/settings!"
        exit 1
    fi
done

echo ${PACKAGES} | grep -q ','
if [ $? -eq 0 ]; then
    # comma to blank
    PACKAGES=$(echo ${PACKAGES} | tr ',' ' ')
fi

new_packages=()
for PACKAGE in ${PACKAGES[@]}
do
    if [[ -z "${PACKAGE}" ]]; then
        continue
    fi
    if [ -f /pitrix/upgrade/packages/${PACKAGE} ]; then
        . /pitrix/upgrade/packages/${PACKAGE}
    else
        packages=("${PACKAGE}")
    fi
    new_packages=(${new_packages[@]} ${packages[@]})
done
packages=(${new_packages[@]})

# remove repeating package
packages=($(echo ${packages[@]} | sed 's/ /\n/g' | sort | uniq))

if [ ${#packages[@]} -eq 0 ]; then
    echo "Error: The argument <packages> is empty, please input a valid one."
    exit 1
fi

# packages is array
for package in ${packages[@]}
do
    count=$(find /pitrix/repo /var/www/repo -name "${package}*" | wc -l)
    if [ ${count} -eq 0 ]; then
        echo "Error: The package [${package}] is invalid, can not find it in /pitrix/repo or /var/www/repo!"
        exit 1
    fi
done

nodes_str=$(IFS=, ; echo "${nodes[*]}")
packages_str=$(IFS=, ; echo "${packages[*]}")
echo "------------------------------------------------"
echo -e "TARGET NODES:\n    ${nodes_str}"
echo "------------------------------------------------"
echo -e "TARGET PACKAGES:\n    ${packages_str}"
echo "------------------------------------------------"

function confirm()
{
    msg=$*
    while [ 1 -eq 1 ]
    do
        read -r -p "${msg}" response
        case $response in
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

if [[ "x${option}" != "x--force-yes" ]]; then
    val=$(confirm "Are you sure to update the packages on the above nodes [y/N]?")
    if [ ${val} -ne 0 ]; then
        exit 0
    fi
fi

mkdir -p /pitrix/log/update_nodes
log_file="/pitrix/log/update_nodes/update_nodes.log"
if [ -f ${log_file} ]; then
    echo "" >> ${log_file}
fi

function log()
{
    msg=$*
    DATE=$(date +'%Y-%m-%d %H:%M:%S')
    echo "${DATE} ${msg}" >> ${log_file}
}

conf_file="/tmp/update_nodes_${NODE}_$$"
rm -f ${conf_file}
for node in ${nodes[@]}
do
    echo "${node}#${packages[@]}" >> ${conf_file}
done

job_log="/tmp/update_nodes_job_log_$$"
rm -f ${job_log}

log "Updating [${nodes[@]}] with [${packages[@]}] ..."
cat ${conf_file} | parallel -j 10 --colsep '#' --joblog ${job_log} ${CWD}/_update_node.sh {1} {2} 2>&1 | tee -a ${log_file}
log "Update [${nodes[@]}] with [${packages[@]}] Finish."

# get the exit codes from the job log file and check them
cat ${job_log} | awk '{print $7}' | grep -v 'Exitval' | sort | uniq | grep -qw '1'
if [ $? -eq 0 ]; then
    rm -f ${conf_file}
    rm -f ${job_log}
    exit 1
else
    rm -f ${conf_file}
    rm -f ${job_log}
    exit 0
fi

