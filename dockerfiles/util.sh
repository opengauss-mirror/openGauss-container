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

ROOT_DIR=/opengauss

install_path=$ROOT_DIR/cluster

app_path=${install_path}/app
log_path=${install_path}/log
tmp_path=${install_path}/tmp
tool_path=${install_path}/tool
package_path=${install_path}/package_path
datanode_dir=${install_path}/datanode/dn1

# cm path
cm_config_path=${install_path}/cm
cm_agent_path=${cm_config_path}/cm_agent
cm_server_path=${cm_config_path}/cm_server
cm_agent_log=${log_path}/cm/cm_agent
cm_server_log=${log_path}/cm/cm_server
monitor_log=${log_path}/cm/om_monitor

# all_package_file=openGauss-${OPENGAUSS_VERSION}-${PLATFROM}-64bit-all.tar.gz
enterprise_pkg_file=$(ls ${ROOT_DIR}/openGauss-*-all.tar.gz)
