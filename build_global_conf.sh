#!/bin/bash

SCRIPT=$(readlink -f $0)
CWD=$(dirname ${SCRIPT})

function usage()
{
    echo "Usage:"
    echo "    build_global_conf.sh [-z zone_id]"
    echo "      -z means zone_ids, there are where the package needs to build, all is default"
    echo "Example:"
    echo "    build_global_conf.sh -z pek3a"
}

ZONE_IDS='all'

while [[ "x$1" != "x" ]]
do
    case $1 in
        -z)
            if [[ "x$2" != "x" ]] && [[ $2 != "-"* ]]; then
                ZONE_IDS=$2
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

if [[ "x${ZONE_IDS}" == 'xall' ]]; then
    ZONE_IDS=($(cat /pitrix/conf/variables/zone_ids))
else
    ZONE_IDS=($(echo ${ZONE_IDS} | tr ',' ' '))
fi

DATE="$(date +%Y%m%d)"

rm -rf /pitrix/conf/variables/global_${DATE}
cp -arf /pitrix/conf/variables/global /pitrix/conf/variables/global_${DATE}

for ZONE_ID in ${ZONE_IDS[@]}
do
    /pitrix/build/build_pkgs.sh -z ${ZONE_ID} -p pitrix-global-conf,pitrix-alert-agent,pitrix-hosts,pitrix-neonsan-conf,pitrix-ks-seed,pitrix-ks-vbr,pitrix-ks-snapshot,pitrix-hyper,pitrix-ks-vgateway
done
