
### shardingsphere分布式容器镜像使用

#### 镜像构建

1. shardingsphere镜像构建

软件包准备：
    apache-shardingsphere-5.3.1-shardingsphere-proxy-bin.tar.gz
    apache-zookeeper-3.8.0-bin.tar.gz
    bisheng-jre-11.0.12-linux-aarch64.tar.gz (https://mirror.iscas.ac.cn/kunpeng/archive/compiler/bisheng_jdk/bisheng-jre-11.0.12-linux-aarch64.tar.gz)
    bisheng-jre-11.0.12-linux-x64.tar.gz     (https://mirror.iscas.ac.cn/kunpeng/archive/compiler/bisheng_jdk/bisheng-jre-11.0.12-linux-x64.tar.gz)

2. openlookeng

软件包准备：
    hetu-server-1.10.0-SNAPSHOT.tar.gz
    opengauss-jdbc-5.0.1.jar
    bisheng-jre-11.0.12-linux-aarch64.tar.gz
    bisheng-jre-11.0.12-linux-x64.tar.gz


3. 镜像打包

    将需要用的镜像，下载到对应目录下，shardingsphere镜像文件拷贝到sharding目录下，openlookeng依赖软件包文件拷贝到openlookeng目录下，执行构建镜像脚本：

    ```
    sh build_distri_image.sh 
    ```
    打包完成后，可以使用`docker images`名称查询
    ```
    REPOSITORY           TAG                 IMAGE ID            CREATED             SIZE
    opengauss-sharding   5.0.1               a96c3d8d03c2        4 seconds ago       873MB
    opengauss-hetu       5.0.1               c2936499866f        4 minutes ago       4.09GB
    ```

#### 镜像使用


1. 部署数据库集群

使用sharding分片，至少需要部署两套数据库集群。

数据库容器部署参考文档: openGauss-container/README.md


2. 运行shardingsphere镜像

```
docker run --name opengauss-sharding --net og-distri --ip "173.11.0.8" -p 3307:3307 -p 2181:2181 -v /ssconfig:/var/lib/sharding -d opengauss-sharding:5.0.1
```

参数说明：

```
--name： 容器运行名称，任意指定，不重复即可

--net：  容器网络，需要确保数据库、sharding、openlookeng容器都使用相同的容器网络。

--ip：   指定运行的容器ip

-p3307:3307:  宿主机和容器内的sharding服务端口映射。 容器内端口为3307，宿主机可自行指定

-p2181:2181:  宿主机和容器内的zookeeper服务端口映射。容器内端口为2181，宿主机可自行指定

-v /ssconfig:/var/lib/sharding： sharding配置目录映射。/var/lib/sharding为容器内部的配置目录， /ssconfig为宿主机目录，可自行指定

opengauss-sharding:5.0.1： 容器镜像名称
```

容器启动后，在宿主机/ssconfig目录下，配置shardingshpere的server.yaml,config-sharding.yaml文件。

在server.yaml中配置zookeeper连接信息以及连接用户。

预先在数据库集群创建远程连接用户、数据库，并配置到config-sharding.yaml里面。

重启shardingshpere容器，即可生效。

3. 运行openlookeng容器(hetu-server)

openlookeng容器运行需要依赖sharding和zookeeper相关配置。

```
database_name=sharding_db  # 对应config-sharding.yaml中databaseName
namespace=governance_ds    # 对应server.yaml中ZK的namespace
server_lists=173.11.0.8:2181  # zookeeper的连接配置

docker run --name opengauss-hetu --net og-distri --ip "173.11.0.9"  -e database_name="$database_name" -e namespace="$namespace" -e server_lists="$server_lists" -d opengauss-hetu:5.0.1
```

参数说明：
```
--name： 容器运行名称，任意指定，不重复即可

--net：  容器网络，需要确保数据库、sharding、openlookeng容器都使用相同的容器网络。

--ip：   指定运行的容器ip

-e database_name:  对应config-sharding.yaml中databaseName

-e namespace:      对应server.yaml中ZK的namespace

-e server_lists:  zookeeper的连接配置

opengauss-hetu:5.0.1： 容器镜像名称
```