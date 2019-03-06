#!/bin/bash
# set -x

SCRIPT=$(readlink -f $0)
CWD=$(dirname ${SCRIPT})

function usage()
{
    echo "Usage:"
    echo "    pre_upgrade.sh"
    echo "Example:"
    echo "    pre_upgrade.sh"
}

if [[ "x$1" == "x-h" ]] || [[ "x$1" == "x--help" ]]; then
    usage
    exit 1
fi

function backup_key_dirs()
{
    old_upgrade=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['old_upgrade'])")

    # back up dns bind conf for security
    /pitrix/upgrade/exec_nodes.sh -f dns "cp -rf /etc/bind /etc/bind_${old_upgrade}"

    # back up pitrix docs
    /pitrix/upgrade/exec_nodes.sh -f webservice "cp -rf /pitrix/lib/pitrix-docs/ /pitrix/lib/pitrix-docs_${old_upgrade}"

    # back up websites
    websites=('pitrix-webconsole' 'pitrix-webappcenter' 'pitrix-websupervisor')
    /pitrix/upgrade/exec_nodes.sh -f webservice "for website in ${websites[@]};do cp -rf /pitrix/lib/\${website} /pitrix/lib/\${website}_${old_upgrade};done"
}

function prepare_upgrades()
{
    old_upgrade=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['old_upgrade'])")
    new_upgrade=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['current']['new_upgrade'])")

    if [[ "x${old_upgrade}" == "x" ]] || [[ "x${new_upgrade}" == "x" ]]; then
        echo "Error: Can not get [old_upgrade] or [new_upgrade] from [/pitrix/version.version], please check it!"
        return 1
    fi

    upgrades_dir="${CWD}/upgrades/*"
    new_upgrades_dir="${CWD}/new_upgrades/"
    rm -rf ${new_upgrades_dir}
    mkdir -p ${new_upgrades_dir}
    elements=( 'xboss' 'xvdi' )
    for upgrade_dir in ${upgrades_dir}
    do
        upgrade_name=$(basename ${upgrade_dir})
        if [[ "x${upgrade_name}" == "xchangelog" ]]; then
            continue
        fi

        # elements upgrades
        if [[ "${elements[@]}" =~ "x${upgrade_name}" ]]; then # =~: Determines whether the value is included in the array.
            element_upgrades_dir="${upgrade_dir}/*"
            mkdir -p "${new_upgrades_dir}/${upgrade_name}/"
            for element_upgrade_dir in ${element_upgrades_dir[@]}
            do
                element_upgrade_name=$(basename ${element_upgrade_dir})
                if [[ ${element_upgrade_name} -ge ${old_upgrade} ]] && [[ ${element_upgrade_name} -le ${new_upgrade} ]]; then
                    rsync -azPS ${element_upgrade_dir} "${new_upgrades_dir}/${upgrade_name}/"
                fi
            done
            continue
        fi

        if [[ ${upgrade_name} -ge ${old_upgrade} ]] && [[ ${upgrade_name} -le ${new_upgrade} ]]; then
            rsync -azPS ${upgrade_dir} ${new_upgrades_dir}
        fi
    done
}

