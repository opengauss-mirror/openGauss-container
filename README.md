# main 分支说明

main分支修改了安装目录和数据目录，其中数据目录和单机容器保持一致，可以支持单机容器扩容到带CM的主备容器场景。
支持主备容器使用宿主机网络
支持CM和数据库端口自定义
支持数据目录和app目录挂载

# 使用说明 （支持容器网络和宿主机网络）

## 参数说明

1. --sysctl kernel.sem="250 6400000 1000 25600"  指定系统信号量大小
2. --security-opt seccomp=unconfined 支持运行权限，否则数据库运行有可能会缺失mbind报错。
3. --net 指定使用容器网络还是宿主机网络
4. -h= 指定容器内名称
5. --ip 指定容器的ip，主备通过ip通信，安装时候就要需要确定ip。 （通过--net host宿主机网络部署主备不需要这个参数）
6. -e primaryhost= 集群有主备之分，指定主节点的ip
7. -e primaryname= 指定主节点名称
8. -e standbyhosts= 指定备节点ip，多个备机以逗号分隔
9. -e standbynames= 指定备节点容器内名称，多个备机以逗号分隔
10. -e GS_PASSWORD= 设置数据库密码
11. -e dbport= 指定数据库端口，会监听 port， port+1, port+4，默认5432，如果主备走容器网络不会占用宿主机端口可以不用配置
12. -e cmport= 指定CM使用的端口，会监听 port, port+1,port+2,默认25000，如果主备走容器网络不会占用宿主机端口可以不用配置
13. -v 宿主机和容器目录改在，涉及两个目录, 数据目录/var/lib/opengauss必须挂在到宿主机避免数据丢失; 二进制目录/usr/local/opengauss非必选，建议挂载，否则误删除容器后需要重装。
14. opengauss-cm:6.0.3  容器镜像名称
15. -e single 启动为单机模式. single=1单机主备模式不带CM， single=0 CM集群模式。
16. -e instance_type=primary | standby | cascade_standby 单机模式下初始化容器指定主备参数

### 容器内说明

维护文件： /usr/local/opengauss/cluster_maintain_file， enctrypoint.sh作为守护进程会检测数据库进程不存在而重拉，如果需要主动停止进程进行维护，创建这个文件后可以手动重启等操作。

## 主备容器使用宿主机网络 net=host运行

启动需要传入这些参数：
```
primary_nodeip="20.20.20.54"
standby1_nodeip="20.20.20.56"
primary_nodename=primary
standby1_nodename=standby1

OG_NETWORK=host
GS_PASSWORD=test@123
```

### 启动实例1
```
docker run -d -it -P  --sysctl kernel.sem="250 6400000 1000 25600" --security-opt seccomp=unconfined  --name opengauss-01 --net ${OG_NETWORK}  -h=$primary_nodename -e primaryhost="$primary_nodeip" -e primaryname="$primary_nodename" -e standbyhosts="$standby1_nodeip" -e standbynames="$standby1_nodename" -e GS_PASSWORD=$GS_PASSWORD -v /usr2/zxb/cmtest:/var/lib/opengauss -e dbport=22100 -e cmport=22200 opengauss-cm:6.0.3
```

### 启动实例2
```
docker run -d -it -P  --sysctl kernel.sem="250 6400000 1000 25600" --security-opt seccomp=unconfined  --name opengauss-02 --net ${OG_NETWORK}  -h=$standby1_nodename -e primaryhost="$primary_nodeip" -e primaryname="$primary_nodename" -e standbyhosts="$standby1_nodeip" -e standbynames="$standby1_nodename" -e GS_PASSWORD=$GS_PASSWORD -v /usr2/zxb/cmtest:/var/lib/opengauss  -e dbport=22100 -e cmport=22200 opengauss-cm:6.0.3
```


## 主备容器使用自定义容器网络运行

todo

## 从不带CM单机容器（server仓发布的容器镜像）扩主备，在部署到带cm容器 -- 使用宿主机网络

### 1. 通过主机网络搭建主备容器（不带CM -- Server仓库的容器）

