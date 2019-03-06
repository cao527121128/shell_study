#!/bin/bash
# set -x

SCRIPT="$(readlink -f $0)"
CWD="$(dirname ${SCRIPT})"

params=$@
${CWD}/update_nodes_allinone.sh ${params}
