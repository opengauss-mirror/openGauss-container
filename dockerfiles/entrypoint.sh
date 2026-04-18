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

        # 0 with cm; 1 without cm
        declare -g SINGLE_MODE

        # 0 normal; 1 primary; 2 standby; 3 cascade_standby
        declare -g INSTANCE_TYPE
        

        declare -g DATABASE_ALREADY_EXISTS
        # look specifically for OG_VERSION, as it is expected in the DB dir
        if [ -s "$datanode_dir/PG_VERSION" ]; then
                DATABASE_ALREADY_EXISTS='true'
        fi

        declare -g DATABASE_APP_EXISTS
        if [ -d "$app_path" ] && [ -f "$app_path/bin/gaussdb" ]; then
                DATABASE_APP_EXISTS='true'
        fi

        declare -g NEED_INSTALL_CM_COMPONENT=0
        if [ -n "$DATABASE_ALREADY_EXISTS" ] && [ -n "DATABASE_APP_EXISTS" ]; then
                if [ -d "$cm_agent_path" ] && [ -f "$cm_agent_path/cm_agent.conf" ] && [ -d "$cm_server_path" ] && [ -f "$cm_server_path/cm_server.conf" ]; then
                        NEED_INSTALL_CM_COMPONENT=0
                else
                        NEED_INSTALL_CM_COMPONENT=1
                fi
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
        export GS_CLUSTER_NAME=cluster
        export PGPORT=${dbport}
        export CMPORT=${cmport}
        export SINGLE_MODE=${SINGLE_MODE}
        export INSTANCE_TYPE=${INSTANCE_TYPE}

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
        echo "export GS_CLUSTER_NAME=cluster" >>${ENVFILE}

        echo "#HOST INFO" >>${ENVFILE}
        echo "export PRIMARYHOST=${primary_host}" >>${ENVFILE}
        echo "export STANDBYHOSTS=${standby_hosts}" >>${ENVFILE}
        echo "export PRIMARYNAME=${primary_name}" >>${ENVFILE}
        echo "export STANDBYNAMES=${standby_names}" >>${ENVFILE}
        echo "export PGPORT=${dbport}" >>${ENVFILE}
        echo "export CMPORT=${cmport}" >>${ENVFILE}
        echo "export SINGLE_MODE=${SINGLE_MODE}" >>${ENVFILE}
        echo "export INSTANCE_TYPE=${INSTANCE_TYPE}" >>${ENVFILE}
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

function start_instance_loop() {
                source ${ENVFILE}

                opts=""
                if [ $INSTANCE_TYPE -eq 1 ]; then
                        opts=" -M primary"
                elif [ $INSTANCE_TYPE -eq 2 ]; then
                        opts=" -M standby"
                elif [ $INSTANCE_TYPE -eq 3 ]; then
                        opts=" -M cascade_standby"
                fi
                procstatus=$(ps ux | grep gaussdb  | grep ${datanode_dir} | grep -v grep)
                if [ "${procstatus}" == "" ]; then
                        echo "database instance is not running, start it."
                        gs_ctl start -D ${datanode_dir} ${opts}
                fi
}

function start_monitor_dead_loop() {

                monitor_proc=$(ps -aux | grep om_monitor | grep -v grep)
                #check if process exist
                if [ "${monitor_proc}" == "" ]; then
                        source ${ENVFILE}
                        nohup $GAUSSHOME/bin/om_monitor -L $GAUSSLOG/cm/om_monitor &
                fi
                #check if process SIGSTOP(kill -19)
                proc_stat=$(echo $monitor_proc | awk '{print $8}')
                if [[ $proc_stat = T* ]]; then
                        echo "om_monitor process has been hung up. wake up it."
                        pid=$(echo $monitor_proc | awk '{print $2}')
                        kill -18 ${pid}
                fi

}

function keep_loop() {
        i=1
        while ((i > 0)); do
                if [ -f "${cluster_maintain_file}" ]; then
                        echo "cluster maintain file ${cluster_maintain_file} exist, skip loop."
                        sleep 60
                        continue
                fi
                source ${ENVFILE}
                if [ $SINGLE_MODE -eq 1 ]; then
                        start_instance_loop
                else
                        start_monitor_dead_loop
                fi
                sleep 60
        done;
        
}

