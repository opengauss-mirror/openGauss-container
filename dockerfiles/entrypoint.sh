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
#    openGauss-container/dockerfile/entrypint.sh
#
#-------------------------------------------------------------------------

source util.sh
source install.sh

# Loads various settings that are used elsewhere in the script
# This should be called before any other functions
function docker_setup_env() {
        declare -g DATABASE_ALREADY_EXISTS
        # look specifically for OG_VERSION, as it is expected in the DB dir
        if [ -s "$datanode_dir/PG_VERSION" ]; then
                DATABASE_ALREADY_EXISTS='true'
        fi
}


function set_envfile() {
        export GPHOME=${tool_path}
        export PATH=$GPHOME/script/gspylib/pssh/bin:$GPHOME/script:$PATH
        export LD_LIBRARY_PATH=$GPHOME/lib:$LD_LIBRARY_PATH
        export PYTHONPATH=$GPHOME/lib
        export PGHOST=${tmp_path}
        export GAUSSHOME=${app_path}
        export LD_LIBRARY_PATH=$GAUSSHOME/lib:$LD_LIBRARY_PATH
        export PATH=${GAUSSHOME}/bin:${PATH}
        export GAUSSLOG=${log_path}

        echo "export GPHOME=${tool_path}" >${ENVFILE}
        echo "export PATH=$GPHOME/script/gspylib/pssh/bin:$GPHOME/script:$PATH" >>${ENVFILE}
        echo "export LD_LIBRARY_PATH=$GPHOME/lib:$LD_LIBRARY_PATH" >>${ENVFILE}
        echo "export PYTHONPATH=$GPHOME/lib" >>${ENVFILE}
        echo "export PGHOST=${tmp_path}" >>${ENVFILE}
        echo "export GAUSSHOME=${app_path}" >>${ENVFILE}
        echo "export LD_LIBRARY_PATH=$GAUSSHOME/lib:$LD_LIBRARY_PATH" >>${ENVFILE}
        echo "export PATH=${GAUSSHOME}/bin:${PATH}" >>${ENVFILE}
        echo "export GAUSSLOG=${log_path}" >>${ENVFILE}
        echo "export GAUSS_ENV=2" >>${ENVFILE}

        echo "#HOST INFO" >>${ENVFILE}
        echo "export PRIMARYHOST=${primary_host}" >>${ENVFILE}
        echo "export STANDBYHOSTS=${standby_hosts}" >>${ENVFILE}
        echo "export PRIMARYNAME=${primary_name}" >>${ENVFILE}
        echo "export STANDBYNAMES=${standby_names}" >>${ENVFILE}
}

function install_application() {
        cd ${package_path}
        tar -xf ${enterprise_pkg_file} -C .
        plat_info=$(ls openGauss*.tar.bz2 | sed 's/openGauss-\(.*\)-64bit.tar.bz2/\1/g')
        tar -xf openGauss-${plat_info}-64bit.tar.bz2 -C ${app_path}
        tar -xf openGauss-${plat_info}-64bit-cm.tar.gz -C ${app_path}
        tar -xf openGauss-${plat_info}-64bit-om.tar.gz -C ${tool_path}
        mv $ROOT_DIR/gs_createtrust.py ${tool_path}/script
}

function create_install_path() {
        if [ -d ${install_path} ]; then
                rm -rf ${install_path}
        fi

        dir_array=($app_path $log_path $tmp_path $tool_path $datanode_dir $package_path $cm_agent_path $cm_server_path $cm_agent_log $cm_server_log $monitor_log)
        for i in ${dir_array[*]}; do
                echo "${i}"
                mkdir -p "${i}"
        done
        chmod -R 700 /opengauss
}

function set_user_passwd() {
        echo "${GS_PASSWORD}" | passwd $USER --stdin
}

function config_user_ssh() {
        # config kown hosts to null
        # ssh-keyscan -t ed25519 hostip has no response in docker
        mkdir -m 700 -p /home/omm/.ssh
        touch /home/omm/.ssh/config
        echo "StrictHostKeyChecking no" >/home/omm/.ssh/config
        echo "UserKnownHostsFile /dev/null" >>/home/omm/.ssh/config
        echo "LogLevel ERROR" >>/home/omm/.ssh/config
        chmod 600 /home/omm/.ssh/config
}