```
docker run --name opengauss-og1 --privileged=true --network=host -d -e GS_PASSWORD=Test@123 -v /usr2/zxb/cmtest:/var/lib/opengauss opengauss-tde:6.0.3sp2

docker run --name opengauss-og2 --privileged=true --network=host -d -e GS_PASSWORD=Test@123 -v /usr2/zxb/cmtest:/var/lib/opengauss opengauss-tde:6.0.3sp2 -M standby
```

配置容器端口是22100 （5432被占用情况下可以自定义配置）
```
echo "port=22100" >> /usr2/zxb/cmtest/data/postgresql.conf
```

启动容器
```
docker start opengauss-og1
docker start opengauss-og2
```
### 2. 配置主备参数

配置主机参数
```
primary_name=opengauss-og1
docker exec ${primary_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c \"replconninfo1='localhost=20.20.20.54 localport=22101 localheartbeatport=22104 localservice=22105 remotehost=20.20.20.56 remoteport=22101 remoteheartbeatport=22104 remoteservice=22105'\""
docker exec ${primary_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c 'remote_read_mode=off'"
docker exec ${primary_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c 'replication_type=1'"
docker exec ${primary_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c \"application_name='dn_master'\""
docker exec ${primary_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -h 'host all omm 20.20.20.54/32 trust'"
docker exec ${primary_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -h 'host all omm 20.20.20.56/32 trust'"
```


配置备机参数
```
standby_name=opengauss-og2
docker exec ${standby_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c \"replconninfo1='localhost=20.20.20.56 localport=22101 localheartbeatport=22104 localservice=22105 remotehost=20.20.20.54 remoteport=22101 remoteheartbeatport=22104 remoteservice=22105'\""
docker exec ${standby_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c 'remote_read_mode=off'"
docker exec ${standby_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c 'replication_type=1'"
docker exec ${standby_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c \"application_name='dn_standby1'\""
docker exec ${standby_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -h 'host all omm 20.20.20.54/32 trust'"
docker exec ${standby_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -h 'host all omm 20.20.20.56/32 trust'"
```


### 3. 备机启动为后端方式
```
docker stop ${standby_name}
docker rm ${standby_name}
docker run --name ${standby_name} --privileged=true --network=host -d -e GS_PASSWORD=Test@123 -v /usr2/zxb/cmtest:/var/lib/opengauss -it --entrypoint /bin/bash opengauss-tde:6.0.3sp2
```


### 4. 备机全量拉取主机数据
```
docker exec ${standby_name} su - omm -c "gs_ctl build -D /var/lib/opengauss/data -M standby"
```

### 5. 备机以standby方式重启 （去掉  -it --entrypoint /bin/bash ）
```
docker stop ${standby_name}
docker rm ${standby_name}
docker run --name ${standby_name} --privileged=true --network=host -d -e GS_PASSWORD=Test@123 -v /usr2/zxb/cmtest:/var/lib/opengauss opengauss-tde:6.0.3sp2 -M standby
```

查询
```
docker exec ${standby_name} su - omm -c "gs_ctl query -D /var/lib/opengauss/data"
```

### 6. 停止主备容器

```
docker stop ${standby_name}
docker stop ${primary_name}
```

### 7. 分别使用带CM的容器镜像启动主备容器

注意保证挂载的数据目录和不带CM的容器一致。 其他参数参考上面介绍。

主机启动
```
primary_nodeip="20.20.20.54"
standby1_nodeip="20.20.20.56"
primary_nodename=primarycm
standby1_nodename=standby1cm

OG_NETWORK=host
GS_PASSWORD=test@123

docker run -d -it -P  --sysctl kernel.sem="250 6400000 1000 25600" --security-opt seccomp=unconfined  --name opengauss-01 --net ${OG_NETWORK}  -h=$primary_nodename -e primaryhost="$primary_nodeip" -e primaryname="$primary_nodename" -e standbyhosts="$standby1_nodeip" -e standbynames="$standby1_nodename" -e GS_PASSWORD=$GS_PASSWORD -v /usr2/zxb/cmtest:/var/lib/opengauss -e dbport=22100 -e cmport=22200 opengauss-cm:6.0.3
```