function check_env_hosts() {
        dbport=$(echo ${dbport} | sed 's/ //g')
        if [ "${dbport}" == "" ]; then
                echo "Database port is empty, use 5432 as default."
                dbport=5432
        fi

        cmport=$(echo ${cmport} | sed 's/ //g')
        if [ "${cmport}" == "" ]; then
                echo "CM port is empty, use 25000 as default."
                cmport=25000
        fi

        SINGLE_MODE=$(echo ${single} | sed 's/ //g')
        if [ "${SINGLE_MODE}" == "" ]; then
                echo "Single instance mode is empty, use 0 as default."
                SINGLE_MODE=0
        fi

        inst_type=$(echo ${instance_type} | sed 's/ //g')
        echo "Instance type is ${inst_type}."
        if [ "${inst_type}" == "" ]; then
                INSTANCE_TYPE=0
        elif [ "${inst_type}" == "primary" ]; then
                INSTANCE_TYPE=1
        elif [ "${inst_type}" == "standby" ]; then
                INSTANCE_TYPE=2
        elif [ "${inst_type}" == "cascade_standby" ]; then
                INSTANCE_TYPE=3
        else
                INSTANCE_TYPE=0
        fi
        
        if [ "$SINGLE_MODE" = 1 ] && [ "$INSTANCE_TYPE" = 0 ]; then
                echo "Single mode is ${SINGLE_MODE}, instance type is ${INSTANCE_TYPE}, skip check hosts."
                return
        fi

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

function clean_environment() {
        unset GS_PASSWORD
}

function start_at_install() {
        if [ $SINGLE_MODE -eq 0 ]; then
                nohup $GAUSSHOME/bin/om_monitor -L $GAUSSLOG/cm/om_monitor &
                return
        fi
        if [ $INSTANCE_TYPE -eq 0 ]; then
                gs_ctl start -D ${datanode_dir}
        elif [ $INSTANCE_TYPE -eq 1 ]; then
                gs_ctl start -D ${datanode_dir} -M primary
        elif [ $INSTANCE_TYPE -eq 2 ]; then
                gs_ctl start -D ${datanode_dir} -M standby
                gs_ctl build -D ${datanode_dir} -M standby
        elif [ $INSTANCE_TYPE -eq 3 ]; then
                gs_ctl start -D ${datanode_dir} -M cascade_standby
                gs_ctl build -D ${datanode_dir} -M cascade_standby
        fi
}

function main() {
        docker_setup_env
        if [ -n "$DATABASE_ALREADY_EXISTS" ]; then
                if [ "$(id -u)" = '0' ]; then
                        write_local_host
                        /usr/sbin/sshd -D &
                        exec gosu omm "$BASH_SOURCE" "$@"
                fi
                
                if [ -z "$DATABASE_APP_EXISTS" ]; then
                        check_env_hosts
                        echo "database already exists but application is not found, try install application."
                        set_envfile
                        config_user_ssh
                        create_install_path
                        install_application
                        generate_xml
                        generate_static_config_file
                        generate_cm_cert
                fi

                if [ "$NEED_INSTALL_CM_COMPONENT" = "1" -a "$SINGLE_MODE" = "0" ]; then
                        check_env_hosts
                        echo "database and application already exists but cm component is not found, try install cm component."
                        set_envfile
                        create_cm_install_path
                        install_cm_application
                        generate_xml
                        generate_static_config_file
                        init_cm_config
                        generate_cm_cert
                fi
                source ${ENVFILE}
                echo "openGauss Database directory appears to contain a database; Skipping init"
                keep_loop
                exit 0
        fi
        check_env_hosts
        if [ "$(id -u)" = '0' ]; then
                write_local_host
                # config_sshd
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
        start_at_install
        clean_environment
        keep_loop
}
if [ "$(id -u)" = '0' ]; then
        chown $USER:$GROUP /var/lib/opengauss
        chown $USER:$GROUP /usr/local/opengauss
        chmod 777 /tmp
fi


main $@
