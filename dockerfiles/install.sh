#!/bin/bash
# Build docker image
# Copyright (c) Huawei Technologies Co., Ltd. 2023. All rights reserved.
#
#openGauss is licensed under Mulan PSL v2.
#You can use this software according to the terms and conditions of the Mulan PSL v2.
#You may obtain a copy of Mulan PSL v2 at:
#
#          http://license.coscl.org.cn/MulanPSL2
#
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.
#-------------------------------------------------------------------------
#
# entrypint.sh
#    Build docker image
#
# IDENTIFICATION
#    openGauss-container/dockerfile/install.sh
#
#-------------------------------------------------------------------------

source util.sh

hostname=$(hostname)

# query the actually docker ip
# compared with docker params by user input.
function get_real_ip() {
    correct_network_ip=
    hostarr=$1
    curiparr=$2
    for ((i = 0; i < ${#hostarr[@]}; i++)); do

        for ((j = 0; j < ${#curiparr[@]}; j++)); do
            if [ "${hostarr[i]}" = "${curiparr[j]}" ]; then
                correct_network_ip="${hostarr[i]}"
            fi
        done
    done
    echo ${correct_network_ip}
}

function init_database() {
    # init datanode with parameters
    gs_initdb -D ${datanode_dir} --nodename=nodename -w ${GS_PASSWORD}

    if [ $? -ne 0 ]; then
        echo "init database datanode failed."
        exit 1
    fi

    curips=$(ifconfig -a | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | tr -d "addr:")
    hostarr=(${PRIMARYHOST})
    standby_hosts=${STANDBYHOSTS}
    hostarr+=(${standby_hosts//,/ })
    curiparr=(${curips// / })

    correct_network_ip=$(get_real_ip $hostarr $curiparr)

    index=1
    for ((i = 0; i < ${#hostarr[@]}; i++)); do
        if [ "${correct_network_ip}" != "${hostarr[i]}" ]; then
            gs_guc set -D ${datanode_dir} -c "replconninfo${index}='localhost=${correct_network_ip} localport=5433 localheartbeatport=5436 remotehost=${hostarr[i]} remoteport=5433 remoteheartbeatport=5436'"
            index=$(expr $index + 1)
        fi
        gs_guc set -D ${datanode_dir} -h "host all all ${hostarr[i]}/32 trust"
    done

    gs_guc set -D ${datanode_dir} -c "remote_read_mode=off"
    gs_guc set -D ${datanode_dir} -c "replication_type=1"
    gs_guc set -D ${datanode_dir} -c "port=5432"
    gs_guc set -D ${datanode_dir} -c "listen_addresses='*'"
    gs_guc set -D ${datanode_dir} -c "max_connections=5000"

    #close mot
    echo "enable_numa = false" >>${datanode_dir}/mot.conf
}

function generate_static_config_file() {
    if [ -f ${GAUSSHOME}/bin/cluster_static_config ]; then
        rm ${GAUSSHOME}/bin/cluster_static_config
    fi
    gs_om -t generateconf -X /home/omm/cluster.xml
    if [ $? -ne 0 ]; then
        echo "generate static config file failed..."
        exit 1
    fi
    cp /opengauss/cluster/tool/script/static_config_files/cluster_static_config_${hostname} ${GAUSSHOME}/bin/cluster_static_config
}

function get_nodeid() {
    nodeid=-1
    c=0
    for line in $(cm_ctl view); do
        account=$line
        accounts[$c]=$account
        if [ "$account" == "nodeName:$hostname" ]; then
            string=${accounts[$c - 1]}
            array=(${string//\:/ })
            nodeid=${array[-1]}
            break
        fi
        ((c++))
    done
    return $nodeid
}

function init_cm_config() {
    cp ${GAUSSHOME}/share/config/cm_server.conf.sample ${cm_config_path}/cm_server/cm_server.conf
    cp ${GAUSSHOME}/share/config/cm_agent.conf.sample ${cm_config_path}/cm_agent/cm_agent.conf
    if [ ! -d $GAUSSHOME/share/sslcert/cm ]; then
        mkdir $GAUSSHOME/share/sslcert/cm
    fi
    get_nodeid
    nodeid=$?
    if [ $nodeid == -1 ]; then
        echo "could not found nodeid of ${hostname}"
        exit 1
    fi

    cmserver_log=${GAUSSLOG}/cm/cm_server
    cmagent_log=${GAUSSLOG}/cm/cm_agent
    cm_ctl set --param --server -k log_dir="'${cmserver_log}'" -n $nodeid
    cm_ctl set --param --agent -k log_dir="'${cmagent_log}'" -n $nodeid
    cm_ctl set --param --agent -k unix_socket_directory="'$GAUSSHOME'" -n $nodeid
    cm_ctl set --param --agent -k enable_ssl="off" -n $nodeid
    cm_ctl set --param --server -k enable_ssl="off" -n $nodeid
}

# expect_encrypt "cmd" "password" "success info"
function expect_encrypt() {
    /usr/bin/expect <<-EOF
        set timeout -1
        spawn $1
        expect {
                "*yes/no" { send "yes\r"; exp_continue }
                "*password:" { send "$2\r"; exp_continue }
                "*password again:" { send "$2\r"; exp_continue }
                "*$3*" { exit }
        }
        expect eof
EOF
    if [ $? == 0 ]; then
        return 0
    else
        return 1
    fi
}

function expect_createtrust() {
    /usr/bin/expect <<-EOF
        set timeout -1
        spawn $1
        expect {
                "Password:" { send "$2\r"; exp_continue }
                "*$3*" { exit }
        }
        expect eof
EOF
    if [ $? == 0 ]; then
        return 0
    else
        return 1
    fi
}

function generate_cm_cert() {
    client_cmd="cm_ctl encrypt -M client -D $GAUSSHOME/share/sslcert/cm"
    server_cmd="cm_ctl encrypt -M server -D $GAUSSHOME/share/sslcert/cm"
    expect_encrypt "${client_cmd}" "${GS_PASSWORD}" "encrypt success."
    expect_encrypt "${server_cmd}" "${GS_PASSWORD}" "encrypt success."
}

function _test_trust_expect()
{
    hostip=$1
    source ~/.bashrc
    /usr/bin/expect <<-EOF
        set timeout 30
        spawn ssh $hostip "echo okokok"
        expect {
                "okokok:" { exit 0 }
                "*password*" { exit 1 }
                "*connecting*" { exit 1 }
                "*not known*" {exit 1}
        }
EOF
    if [ $? == 0 ]; then
        return 0
    else
        return 1
    fi
}

function _test_hosts_trust() {
    hostarr=(${PRIMARYNAME})
    standby_hosts=${STANDBYNAMES}
    hostarr+=(${standby_hosts//,/ })

    test_trust_ok=0
    for ((i = 0; i < ${#hostarr[@]}; i++)); do
        _test_trust_expect ${hostarr[i]}
        if [ $? -ne 0 ]; then
            test_trust_ok=1
        fi
    done
    return $test_trust_ok
}

function create_user_trust() {
    echo "start to create omm user trust"
    cp ${app_path}/bin/encrypt ${tool_path}/script/gspylib/clib/
    expect_createtrust "python3 ${tool_path}/script/gs_createtrust.py -f /home/omm/hostfile -l create_trust.log" $GS_PASSWORD "Successfully created SSH trust"

    if [ "$hostname" == "${PRIMARYNAME}" ]; then
        sleep 30
        max_retry_times=5
        for ((i = 1; i <= $max_retry_times; i++)); do
            _test_hosts_trust
            if [ $? == 0 ]; then
                echo "create host trust success."
                break
            fi
            echo "create trust failed for $i time. we will rebuild again."
            expect_createtrust "python3 ${tool_path}/script/gs_createtrust.py -f /home/omm/hostfile -l create_trust.log" $GS_PASSWORD "Successfully created SSH trust"
        done
    fi

}

function install_main() {
    source ${ENVFILE}
    init_database
    generate_static_config_file
    init_cm_config
    generate_cm_cert
}
