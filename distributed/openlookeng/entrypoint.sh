#!/bin/bash

export LOG_PATH=/var/log/hetu-server
export CONFIG_PATH=/var/lib/hetu-server
export OLK_HOME=/usr/local/hetu-server
export HETU_SERVER_PORT=8080

host_ip=$(ifconfig -a | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | tr -d "addr:")

function deadloop()
{
    i=0
    while ((i < 1)); do
        sleep 60
    done
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

function config_conn_ss()
{
    source ~/.bashrc
    mkdir ${OLK_HOME}/etc/catalog
    cd ${OLK_HOME}/etc/catalog
    echo "
connector.name=singledata
singledata.mode=SHARDING_SPHERE
shardingsphere.database-name=${ss_schema_name}
shardingsphere.type=ZooKeeper
shardingsphere.namespace=${ss_namespace}
shardingsphere.server-lists=${ss_zk_lists}" > shardingsphere.properties

    mv ${OLK_HOME}/opengauss-jdbc-*.jar ${OLK_HOME}/plugin/hetu-singledata
}

function config_oel()
{
    mkdir ${OLK_HOME}/etc
    cd ${OLK_HOME}/etc

    # node.properties
    echo "
node.environment=openlookeng
node.launcher-log-file=${OLK_HOME}/log/launch.log
node.server-log-file=${OLK_HOME}/log/server.log 
catalog.config-dir=${OLK_HOME}/etc/catalog 
node.data-dir=${OLK_HOME}/data 
plugin.dir=${OLK_HOME}/plugin" > node.properties

    # jvm.config
    echo "
-server
-Xmx16G
-XX:-UseBiasedLocking
-XX:+UseG1GC
-XX:G1HeapRegionSize=32M
-XX:+ExplicitGCInvokesConcurrent
-XX:+ExitOnOutOfMemoryError
-XX:+UseGCOverheadLimit
-XX:+HeapDumpOnOutOfMemoryError
-XX:+ExitOnOutOfMemoryError" > jvm.config

    # config.properties
    echo "
coordinator=true
node-scheduler.include-coordinator=true
http-server.http.port=${HETU_SERVER_PORT}
query.max-memory=50GB
query.max-total-memory=50GB
query.max-memory-per-node=10GB
query.max-total-memory-per-node=10GB
discovery-server.enabled=true
discovery.uri=http://${host_ip}:${HETU_SERVER_PORT}" > config.properties
}

function check_env()
{
    ss_schema_name=${database_name}
    ss_namespace=${namespace}
    ss_zk_lists=${server_lists}
    if [ "${ss_schema_name}" == "" ]; then
        echo "sharding database name is not set... "
        exit 1
    fi
    if [ "${ss_namespace}" == "" ]; then
        echo "sharding namespace is not set... "
        exit 1
    fi
    if [ "${ss_zk_lists}" == "" ]; then
        echo "zookeeper name is not set... "
        exit 1
    fi

    echo "export ss_schema_name=${ss_schema_name}" >> /home/omm/.bashrc
    echo "export ss_namespace=${ss_namespace}" >> /home/omm/.bashrc
    echo "export ss_zk_lists=${ss_zk_lists}" >> /home/omm/.bashrc
}

function main()
{
    if [ "$(id -u)" = '0' ]; then
        check_env
        install_jre
        chown -R omm:omm ${LOG_PATH}
        chown -R omm:omm ${CONFIG_PATH}
        # change to omm user
        exec gosu omm "$BASH_SOURCE" "$@"
    fi

    if [ $1 == "init" ]; then
        config_oel
        config_conn_ss
        chmod 755 ${OLK_HOME}/bin/*
        ${OLK_HOME}/bin/launcher run
        deadloop
    fi

}

main $@
