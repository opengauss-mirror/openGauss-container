

source util.sh
source install.sh

function parse_params()
{
        cmport=$(echo ${cmport} | sed 's/ //g')
        if [ "${cmport}" == "" ]; then
                echo "CM port is empty, use 25000 as default."
                cmport=25000
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

function set_envfile()
{
        echo "#HOST INFO" >> ${ENVFILE}
        echo "export PRIMARYHOST=${primary_host}" >> ${ENVFILE}
        echo "export STANDBYHOSTS=${standby_hosts}" >> ${ENVFILE}
        echo "export PRIMARYNAME=${primary_name}" >> ${ENVFILE}
        echo "export STANDBYNAMES=${standby_names}" >> ${ENVFILE}
        echo "export CMPORT=${cmport}" >> ${ENVFILE}
        echo "export SINGLE_MODE=0" >> ${ENVFILE}
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

function main()
{   
    parse_params
    if [ "$(id -u)" = '0' ]; then
            write_local_host
            exec gosu omm "$BASH_SOURCE" "$@"
    fi
    set_envfile
    source ${ENVFILE}
    create_cm_install_path
    install_cm_application
    generate_xml
    generate_static_config_file
    init_cm_config
    generate_cm_cert
    nohup $GAUSSHOME/bin/om_monitor -L $GAUSSLOG/cm/om_monitor &
}


main @