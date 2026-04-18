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
#    openGauss-container/dockerfile/util.sh
#
#-------------------------------------------------------------------------

USER=omm
GROUP=omm
ENVFILE=/home/omm/.bashrc

DATA_BASE=/var/lib/opengauss
APP_PATH=/usr/local/opengauss

log_path=${DATA_BASE}/log
tmp_path=${DATA_BASE}/tmp
datanode_dir=${DATA_BASE}/data

app_path=${APP_PATH}/app
tool_path=${APP_PATH}/tools
package_path=${APP_PATH}/package

# cm path
cm_config_path=${DATA_BASE}/cm
cm_agent_path=${cm_config_path}/cm_agent
cm_server_path=${cm_config_path}/cm_server
cm_agent_log=${log_path}/cm/cm_agent
cm_server_log=${log_path}/cm/cm_server
monitor_log=${log_path}/cm/om_monitor

cluster_maintain_file=${APP_PATH}/cluster_maintain_file
