本脚本适用于ubuntu 22.04 与 24.04版本 server 版

环境使用两张网络，一张内部使用，一张外部网卡，外部网卡可选配置

1.网络配置（所以节点操作）

示例如：

```
network:
  ethernets:
    ens33:   # 配置内部网卡
      addresses: ["172.16.100.51/24"]
      dhcp4: false
      optional: true
      routes:
        - to: 0.0.0.0/0
          via: 172.16.100.254
          metric: 100
      nameservers:
        addresses: [114.114.114.114]
  version: 2
```

2.获取脚本（所以节点操作）

```
git clone  https://github.com/asws666dsx/openstack.git
```

所以节点操作

3.拷贝到对应目录下

```
mkdir /usr/local/bin/osi/
scp  openstack/Basic_Configuration/* /usr/local/bin/osi/
scp  openstack/assembly/*  /usr/local/bin/osi/
```

4.运行env  根据提示配置 

```
env.sh
```

5.compute 与controller 运行 基础配置

```
basoc_configuration.sh
```

6.controller 安装mysql,rabbitmq,memcache

```
basis_server.sh
```

7.controller 安装 keystone,glance,placement

```
keystone.sh
```

```
glance.sh
```

```
placement.sh
```

!!!!注意在使用22.04 版本安装 keystone 进行数据同步时会报错，可以忽略这个报错

```
AttributeError: 'NoneType' object has no attribute 'getcurrent'
```

8.controller 安装 nova 

```
nova.sh
```

9.compute 安装nova

```
nova.sh
```

10.controller 安装 neutron 

```
neutron.sh
```

11.compute 安装neutron 

```
neutron.sh
```

12.安装dashboard

```
dashboard.sh
```

其他组件以此类推
