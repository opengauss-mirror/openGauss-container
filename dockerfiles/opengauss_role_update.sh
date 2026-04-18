#!/bin/bash
# Build docker image
# Copyright (c) Huawei Technologies Co., Ltd. 2026. All rights reserved.
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
#    openGauss-container/dockerfile/opengauss_role_update.sh
#
#-------------------------------------------------------------------------

source util.sh

function main() { 
        if [ "$(id -u)" = '0' ]; then
                exec gosu omm "$BASH_SOURCE" "$@"
        fi
        source ${ENVFILE}
        if [ ${SINGLE_MODE} -eq 0 ]; then
                echo "update role is only need as single mode"
                exit 0
        fi

        role=$(gs_ctl query -D ${datanode_dir} | grep -i local_role | head -n 1 | awk -F ':' '{print $2}' | xargs | tr 'A-Z' 'a-z')
        if [ "${role}" = "primary" ]; then
            sed -i "s/INSTANCE_TYPE=*.*/INSTANCE_TYPE=1/g" ${ENVFILE}
            echo "update role to primary successfully."
        elif [ "${role}" = "standby" ]; then
            sed -i "s/INSTANCE_TYPE=*.*/INSTANCE_TYPE=2/g" ${ENVFILE}
            echo "update role to standby successfully."
        else
            echo "Node role is ${role}, no need to update role."
            exit 0
        fi

}

main $@
