#!/bin/bash
# set -x

SCRIPT=`readlink -f $0`
CWD=`dirname $SCRIPT`

if [ $# -eq 0 ]; then
    $CWD/update_nodes.sh
    exit 1
fi

params=$@

if [ $# -eq 1 ] && [ -f /pitrix/upgrade/packages/$params ]; then
    # such as "./update.sh hyper"
    $CWD/update_nodes.sh $params $params
else
    $CWD/update_nodes.sh $params
fi

