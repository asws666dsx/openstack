本脚本适用于ubuntu 22.04 与 24.04版本 server 版

环境使用两张网络，一张内部使用，一张外部网卡，外部网卡不用配置

1.网络配置

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

使用方法

```
wget   
```

3.解压

```
mkdir /usr/local/bin/osi/
tar install.tar.gz    -C /usr/local/bin/osi/
```

4.运行env  根据提示配置

```
env.sh
```

!!!!注意在使用22.04 版本安装 keystone 进行数据同步时会报错，可以忽略这个报错

```
AttributeError: 'NoneType' object has no attribute 'getcurrent'
```