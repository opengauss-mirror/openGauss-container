
#!/bin/bash
# create cm docker containers
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
# create_cm_containers.sh
#    create cm container with one master and two slaves instance.
#
# IDENTIFICATION
#    openGass-container/create_cm_containers.sh
#
#-------------------------------------------------------------------------

#set OG_SUBNET,GS_PASSWORD,MASTER_IP,SLAVE_1_IP,MASTER_HOST_PORT,MASTER_LOCAL_PORT,SLAVE_1_HOST_PORT,SLAVE_1_LOCAL_PORT,MASTER_NODENAME,SLAVE_NODENAME

echo "This script will create three containers with cm on a single node. \n"

read -p "Please input OG_SUBNET (容器所在网段) [173.11.0.0/24]: " OG_SUBNET
OG_SUBNET=${OG_SUBNET:-173.11.0.0/24}
echo "OG_SUBNET set $OG_SUBNET"

read -p "Please input OG_NETWORK (容器网络名称) [og-distri]: " OG_NETWORK
OG_NETWORK=${OG_NETWORK:-og-distri}
echo "OG_NETWORK set $OG_NETWORK"

read -s -p "Please input GS_PASSWORD (定义数据库密码)[test@123]: " GS_PASSWORD
GS_PASSWORD=${GS_PASSWORD:-test@123}
echo -e "\nGS_PASSWORD set"

read -p "Please input openGauss VERSION [5.0.0]: " VERSION
VERSION=${VERSION:-5.0.0}
echo "openGauss VERSION set $VERSION"

function check_input()
{
    docker_exist=`docker images |grep -w opengauss | grep -w $VERSION`
    if [ "$docker_exist" == "" ]; then
        echo "docker images opengauss:$VERSION not found."
    fi
}

check_input

echo "starting  create docker containers..."

docker network create --subnet=$OG_SUBNET ${OG_NETWORK} \
|| {
  echo ""
  echo "ERROR: OpenGauss Database Network was NOT successfully created."
  echo "HINT: ${OG_NETWORK} Maybe Already Exsist Please Execute 'docker network rm ${OG_NETWORK}' "
  exit OG_NETWORK
}


echo "OpenGauss Database Network Created."


netwk_ip=$(echo $OG_SUBNET | awk -F . '{print $1"."$2"."$3}')
primary_nodeip="${netwk_ip}.2"
standby1_nodeip="${netwk_ip}.3"
primary_nodename=primary
standby1_nodename=standby1
echo "Create first cluster: $primary_nodeip,$standby1_nodeip"
echo "Primary: $primary_nodename   $primary_nodeip"
echo "Standby1: $standby1_nodename $standby1_nodeip"

docker run -d -it -P  --sysctl kernel.sem="250 6400000 1000 25600" --security-opt seccomp=unconfined --name cluster1-p --net ${OG_NETWORK} --ip "$primary_nodeip" -h=$primary_nodename -e primaryhost="$primary_nodeip" -e primaryname="$primary_nodename" -e standbyhosts="$standby1_nodeip" -e standbynames="$standby1_nodename" -e GS_PASSWORD=$GS_PASSWORD opengauss:$VERSION 

docker run -d -it -P  --sysctl kernel.sem="250 6400000 1000 25600" --security-opt seccomp=unconfined --name cluster1-s1 --net ${OG_NETWORK} --ip "$standby1_nodeip" -h=$standby1_nodename -e primaryhost="$primary_nodeip" -e primaryname="$primary_nodename" -e standbyhosts="$standby1_nodeip" -e standbynames="$standby1_nodename" -e GS_PASSWORD=$GS_PASSWORD opengauss:$VERSION



primary_nodeip="${netwk_ip}.5"
standby1_nodeip="${netwk_ip}.6"
primary_nodename=primary
standby1_nodename=standby1

echo "Create second cluster: $primary_nodeip,$standby1_nodeip"
echo "Primary: $primary_nodename   $primary_nodeip"
echo "Standby1: $standby1_nodename $standby1_nodeip"


docker run -d -it -P  --sysctl kernel.sem="250 6400000 1000 25600" --security-opt seccomp=unconfined --name cluster2-p --net ${OG_NETWORK} --ip "$primary_nodeip" -h=$primary_nodename -e primaryhost="$primary_nodeip" -e primaryname="$primary_nodename" -e standbyhosts="$standby1_nodeip" -e standbynames="$standby1_nodename" -e GS_PASSWORD=$GS_PASSWORD opengauss:$VERSION 

docker run -d -it -P  --sysctl kernel.sem="250 6400000 1000 25600" --security-opt seccomp=unconfined --name cluster2-s1 --net ${OG_NETWORK} --ip "$standby1_nodeip" -h=$standby1_nodename -e primaryhost="$primary_nodeip" -e primaryname="$primary_nodename" -e standbyhosts="$standby1_nodeip" -e standbynames="$standby1_nodename" -e GS_PASSWORD=$GS_PASSWORD opengauss:$VERSION

echo "OpenGauss Database Docker Containers created."