function execute_upgrade_scripts()
{
    new_upgrades_dir="/pitrix/upgrade/new_upgrades/*"
    new_upgrades_boss_dir="/pitrix/upgrade/new_upgrades/boss/*"
    new_upgrades_vdi_dir="/pitrix/upgrade/new_upgrades/vdi/*"
    for new_upgrade_dir in ${new_upgrades_dir} ${new_upgrades_boss_dir} ${new_upgrades_vdi_dir}
    do
        scripts="${new_upgrade_dir}/*pre_upgrade*.sh"
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

function merge_yamls()
{
    echo "Backing up the global conf directory ..."
    if [ ! -d /pitrix/conf/variables/global_${old_upgrade} ]; then
        cp -rf /pitrix/conf/variables/global /pitrix/conf/variables/global_${old_upgrade}
    fi

    # merge yaml files
    zone_ids=$(cat /pitrix/conf/variables/zone_ids)
    patch_dir=${CWD}/new_upgrades/
    for comp in "server" "billing" "boss" "cmd" "notifier" "topology" "appcenter"
    do
        for zone_id in ${zone_ids}
        do
            echo "Merging [${comp}.yaml.${zone_id}] with the upgrades ..."
            last_full_yaml=$(find ${patch_dir} -name "*.yaml*" | grep -E "${comp}.yaml.all$" | sort | tail -n 1)
            if [[ "x${last_full_yaml}" != "x" ]]; then
                source_yaml=${last_full_yaml}
                patch_list=$(find ${patch_dir} -name "*.yaml*" | sort | grep -A 10000 ${last_full_yaml} | grep -E "${comp}.yaml" | grep -v "${comp}.yaml.del" | sort | tr '\n' ' ')
            else
                source_yaml=/pitrix/conf/variables/global/${comp}.yaml.${zone_id}
                patch_list=$(find ${patch_dir} -name "*.yaml*" | sort | grep -E "${comp}.yaml" | grep -v "${comp}.yaml.del" | sort | tr '\n' ' ')
            fi
            dest_yaml=/pitrix/conf/variables/global/${comp}.yaml.${zone_id}

            if [[ "x${patch_list}" != "x" ]]; then
                rm -f /tmp/.new.yaml
                rm -f /tmp/.old.yaml
                python /pitrix/bin/merge_yaml.py ${source_yaml} ${patch_list}
                echo "The diff of [old] [new] ${comp} yaml file is as blew:"
                diff /tmp/.old.yaml /tmp/.new.yaml
                rsync -azPS /tmp/.new.yaml ${dest_yaml}
                rm -f /tmp/.new.yaml
                rm -f /tmp/.old.yaml
            else
                rsync -azPS ${source_yaml} ${dest_yaml}
            fi
        done
    done
}

function get_server_address()
{
    settings="/pitrix/conf/settings/*"
    empty_setting="/pitrix/conf/templates/empty_setting"
    for setting in ${settings}
    do
        if [ ! -f ${setting} ]; then
            continue
        fi
        . ${empty_setting} >/dev/null 2>&1
        . ${setting} >/dev/null 2>&1
        if echo "${role}" | egrep "pgmaster|pgslave|pgserver|pgalone" ; then
            ssh -o ConnectTimeout=5 -o ConnectionAttempts=1 ${mgmt_network_address} 'dpkg -l | grep pitrix-postgresql | grep 10'
            if [ $? -eq 0 ] ; then
                pgserver=$(ssh -o ConnectTimeout=5 -o ConnectionAttempts=1 ${mgmt_network_address} 'cat /pitrix/run/pg_master')
                break
            else
                ssh -o ConnectTimeout=5 -o ConnectionAttempts=1 ${mgmt_network_address} 'ls /var/lib/postgresql/9.*/main/recovery.conf'
                if [ $? -ne 0 ]; then
                    pgserver=${mgmt_network_address}
                    break
                fi

                ssh -o ConnectTimeout=5 -o ConnectionAttempts=1 ${mgmt_network_address} 'ps aux | grep -v "grep" | grep postgres | grep sender' >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    pgserver=${mgmt_network_address}
                    break
                fi
            fi
        fi
    done

    if [[ "x${pgserver}" == "x" ]]; then
        echo "Error: Can not get the pgserver address, please check it!"
        return 1
    fi

    ping -w 1 -c 1 ${pgserver}
    if [ $? -ne 0 ]; then
        ping -w 1 -c 1 ${pgserver}
        if [ $? -ne 0 ]; then
            echo "Error: The pgserver [${pgserver}] is unreachable!"
            return 1
        fi
    fi

    ssh -o ConnectTimeout=5 -o ConnectionAttempts=1 ${pgserver} 'dpkg -l | grep pitrix-postgresql | grep 10'
    if [[ $? -eq 0 ]]; then
        pgport="5433"
    else
        pgport=$(ssh -o ConnectTimeout=5 -o ConnectionAttempts=1 ${pgserver} 'cat /etc/postgresql/9.*/main/postgresql.conf | egrep "^port"' | tr -dc 0-9)
    fi

    for setting in ${settings}
    do
        if [ ! -f ${setting} ]; then
            continue
        fi
        . ${empty_setting} >/dev/null 2>&1
        . ${setting} /dev/null 2>&1
        if [[ ${role} == *"zoocassa"* ]]; then
            zoocassa=${mgmt_network_address}
            break
        fi
    done

    if [[ "x${zoocassa}" == "x" ]]; then
        echo "Error: Can not get the zoocassa address, please check it!"
        return 1
    fi

    ping -w 1 -c 1 ${zoocassa}
    if [ $? -ne 0 ]; then
        ping -w 1 -c 1 ${zoocassa}
        if [ $? -ne 0 ]; then
            echo "Error: The zoocassa [${zoocassa}] is unreachable!"
            return 1
        fi
    fi
}

function _set_tbl_owner()
{
    local db=$1
    cmd_file="/tmp/set_${db}_tbls_owner.sh"
    echo '#!/bin/bash' > ${cmd_file}
    echo "#set -x" >> ${cmd_file}
    echo "" >> ${cmd_file}
    echo "for tbl in \$(psql -qAt -p ${pgport} -c \"select tablename from pg_tables where schemaname = 'public';\" ${db}) ;" >> ${cmd_file}
    echo "do" >> ${cmd_file}
    echo "    psql -p ${pgport} -c \"alter table \${tbl} owner to yunify;\" -d ${db}" >> ${cmd_file}
    echo "done" >> ${cmd_file}
    echo "" >> ${cmd_file}

    chmod 755 ${cmd_file}
    rsync -azPS ${cmd_file} ${pgserver}:/tmp/
    ssh postgres@${pgserver} "bash -c ${cmd_file}"
    rm -f ${cmd_file}
}

function update_postgresql_database()
{
    old_installer_version=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['old'][0]['installer'])")
    old_qingcloud_version=$(python -c "import json; print(json.load(open('/pitrix/version.json', 'r'))['old'][0]['qingcloud'])")
    backup_dir="/pitrix/backup/${old_installer_version}-${old_qingcloud_version}"

    # backup the qingcloud postgresql
    if [ ! -f ${backup_dir}/qingcloud/qingcloud_pg_dumpall.gz ]; then
        ssh -o ConnectTimeout=5 -o ConnectionAttempts=1 ${pgserver} 'dpkg -l | grep pitrix-postgresql | grep 10'
        if [ $? -eq 0 ] ; then
            ssh postgres@${pgserver} "/opt/postgresql-10.4/bin/pg_dumpall --clean -p ${pgport} | gzip > /tmp/qingcloud_pg_dumpall.gz"
        else
            ssh postgres@${pgserver} "pg_dumpall --clean -p ${pgport} | gzip > /tmp/qingcloud_pg_dumpall.gz"
        fi
        mkdir -p ${backup_dir}/qingcloud
        rsync -azPS ${pgserver}:/tmp/qingcloud_pg_dumpall.gz ${backup_dir}/qingcloud/
    fi

    new_upgrades="/pitrix/upgrade/new_upgrades/*"
    new_upgrades_boss="/pitrix/upgrade/new_upgrades/boss/*"
    new_upgrades_vdi="/pitrix/upgrade/new_upgrades/vdi/*"
    counter=0
    for new_upgrade in ${new_upgrades} ${new_upgrades_boss} ${new_upgrades_vdi}
    do
        sqls=${new_upgrade}/*sql
        ls -1 ${sqls} >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            rsync -azPS ${sqls} postgres@${pgserver}:/tmp/
            for sql in ${sqls}
            do
                # /tmp/test.sql --> test.sql
                sqlfile=${sql##*/}
                if [[ ${sql} == *"/boss/"* ]]; then
                    deploy_boss=($(cat /pitrix/conf/variables/deploy_boss.*))
                    if [[ "${deploy_boss[@]}" =~ "0" ]]; then
                        continue
                    fi
                    db="boss_hypervisor"
                elif [[ ${sql} == *"/vdi/"* ]]; then
                    deploy_vdi=($(cat /pitrix/conf/variables/deploy_vdi.*))
                    if [[ "${deploy_vdi[@]}" =~ "0" ]]; then
                        continue
                    fi
                    db="vdi"
                else
                    # test.sql --> test
                    db=${sqlfile%.sql}
                fi
                ssh postgres@${pgserver} "psql -d ${db} -f /tmp/${sqlfile} -p ${pgport}"
                if [[ $? -ne 0 ]]; then
                    echo "Error: Can not update postgresql database, please check it!"
                    return 1
                fi
                dbs[$counter]=${db}
                let counter=counter+1
            done
        fi

        schemas=${new_upgrade}/*ca
        ls -1 ${schemas} >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            rsync -azPS ${schemas} root@${zoocassa}:/tmp/
            for schema in ${schemas}
            do
                # /tmp/test.ca --> test.ca
                schemafile=${schema##*/}
                ssh root@${zoocassa} "cassandra-cli -h ${zoocassa} -p 9160 -f /tmp/${schemafile}"
            done
        fi
    done

    unique_dbs=$(echo "${dbs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
    IFS=' ' read -a unique_dbs <<< "${unique_dbs}"
    for i in "${!unique_dbs[@]}"
    do
        _set_tbl_owner ${unique_dbs[i]}
    done
}

function rebuild_necessary_packages()
{
    /pitrix/build/build_pkgs_allinone.sh
}

mkdir -p /pitrix/log/upgrade
log_file="/pitrix/log/upgrade/pre_upgrade.log"
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
echo -n "${date} Backing up some key dirs before upgrading ... "
SafeExecFunc backup_key_dirs

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Preparing the upgrades depending the qingcloud version ... "
SafeExecFunc prepare_upgrades

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Executing the pre upgrade scripts ... "
SafeExecFunc execute_upgrade_scripts

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Merging the global yaml files with the upgrades ... "
SafeExecFunc merge_yamls

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Getting the pgserver and zoocassa network address ..."
SafeExecFunc get_server_address

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Updating the postgresql database with the upgrades ... "
SafeExecFunc update_postgresql_database

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo -n "${date} Rebuilding some necessary packages before upgrading ... "
SafeExecFunc rebuild_necessary_packages

date="$(date +'%Y-%m-%d %H:%M:%S')"
echo "${date} Pre upgrade actions have finished successfully."
touch ${CWD}/pre_upgrade.Done
log "Pre upgrade actions have finished successfully."
