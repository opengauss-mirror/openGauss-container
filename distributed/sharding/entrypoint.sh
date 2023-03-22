#!/bin/bash

export LOG_PATH=/var/log/sharding
export CONFIG_PATH=/var/lib/sharding
export ZK_HOME=/usr/local/zookeeper
export SS_HOME=/usr/local/shardingsphere

export ZOO_LOG_DIR=${LOG_PATH}/zk

host_ip=$(ifconfig -a | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | tr -d "addr:")


function install_zk()
{
    mkdir -p ${ZOO_LOG_DIR}
    mkdir -p ${CONFIG_PATH}/zkdata
    cd ${ZK_HOME}/conf/
    cp zoo_sample.cfg zoo.cfg
    echo "dataDir=${CONFIG_PATH}/zkdata" >> zoo.cfg
    echo "clientPort=2181" >> zoo.cfg
    echo "admin.serverPort=8888" >> zoo.cfg
    sh ${ZK_HOME}/bin/zkServer.sh start
}

function install_jre()
{
    export JRE_HOME=/usr/bisheng-jre
    export CLASSPATH=$JRE_HOME/lib:$CLASSPATH
    export PATH=$JRE_HOME/bin:$PATH
    export LD_LIBRARY_PATH=$JRE_HOME/lib:$LD_LIBRARY_PATH
    echo "export JRE_HOME=/usr/bisheng-jre" >> /etc/profile
    echo "export CLASSPATH=$JRE_HOME/lib:$CLASSPATH" >> /etc/profile
    echo "export PATH=$JRE_HOME/bin:$PATH" >> /etc/profile
    echo "export LD_LIBRARY_PATH=$JRE_HOME/lib:$LD_LIBRARY_PATH" >> /etc/profile
}

function config_ss_server()
{
    echo "
mode:
  type: Cluster
  repository:
    type: ZooKeeper
    props:
      namespace: governance_ds
      server-lists: ${host_ip}:2181
      retryIntervalMilliseconds: 500
      timeToLiveSeconds: 60
      maxRetries: 3
      operationTimeoutMilliseconds: 500
authority:
  users:
  - user: root@%
    password: root
  - user: sharding
    password: sharding
  privilege:
    type: ALL_PERMITTED
rules:
- !TRANSACTION
    defaultType: XA
    providerType: Atomikos
" >> ${SS_HOME}/conf/server.yaml
}

function config_ss_sharding()
{
    if [ -f "${CONFIG_PATH}/ssconfig/server.yaml" ] && [ -f "${CONFIG_PATH}/ssconfig/config-sharding.yaml" ]; then
        return
    fi
    mkdir -p ${CONFIG_PATH}/ssconfig
    cp ${SS_HOME}/conf/*.yaml ${CONFIG_PATH}/ssconfig
}

function install_sharding()
{
    # config_ss_server
    config_ss_sharding
    # default port 3307, listen_address:0.0.0.0
    sh ${SS_HOME}/bin/start.sh -c ${CONFIG_PATH}/ssconfig
}

function deadloop()
{
    i=0
    while ((i < 1)); do
        sleep 60
    done
}

function check_installed()
{
    declare -g HAVE_INSTALLED
    if [ -d "${CONFIG_PATH}/ssconfig" ] && [ -d ${CONFIG_PATH}/zkdata ]; then
        HAVE_INSTALLED="true"
    fi
}

function main()
{
    if [ "$(id -u)" = '0' ]; then
        install_jre
        chown -R omm:omm ${LOG_PATH}
        chown -R omm:omm ${CONFIG_PATH}
        # change to omm user
        exec gosu omm "$BASH_SOURCE" "$@"
    fi
    check_installed
    echo "$(ps ux)"

    if [ $1 == "init" ]; then
        install_zk
        install_sharding
        deadloop
    fi

}

main $@
