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

    db_port=${PGPORT}
    ha_port=$(expr ${db_port} + 1)
    heartbeat_port=$(expr ${db_port} + 4)

    index=1
    for ((i = 0; i < ${#hostarr[@]}; i++)); do
        if [ "${correct_network_ip}" != "${hostarr[i]}" ]; then
            gs_guc set -D ${datanode_dir} -c "replconninfo${index}='localhost=${correct_network_ip} localport=${ha_port} localheartbeatport=${heartbeat_port} remotehost=${hostarr[i]} remoteport=${ha_port} remoteheartbeatport=${heartbeat_port}'"
            index=$(expr $index + 1)
        fi
        gs_guc set -D ${datanode_dir} -h "host all all ${hostarr[i]}/32 trust"
    done

    gs_guc set -D ${datanode_dir} -c "remote_read_mode=off"
    gs_guc set -D ${datanode_dir} -c "replication_type=1"
    gs_guc set -D ${datanode_dir} -c "port=${db_port}"
    gs_guc set -D ${datanode_dir} -c "listen_addresses='*'"
    gs_guc set -D ${datanode_dir} -c "max_connections=1000"

    #close mot
    echo "enable_numa = false" >>${datanode_dir}/mot.conf
}

function generate_static_config_file() {
    if [ $SINGLE_MODE -eq 1 ]; then
        echo "single instance mode, skip generate static config file."
        return
    fi

    if [ -f ${GAUSSHOME}/bin/cluster_static_config ]; then
        rm ${GAUSSHOME}/bin/cluster_static_config
    fi
    gs_om -t generateconf -X /home/omm/cluster.xml
    if [ $? -ne 0 ]; then
        echo "generate static config file failed..."
        exit 1
    fi
    cp ${tool_path}/script/static_config_files/cluster_static_config_${hostname} ${GAUSSHOME}/bin/cluster_static_config
    cp ${tool_path}/version.cfg ${app_path}/bin/upgrade_version
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
    if [ $SINGLE_MODE -eq 1 ]; then
        echo "single instance mode, skip init cm config."
        return
    fi

    cp ${GAUSSHOME}/share/config/cm_server.conf.sample ${cm_config_path}/cm_server/cm_server.conf
    cp ${GAUSSHOME}/share/config/cm_agent.conf.sample ${cm_config_path}/cm_agent/cm_agent.conf
    
    get_nodeid
    nodeid=$?
    if [ $nodeid == -1 ]; then
        echo "could not found nodeid of ${hostname}"
        exit 1
    fi

    cmserver_log=${cm_server_log}
    cmagent_log=${cm_agent_log}
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
    if [ $SINGLE_MODE -eq 1 ]; then
        echo "single instance mode, skip generate cm cert."
        return
    fi

    if [ ! -d $GAUSSHOME/share/sslcert/cm ]; then
        mkdir $GAUSSHOME/share/sslcert/cm
    fi
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
    timeout 600 sh create_trust.sh /home/omm/hostfile $GS_PASSWORD

}
function install_application() {
        cd ${package_path}
        enterprise_pkg_file=$(ls /openGauss-All-*.tar.gz)
        tar -xf ${enterprise_pkg_file} -C .
        plat_info=$(ls openGauss*.tar.bz2 | sed 's/openGauss-Server-\(.*\).tar.bz2/\1/g')
        tar -xf openGauss-Server-${plat_info}.tar.bz2 -C ${app_path}
        
        install_cm_application
}

function install_cm_application() {
        if [ "$SINGLE_MODE" -eq 1 ]; then
                echo "single instance mode, skip install cm component."
                return
        fi
        cd ${package_path}
        enterprise_pkg_file=$(ls /openGauss-All-*.tar.gz)
        tar -xf ${enterprise_pkg_file} -C .
        plat_info=$(ls openGauss*.tar.bz2 | sed 's/openGauss-Server-\(.*\).tar.bz2/\1/g')
        tar -xf openGauss-CM-${plat_info}.tar.gz -C ${app_path}
        tar -xf openGauss-OM-${plat_info}.tar.gz -C ${tool_path}
        # 拷贝python3依赖的lib
        python_version=$(python3 -V | awk '{print $2}' | awk -F'.' '{print $2}')
        cd ${tool_path}/lib/ || exit
        cp bcrypt/lib3.${python_version}/_bcrypt.abi3.so bcrypt/
        cp _cffi_backend_3.${python_version}/_cffi_backend.so ./
        cp cryptography/hazmat/bindings/lib3.${python_version}/*.so cryptography/hazmat/bindings/
        cp nacl/lib3.${python_version}/_sodium.abi3.so nacl/
}

function create_install_path() {

        dir_array=($app_path $log_path $tmp_path $tool_path $datanode_dir $package_path)
        for i in ${dir_array[*]}; do
                echo "${i}"
                mkdir -p "${i}"
        done
        create_cm_install_path
        chmod -R 700 $DATA_BASE
        chmod -R 700 $APP_PATH
}

function create_cm_install_path() {
        if [ "$SINGLE_MODE" -eq 1 ]; then
                echo "single instance mode, skip create cm component install path."
                return
        fi
        dir_array=($cm_agent_path $cm_server_path $cm_agent_log $cm_server_log $monitor_log)
        for i in ${dir_array[*]}; do
                echo "${i}"
                mkdir -p "${i}"
        done
}

function generate_xml() {
        if [ $SINGLE_MODE -eq 1 ]; then
                echo "single instance mode, skip generate cluster xml file."
                return
        fi
        echo "python3 /usr/local/bin/generatexml.py --primary-host=${primary_host} --standby-host=${standby_hosts} --primary-hostname=${primary_name} --standby-hostname=${standby_names}"
        python3 /usr/local/bin/generatexml.py --primary-host=${primary_host} --standby-host=${standby_hosts} --primary-hostname=${primary_name} --standby-hostname=${standby_names}
        if [ ! -f "/home/omm/cluster.xml" ]; then
                echo "generate cluster xml file failed."
                exit 1
        fi
        echo "generate cluster xml file success."
}

function install_main() {
    source ${ENVFILE}
    init_database
    generate_static_config_file
    init_cm_config
    generate_cm_cert
}