备机启动
```
primary_nodeip="20.20.20.54"
standby1_nodeip="20.20.20.56"
primary_nodename=primarycm
standby1_nodename=standby1cm

OG_NETWORK=host
GS_PASSWORD=test@123


docker run -d -it -P  --sysctl kernel.sem="250 6400000 1000 25600" --security-opt seccomp=unconfined  --name opengauss-02 --net ${OG_NETWORK}  -h=$standby1_nodename -e primaryhost="$primary_nodeip" -e primaryname="$primary_nodename" -e standbyhosts="$standby1_nodeip" -e standbynames="$standby1_nodename" -e GS_PASSWORD=$GS_PASSWORD -v /usr2/zxb/cmtest:/var/lib/opengauss  -e dbport=22100 -e cmport=22200 opengauss-cm:6.0.3

```

## 安装2个单机版本集群，配置主备并部署CM高可用工具

### 1. 部署两个单机
 
选择opengauss-og1作为主机，扩展opengauss-og2为备机

```
docker run --name opengauss-og1 --privileged=true --network=host -d -e GS_PASSWORD=Test@123 -e dbport=5800 -e single=1 -v /usr2/zxb/cmtest:/var/lib/opengauss opengauss-cm:6.0.3

docker run --name opengauss-og2 --privileged=true --network=host -d -e GS_PASSWORD=Test@123 -e dbport=5800 -e single=1 -v /usr2/zxb/cmtest:/var/lib/opengauss opengauss-cm:6.0.3
```

### 2. 配置主机参数
```
primary_name=opengauss-og1
docker exec ${primary_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c \"replconninfo1='localhost=20.20.20.56 localport=5801 localheartbeatport=5804 localservice=5805 remotehost=20.20.20.54 remoteport=5801 remoteheartbeatport=5804 remoteservice=5805'\""
docker exec ${primary_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c 'remote_read_mode=off'"
docker exec ${primary_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c 'replication_type=1'"
docker exec ${primary_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c \"application_name='dn_master'\""
docker exec ${primary_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -h 'host all omm 20.20.20.54/32 trust'"
docker exec ${primary_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -h 'host all omm 20.20.20.56/32 trust'"
```

主机需要把实例角色改为1，后面再重启时候才会选择正确角色：
```
sed -i "s/INSTANCE_TYPE=*.*/INSTANCE_TYPE=1/g" /home/omm/.bashrc
```


### 3. 配置备机参数
```
standby_name=opengauss-og2
docker exec ${standby_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c \"replconninfo1='localhost=20.20.20.54 localport=5801 localheartbeatport=5804 localservice=5805 remotehost=20.20.20.56 remoteport=5801 remoteheartbeatport=5804 remoteservice=5805'\""
docker exec ${standby_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c 'remote_read_mode=off'"
docker exec ${standby_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c 'replication_type=1'"
docker exec ${standby_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -c \"application_name='dn_standby1'\""
docker exec ${standby_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -h 'host all omm 20.20.20.54/32 trust'"
docker exec ${standby_name} su - omm -c "gs_guc reload -D /var/lib/opengauss/data -h 'host all omm 20.20.20.56/32 trust'"
```


### 4. 备机以-M standby方式重启，全量build数据

进入到备机容器里面(omm用户下)，添加维护文件

```
touch /usr/local/opengauss/cluster_maintain_file
```

改环境变量角色为备机：
```
sed -i "s/INSTANCE_TYPE=*.*/INSTANCE_TYPE=2/g" /home/omm/.bashrc
```

停止备机实例，以standby方式启动
```
gs_ctl stop -D /var/lib/opengauss/data
gs_ctl start -D /var/lib/opengauss/data -M standby
gs_ctl build -D /var/lib/opengauss/data -M standby

rm /usr/local/opengauss/cluster_maintain_file
```

### 5. 主备安装cm工具 (omm用户下执行那个), 确保primaryname和standbynames与在容器内的hostname一致。
   
```
export single=0
export GS_PASSWORD=Test@123
export primaryhost="20.20.20.56"
export standbyhosts="20.20.20.54"
export primaryname=openGauss56
export standbynames=openGauss54

sh /deploy_cm.sh
```