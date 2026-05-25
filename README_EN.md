## CM Containerized Deployment

### Creating an openGauss Docker Image

Download the openGauss Docker repository code. The build script is managed in this repository.

>-   The openGauss community-released enterprise version package `openGauss-*-64bit-all.tar.gz` is required for image building. Place it in the `openGauss-docker/dockerfiles` directory.
>-   When you run the `buildDockerImage.sh script`, if the -i parameter is not specified, the SHA256 verification is performed by default. You need to manually write the verification result to the `sha256_file_amd64` file.
>    ```
>    ## Modify the SHA256 file.
>    cd `openGauss-docker/dockerfiles`
>    sha256sum openGauss-5.0.0-CentOS-64bit-all.tar.gz > sha256_file_amd64 
>    ```

>-   For the x86, use the CentOS_x86_64 package released by the community. For the ARM, use the openEuler-arm enterprise package released by the community.

Build command:
```
sh buildDockerImage.sh -v 5.0.0 -i
```

### Using the Image Released by the Community

The latest container image:

x86_64:
```
docker pull swr.cn-north-4.myhuaweicloud.com/opengauss-x86-64/opengauss-cm:6.0.2
docker tag swr.cn-north-4.myhuaweicloud.com/opengauss-x86-64/opengauss-cm:6.0.2 opengauss-cm:6.0.2
```

ARM:
```
docker pull swr.cn-north-4.myhuaweicloud.com/opengauss-aarch64/opengauss-cm:6.0.2
docker tag swr.cn-north-4.myhuaweicloud.com/opengauss-aarch64/opengauss-cm:6.0.2 opengauss-cm:6.0.2
```

### Starting the Container

At least two container instances are required to set up a CM cluster.

1. Create a container network.

##### If multiple containers are deployed on a single host, a standard bridge network is sufficient:
`docker network create --subnet=172.11.0.0/24 og-network`

##### If containers are deployed across multiple nodes, the containers must be able to communicate with each other. There are multiple methods in the industry. The following is one example for reference. You can choose the method that best suits your needs.

Choose one to deploy the Progrium/Consul container.
```
docker pull progrium/consul
docker run -d -p 8500:8500 -h consul --name consul progrium/consul -server -bootstrap
```

Modify the Docker configuration on each node:
vim /usr/lib/systemd/system/docker.service
Add the following information to the end of the `ExecStart` column:
```
-H tcp://0.0.0.0:2376 -H unix:///var/run/docker.sock --cluster-store=consul://192.168.0.94:8500 --cluster-advertise=eth0:2376
```
**192.168.0.94** indicates the IP address where the Consul is deployed.

After the modification, restart the Docker:
```
systemctl daemon-reload
systemctl restart docker
```

Create the overlay network.
```
docker network create -d overlay --subnet 10.22.1.0/24  --gateway 10.22.1.1 og-network
```

1. Start multiple container instances.
   
```
# The IP addresses must be in the same network segment as the container network. The IP addresses and node names of the instances cannot be duplicate. In the following example, there are one primary instance and two standby instances.

primary_nodeip="172.11.0.2"
standby1_nodeip="172.11.0.3"
standby2_nodeip="172.11.0.4"
primary_nodename=primary
standby1_nodename=standby1
standby2_nodename=standby2

OG_NETWORK=og-network
GS_PASSWORD=test@123

# Start instance 1
docker run -d -it -P  --sysctl kernel.sem="250 6400000 1000 25600" --security-opt seccomp=unconfined -v /data/opengauss_volume:/volume --name opengauss-01 --net ${OG_NETWORK} --ip "$primary_nodeip" -h=$primary_nodename -e primaryhost="$primary_nodeip" -e primaryname="$primary_nodename" -e standbyhosts="$standby1_nodeip, $standby2_nodeip" -e standbynames="$standby1_nodename, $standby2_nodename" -e GS_PASSWORD=$GS_PASSWORD opengauss-cm:6.0.2

# Start instance 2
docker run -d -it -P  --sysctl kernel.sem="250 6400000 1000 25600" --security-opt seccomp=unconfined -v /data/opengauss_volume:/volume --name opengauss-02 --net ${OG_NETWORK} --ip "$standby1_nodeip" -h=$standby1_nodename -e primaryhost="$primary_nodeip" -e primaryname="$primary_nodename" -e standbyhosts="$standby1_nodeip, $standby2_nodeip" -e standbynames="$standby1_nodename, $standby2_nodename" -e GS_PASSWORD=$GS_PASSWORD opengauss-cm:6.0.2

# Start instance 3
docker run -d -it -P  --sysctl kernel.sem="250 6400000 1000 25600" --security-opt seccomp=unconfined -v /data/opengauss_volume:/volume --name opengauss-03 --net ${OG_NETWORK} --ip "$standby2_nodeip" -h=$standby2_nodename -e primaryhost="$primary_nodeip" -e primaryname="$primary_nodename" -e standbyhosts="$standby1_nodeip, $standby2_nodeip" -e standbynames="$standby1_nodename, $standby2_nodename" -e GS_PASSWORD=$GS_PASSWORD opengauss-cm:6.0.2
```

Description

> If the primary and standby instances are running on separate nodes and utilize host networking (by adding --net host) instead of a container network, the --ip "$primary_nodeip" parameter should be removed from the execution command. \
> That is, the IP address cannot be specified in the host network because the IP address is fixed to be the same as that of the host. The IP address can be specified only in the custom container network.

> For the container network, you can configure SSH mutual trust between several nodes, which is required only in a few scenarios for CM. \
> For the host network, this trust relationship cannot be established between containers (because the host IP address is the same as the host IP address). Therefore, the OM tool cannot be used in the container as OM tools strongly depend on SSH trust for multi-node management.


3. Use the script to quickly start the 1-primary and 2-standby CM cluster container instance.

In the `openGauss-docker` directory, run the `sh create_cm_containers.sh` command.

```
This script will create three containers with cm on a single node. \n
Please input OG_SUBNET (container network segment) [172.11.0.0/24]:
OG_SUBNET set 172.11.0.0/24
Please input OG_NETWORK (container network name) [og-network]:
OG_NETWORK set og-network
Please input GS_PASSWORD (database password) [test@123]:
GS_PASSWORD set
Please input openGauss VERSION [5.0.0]: 
openGauss VERSION set 5.0.0
starting  create docker containers...
```

You need to enter the container network segment, container network name, database password, and container version. If you use the default value, press `Enter` to skip it.
After the script is executed, three container instances are started to form a CM cluster with one primary instance and two standby instances.

### Accessing the Container to Check the Instance Status

1. Access the container.
```
docker exec -ti <containerid> /bin/bash
su - omm
```

2. Check the cluster status.
```
cm_ctl query -Cvid
```

3. Connect to the database.
```
gsql -d postgres -r
```

>Description
>
>- 1. The container to be built must contain the OS layer.
>
>- 2. Only the CM and database kernel tools are provided in the container. The OM tool cannot be used.
