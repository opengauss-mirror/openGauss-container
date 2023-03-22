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
# build_distri_image.sh
#    Build distribute docker images
#
#-------------------------------------------------------------------------

ARCH=$(uname -p)
ROOT_DIR=$(pwd)
VERSION=5.0.0

sharding_image=opengauss-sharding
hetu_image=opengauss-hetu

docker_file=
gosu_file=
if [ "${ARCH}" == "aarch64" ]; then 
    docker_file=dockerfile_arm
    gosu_file=gosu-arm64
elif [ "${ARCH}" == "x86_64" ]; then
    docker_file=dockerfile_amd
    gosu_file=gosu-amd64
else
    echo "Unsupport platform $ARCH"
    exit 1
fi

function build_hetu()
{
    cd ${ROOT_DIR}/openlookeng
    cp ${ROOT_DIR}/${gosu_file} .
    docker build -t ${hetu_image}:${VERSION} -f ${docker_file} .
}

function build_sharding()
{
    cd ${ROOT_DIR}/sharding
    cp ${ROOT_DIR}/${gosu_file} .
    docker build -t ${sharding_image}:${VERSION} -f ${docker_file} .
}


function main()
{
    build_sharding
    build_hetu
}

main $@