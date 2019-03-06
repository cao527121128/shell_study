#!/bin/bash
# set -x

SCRIPT=$(readlink -f $0)
CWD=$(dirname ${SCRIPT})

function usage()
{
    echo "Usage:"
    echo "    post_upgrade.sh"
    echo "Example:"
    echo "    post_upgrade.sh"
}

if [[ "x$1" == "x-h" ]] || [[ "x$1" == "x--help" ]]; then
    usage
    exit 1
fi

function execute_upgrade_scripts()
{
    if [ ! -d /pitrix/upgrade/upgrades ]; then
        echo "Error: There is no [new_upgrades] directory in [/pitrix/upgrade]!"
        return 1
    fi

    new_upgrades_dir="/pitrix/upgrade/new_upgrades/*"
    new_upgrades_boss_dir="/pitrix/upgrade/new_upgrades/boss/*"
    new_upgrades_vdi_dir="/pitrix/upgrade/new_upgrades/vdi/*"
    for new_upgrade_dir in ${new_upgrades_dir} ${new_upgrades_boss_dir} ${new_upgrades_vdi_dir}
    do
        scripts="${new_upgrade_dir}/*post_upgrade*.sh"
        ls -1 ${scripts} >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            for script in ${scripts}
            do
                date="$(date +'%Y-%m-%d %H:%M:%S')"
                echo "${date} Execing the script [${script}] ..."
                ${script}
                if [ $? -ne 0 ]; then
                    echo "Error: Exec the script [${script}] failed!"
                    return 1
                fi
            done
        fi
    done
}

function update_pitrix_version()
{
    new_installer=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['installer'])")
    new_patch=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['patch'])")
    new_upgrade=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['new_upgrade'])")
    new_qingcloud=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['qingcloud'])")
    python -c "import json; obj = json.load(open('/pitrix/version.json', 'r')); obj['current'] = {'installer': '${new_installer}', 'patch': '${new_patch}', 'upgrade': '${new_upgrade}', 'qingcloud': '${new_qingcloud}'}; json.dump(obj, open('/pitrix/version.json', 'w'), sort_keys=True, indent=4, separators=(',', ': '));"
}

mkdir -p /pitrix/log/upgrade
log_file="/pitrix/log/upgrade/post_upgrade.log"
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

if [ ! -f ${CWD}/upgrade_pkgs.Done ]; then
    echo "The [upgrade_pkgs.sh] has not been executed successfully. Please check!"
    exit 1
fi

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Executing the post upgrade scripts ... "
SafeExecFunc execute_upgrade_scripts

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Updating the pitrix version ... "
SafeExecFunc update_pitrix_version

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo "$date Post upgrade actions have finished successfully."
log "Post upgrade actions have finished successfully."

readme_count=$(find /pitrix/upgrade/new_upgrades -name 'readme' | wc -l)
if [ ${readme_count} -gt 0 ]; then
    date="$(date +'%Y-%m-%d %H:%M:%S')"
    echo "${date} There are some manual steps to handle. They are as blew:"
    log "There are some manual steps to handle. They are as blew:"
    find /pitrix/upgrade/new_upgrades -name 'readme' | sort | sed "s|new_upgrades|upgrades|g" | tee -a ${log_file}
fi

# clean
rm -rf /pitrix/upgrade/new_upgrades
rm -f ${CWD}/pre_upgrade.Done
rm -f ${CWD}/upgrade_pkgs.Done
