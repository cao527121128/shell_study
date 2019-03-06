#!/bin/bash

# config
compile_mode=source
#compile_mode=binary

#projects=('pitrix-common' 'pitrix-bot-cache' 'pitrix-bot-router' 'pitrix-bot-router2' 'pitrix-bot-lb' 'pitrix-bot-rdb' 'pitrix-bot-s2' 'pitrix-bot-zk' 'pitrix-bot-frame' 'pitrix-bot-queue' 'pitrix-bot-db' 'pitrix-bot-mongo' 'pitrix-bot-spark' 'pitrix-bots' 'pitrix-vgateway');
#projects=('pitrix-common' 'pitrix-bot-cache' 'pitrix-bot-router' 'pitrix-bot-router2' 'pitrix-bot-lb' 'pitrix-bot-rdb' 'pitrix-bot-s2' 'pitrix-bot-zk' 'pitrix-bot-frame' 'pitrix-bot-queue' 'pitrix-bot-db' 'pitrix-bot-mongo' 'pitrix-bot-spark' 'pitrix-bots' 'pitrix-name' 'pitrix-distributed' 'pitrix-vgateway' 'pitrix-billing' 'pitrix-billing-delegator' 'pitrix-frontgate' 'pitrix-ws' 'pitrix-notifier' 'pitrix-autoscaling' 'pitrix-watch' 'pitrix-boss' 'pitrix-cb');
#projects=('pitrix-common' 'pitrix-bot-cache' 'pitrix-bot-router' 'pitrix-bot-router2' 'pitrix-bot-lb' 'pitrix-bot-rdb' 'pitrix-bot-s2' 'pitrix-bot-zk' 'pitrix-bot-frame' 'pitrix-bot-queue' 'pitrix-bot-db' 'pitrix-bot-mongo' 'pitrix-bot-spark' 'pitrix-bot-hadoop' 'pitrix-bot-hdw'  'pitrix-bots' 'pitrix-name' 'pitrix-billing' 'pitrix-frontgate' 'pitrix-ws' 'pitrix-notifier' 'pitrix-autoscaling' 'pitrix-watch' 'pitrix-boss' 'pitrix-topology' 'pitrix-websocket');
#projects=('pitrix-common' 'pitrix-bot-router' 'pitrix-bot-router2' 'pitrix-bot-lb' 'pitrix-bots' 'pitrix-vgateway');
#projects=('pitrix-common' 'pitrix-bot-cache' 'pitrix-bot-router' 'pitrix-bot-router2' 'pitrix-bot-lb' 'pitrix-bot-rdb' 'pitrix-bot-s2' 'pitrix-bot-zk' 'pitrix-bot-frame' 'pitrix-bot-queue' 'pitrix-bot-db' 'pitrix-bot-mongo' 'pitrix-bot-spark' 'pitrix-bot-hadoop' 'pitrix-bot-hdw' 'pitrix-bots' 'pitrix-vgateway' 'pitrix-billing' 'pitrix-frontgate' 'pitrix-ws' 'pitrix-notifier');
#projects=('pitrix-common' 'pitrix-bot-cache' 'pitrix-bot-router' 'pitrix-bot-router2' 'pitrix-bot-lb' 'pitrix-bot-rdb' 'pitrix-bot-s2' 'pitrix-bot-zk' 'pitrix-bot-frame' 'pitrix-bot-queue' 'pitrix-bot-db' 'pitrix-bot-mongo' 'pitrix-bot-spark' 'pitrix-bot-hadoop' 'pitrix-bot-hdw'  'pitrix-bots' 'pitrix-frontgate' 'pitrix-ws' 'pitrix-notifier' 'pitrix-watch');
#projects=('pitrix-common' 'pitrix-bot-cache' 'pitrix-bot-router' 'pitrix-bot-router2' 'pitrix-bot-lb' 'pitrix-bot-rdb' 'pitrix-bot-s2' 'pitrix-bot-zk' 'pitrix-bot-frame' 'pitrix-bot-queue' 'pitrix-bot-db' 'pitrix-bot-mongo' 'pitrix-bot-spark' 'pitrix-bot-hadoop' 'pitrix-bot-hdw'  'pitrix-bots' 'pitrix-frontgate' 'pitrix-ws' 'pitrix-notifier' 'pitrix-watch' 'pitrix-billing');
#projects=('pitrix-common' 'pitrix-bot-cache' 'pitrix-bot-router' 'pitrix-bot-router2' 'pitrix-bot-lb' 'pitrix-bot-rdb' 'pitrix-bot-s2' 'pitrix-bot-zk' 'pitrix-bot-frame' 'pitrix-bot-queue' 'pitrix-bot-db' 'pitrix-bot-mongo' 'pitrix-bot-spark' 'pitrix-bot-hadoop' 'pitrix-bot-hdw'  'pitrix-bots' );

#projects=('pitrix-common' 'pitrix-bot-nascontainer'  'pitrix-bot-cm' 'pitrix-bot-bm' 'pitrix-bot-swctl' 'pitrix-bot-cluster' 'pitrix-bot-cfgmgmt' 'pitrix-bot-router' 'pitrix-bot-router2' 'pitrix-bot-storm' 'pitrix-bot-hbase' 'pitrix-bot-lb' 'pitrix-bot-rdb' 'pitrix-bot-cache' 'pitrix-bot-s2' 'pitrix-bot-zk' 'pitrix-bot-frame' 'pitrix-bot-queue' 'pitrix-bot-db' 'pitrix-bot-mongo' 'pitrix-bot-spark' 'pitrix-bot-hadoop' 'pitrix-bot-hdw' 'pitrix-bot-es' 'pitrix-bot-opsbuilder' 'pitrix-bots' 'pitrix-bot-repl');
#projects=('pitrix-common' 'pitrix-bot-nascontainer'  'pitrix-bot-cm' 'pitrix-bot-bm' 'pitrix-bot-swctl' 'pitrix-bot-cluster' 'pitrix-bot-cfgmgmt' 'pitrix-bot-router' 'pitrix-bot-router2' 'pitrix-bot-storm' 'pitrix-bot-hbase' 'pitrix-bot-lb' 'pitrix-bot-rdb' 'pitrix-bot-cache' 'pitrix-bot-s2' 'pitrix-bot-zk' 'pitrix-bot-frame' 'pitrix-bot-queue' 'pitrix-bot-db' 'pitrix-bot-mongo' 'pitrix-bot-spark' 'pitrix-bot-hadoop' 'pitrix-bot-hdw' 'pitrix-bot-es' 'pitrix-bot-opsbuilder' 'pitrix-bots' 'pitrix-bot-repl' 'pitrix-ws' 'pitrix-frontgate' 'pitrix-billing' 'pitrix-account' 'pitrix-distributed' 'pitrix-notifier' 'pitrix-watch' 'pitrix-network-plugin');
projects=('pitrix-desktop-tools');
rm -rf output

for proj in "${projects[@]}"
do
    ./build.py  -p /usr/local/src/${proj} -m $compile_mode
done

#./upload.sh output/*

exit 0