function config_sshd() {
        # 在容器里面不加该配置，会导致ssh连接拒绝
        # ssh: connect to host dockerip port 22: Connection refused
        ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N '' >/dev/null
        ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -N '' >/dev/null
        ssh-keygen -t rsa -f /etc/ssh/ssh_host_ecdsa_key -N '' >/dev/null
        ssh-keygen -t rsa -f /etc/ssh/ssh_host_ed25519_key -N '' >/dev/null
        mkdir -p /var/run/sshd

        /usr/sbin/sshd -D &
}

function write_local_host() {
        hostfile=/etc/hosts
        hostarr=(${primary_host})
        standby_hostarr=(${standby_hosts})
        hostarr+=(${standby_hostarr//,/ })

        hostnamearr=(${primary_name})
        standby_hostnamearr=(${standby_names})
        hostnamearr+=(${standby_names//,/ })

        index=1
        for ((i = 0; i < ${#hostarr[@]}; i++)); do
                echo "${hostarr[i]} ${hostnamearr[i]} #GAUSS OM" >>/etc/hosts
                echo "${hostarr[i]}" >>/home/omm/hostfile
        done

        chown $USER:$GROUP /home/omm/hostfile
}

function start_monitor_dead_loop() {
        i=1
        while ((i > 0)); do
                monitor_proc=$(ps -ef | grep om_monitor | grep -v grep)
                if [ "${monitor_proc}" == "" ]; then
                        source ${ENVFILE}
                        nohup $GAUSSHOME/bin/om_monitor -L $GAUSSLOG/cm/om_monitor &
                fi
                sleep 60
        done
}

function check_env_hosts() {
        primary_host=$(echo ${primaryhost} | sed 's/ //g')
        if [ "${primary_host}" == "" ]; then
                echo "Primary host is empty, at least one primary and one standby host are needed."
                exit 1
        fi
        standby_hosts=$(echo ${standbyhosts} | sed 's/ //g')
        if [ "${standby_hosts}" == "" ]; then
                echo "Standby hosts are empty, at least one primary and one standby host are needed."
                exit 1
        fi
        primary_name=$(echo ${primaryname} | sed 's/ //g')
        if [ "${primary_name}" == "" ]; then
                echo "Primary name is empty, at least one primary and one standby host are needed."
                exit 1
        fi

        standby_names=$(echo ${standbynames} | sed 's/ //g')
        if [ "${standby_names}" == "" ]; then
                echo "Standby names are empty, at least one primary and one standby host are needed."
                exit 1
        fi
}
function generate_xml() {
        echo "python3 /usr/local/bin/generatexml.py --primary-host=${primary_host} --standby-host=${standby_hosts} --primary-hostname=${primary_name} --standby-hostname=${standby_names}"
        python3 /usr/local/bin/generatexml.py --primary-host=${primary_host} --standby-host=${standby_hosts} --primary-hostname=${primary_name} --standby-hostname=${standby_names}
        if [ ! -f "/home/omm/cluster.xml" ]; then
                echo "generate cluster xml file failed."
                exit 1
        fi
        echo "generate cluster xml file success."
}
function clean_environment() {

        unset GS_PASSWORD

        pkgfile=$(ls /opengauss/openGauss*)
        if [ "$pkgfile" != "" ]; then
                rm ${pkgfile}
        fi
}

function main() {
        docker_setup_env
        if [ -f "$DATABASE_ALREADY_EXISTS" ]; then
                echo "openGauss Database directory appears to contain a database; Skipping install."
                exit 0
        fi
        check_env_hosts
        if [ "$(id -u)" = '0' ]; then
                write_local_host
                config_sshd
                set_user_passwd
                # change to omm user
                exec gosu omm "$BASH_SOURCE" "$@"
        fi
        config_user_ssh
        create_install_path
        install_application
        set_envfile
        generate_xml
        install_main
        nohup $GAUSSHOME/bin/om_monitor -L $GAUSSLOG/cm/om_monitor &
        create_user_trust
        clean_environment
        start_monitor_dead_loop
}

main $@
