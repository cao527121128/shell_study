#!/bin/bash
#set -x

SCRIPT=$(readlink -f $0)
CWD=$(dirname ${SCRIPT})

PITRIX_DIR='/pitrix'
NODES_DIR="${PITRIX_DIR}/conf/nodes"
mkdir -p ${NODES_DIR}

settings="${PITRIX_DIR}/conf/settings/*"
empty_setting="${PITRIX_DIR}/conf/templates/empty_setting"

ntp_addresses=$(cat /pitrix/conf/variables/ntp_*_address*)

kinds=('all' 'phy' 'vm' 'ks' 'ks-phy' 'ks-vm' 'ks-bm' 'vg' 'vgateway' 'hyper' 'hyper-local' 'hyper-pair' 'hyper-repl' 'hyper-sanc' 'non-ks' 'non-vg' 'non-vg-phy' 'non-hyper' 'non-hyper-phy' 'seed' 'vbr' 'snapshot' 'proxy' 'dnsmaster' 'webservice' 'zookeeper' 'zoocassa' 'pgpool' 'pgmaster' 'pgalone' 'pgslave' 'pgserver' 'bm' 'ntp' 'non-ntp' 'dns' 'vdi' 'eipctl' 'boss')

is_region_flag=$(cat /pitrix/conf/variables/is_region)
if [[ "x${is_region_flag}" == "x1" ]]; then
    zone_ids=$(cat /pitrix/conf/variables/zone_ids)
    if [[ "x${zone_ids}" == "x" ]]; then
        echo "Error: The variable [zone_ids] is empty when [is_region] is [1]!"
        exit 1
    fi
fi

# init kind nodes dict
declare -A kind_nodes_dict
for kind in ${kinds[@]}
do
    kind_nodes_dict[${kind}]=""
    if [[ "x${is_region_flag}" == "x1" ]]; then
        for zone in ${zone_ids}
        do
            kind_nodes_dict[${zone}-${kind}]=""
        done
    fi
done

function write_kind_nodes_dict()
{
    local kind=$1
    local node=$2

    old_nodes=${kind_nodes_dict[${kind}]}
    if [[ "x${old_nodes}" == "x" ]]; then
        new_nodes="${node}"
    else
        new_nodes="${old_nodes} ${node}"
    fi
    kind_nodes_dict[${kind}]="${new_nodes}"

    if [[ "x${is_region_flag}" == "x1" ]]; then
        for zone in ${zone_ids}
        do
            if [[ "x${zone}" == "x${zone_id}" ]]; then
                old_nodes=${kind_nodes_dict[${zone}-${kind}]}
                if [[ "x${old_nodes}" == "x" ]]; then
                    new_nodes="${node}"
                else
                    new_nodes="${old_nodes} ${node}"
                fi
                kind_nodes_dict[${zone}-${kind}]="${new_nodes}"
            fi
        done
    fi
}

function gen_kind_nodes_dict()
{
    for kind in "${kinds[@]}"
    do
        if [ "x${kind}" = "xall" ]; then
            write_kind_nodes_dict ${kind} ${hostname}
        elif [ "x${kind}" = "xphy" ]; then
            if [[ "x${physical_host_network_interface}" == "x" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xvm" ]; then
            if [[ "x${physical_host_network_interface}" != "x" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xks" ]; then
            if [[ "x${feature_hypernode}" != "xon" ]] && [[ "${role}" != *"vgateway"* ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xks-phy" ]; then
            if [[ "x${feature_hypernode}" != "xon" ]] && [[ "${role}" != *"vgateway"* ]] && [[ "x${physical_host_network_interface}" == "x" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xks-vm" ]; then
            if [[ "x${feature_hypernode}" != "xon" ]] && [[ "${role}" != *"vgateway"* ]] && [[ "x${physical_host_network_interface}" == "x" ]] && [[ "x${bm_ipmi_network_interface}" == "x" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xks-bm" ]; then
            if [[ "x${feature_hypernode}" != "xon" ]] && [[ "${role}" != *"vgateway"* ]] && [[ "x${physical_host_network_interface}" == "x" ]] && [[ "x${bm_ipmi_network_interface}" != "x" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xvg" ]; then
            if [[ "${role}" == *"vgateway"* ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xvgateway" ]; then
            if [[ "${role}" == *"vgateway"* ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xhyper" ]; then
            if [[ "x${feature_hypernode}" == "xon" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xhyper-local" ]; then
            if [[ "x${feature_hypernode}" == "xon" ]] && [[ "x${container_mode}" == "xlocal" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xhyper-pair" ]; then
            if [[ "x${feature_hypernode}" == "xon" ]] && [[ "x${container_mode}" == "xpair" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xhyper-repl" ]; then
            if [[ "x${feature_hypernode}" == "xon" ]] && [[ "x${container_mode}" == "xrepl" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xnon-ks" ]; then
            if [[ "x${feature_hypernode}" == "xon" ]] || [[ "${role}" == *"vgateway"* ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xnon-vg" ]; then
            if [[ "${role}" != *"vgateway"* ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xnon-vg-phy" ]; then
            if [[ "${role}" != *"vgateway"* ]] && [[ "x${physical_host_network_interface}" == "x" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xnon-hyper" ]; then
            if [[ "x${feature_hypernode}" != "xon" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xnon-hyper-phy" ]; then
            if [[ "x${feature_hypernode}" != "xon" ]] && [[ "x${physical_host_network_interface}" == "x" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xpgalone" ]; then
            if [[ ${role} == *"pgalone"*  ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xpgserver" ]; then
            if [[ ${role} == *"pgserver"*  ]] || [[ ${role} == *"pgmaster"*  ]] || [[ ${role} == *"pgslave"*  ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xntp" ]; then
            is_ntp_node='false'
            for ntp_address in ${ntp_addresses}
            do
                if [[ ${mgmt_network_address} == ${ntp_address} ]]; then
                    is_ntp_node='true'
                    break
                fi
            done
            if [[ "x${is_ntp_node}" == "xtrue" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xnon-ntp" ]; then
            is_ntp_node='false'
            for ntp_address in ${ntp_addresses}
            do
                if [[ ${mgmt_network_address} == ${ntp_address} ]]; then
                    is_ntp_node='true'
                    break
                fi
            done
            if [[ "x${is_ntp_node}" == "xfalse" ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        elif [ "x${kind}" = "xdns" ]; then
            if [[ "${role}" == *"dnsmaster"* ]] || [[ "${role}" == *"dnsslave"* ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        else
            if [[ "${role}" == *"${kind}"* ]]; then
                write_kind_nodes_dict ${kind} ${hostname}
            fi
        fi
    done
}

for setting in ${settings}
do
    if [ ! -f ${setting} ]; then
        continue
    fi

    . ${empty_setting} >/dev/null 2>&1
    . ${setting} >/dev/null 2>&1

    if [[ "x${is_region_flag}" == "x1" ]]; then
        if [[ "x${zone_id}" == "x" ]]; then
            for zone in ${zone_ids}
            do
                if [[ ${hostname} == "${zone}"* ]]; then
                    zone_id=${zone}
                    break
                fi
            done
        fi
    fi

    gen_kind_nodes_dict
done

for kind in ${!kind_nodes_dict[*]}
do
    nodes=${kind_nodes_dict[${kind}]}
    echo "nodes=( ${nodes} );" > ${NODES_DIR}/${kind}
done

echo "The node list [${kinds[@]}] have been generated in [/pitrix/conf/nodes] successfully."

exit 0
