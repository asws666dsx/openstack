#!/bin/bash

if [ "$(id -u)" != 0 ]; then
    echo "请使用root执行"
    exit 1
fi

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
timedatectl

apt -y install chrony

read -p "当前为controller[Y/N]:" node
read -p "输入用户名:" username


# 统一为小写
node=$(echo "$node" | tr '[:upper:]' '[:lower:]') # upper 为大写字母（A-Z） lower 为小写字母

if [[ $node != 'y' && $node != 'yes' ]]; then # 修改条件语句
    read -p "当前节点位第几个compute:" number
    hostnamectl set-hostname compute-$number
    sed -i "s/127.0.1.1 controller/127.0.1.1 compute-$number/g" /home/$username/hosts
    cp /home/$username/hosts /etc/hosts
    mkdir -p /var/openstack/
    touch /var/openstack/export
    cp /home/$username/export /var/openstack/export
    sed -i "s/ntp.ubuntu.com/controller/g" /etc/chrony/chrony.conf
    sed -i "/^pool 0.\ubuntu\.pool\.ntp\.org /s/^/#/" /etc/chrony/chrony.conf
    sed -i "/^pool 1.\ubuntu\.pool\.ntp\.org /s/^/#/" /etc/chrony/chrony.conf
    sed -i "/^pool 2\.ubuntu\.pool\.ntp\.org /s/^/#/" /etc/chrony/chrony.conf
else
    hostnamectl set-hostname controller
    source /var/openstack/export
    sed -i "s/0.ubuntu.pool.ntp.org/ntp.aliyun.com/g" /etc/chrony/chrony.conf
    sed -i "s/1.ubuntu.pool.ntp.org/ntp1.aliyun.com/g" /etc/chrony/chrony.conf
    sed -i "/^pool 2\.ubuntu\.pool\.ntp\.org /s/^/#/" /etc/chrony/chrony.conf
    cat >>/etc/chrony/chrony.conf <<EOF
allow $network_segment
EOF
    apt install -y python3-pip
    pip install --upgrade eventlet
fi

configuration() {

    cat >/etc/sysctl.conf <<EOF
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 32768
fs.file-max = 200000
EOF
    cat >/etc/security/limits.conf <<EOF
* hard nofile 655360
* soft nofile 655360
* hard nproc unlimited
* soft nproc unlimited
* soft core 655360
* hard core 655360
root soft nproc unlimited
EOF

    sysctl -p

    nested=$(cat /sys/module/kvm_intel/parameters/nested)
    if [ "$nested" != Y ]; then
        cat >>/etc/modprobe.d/kvm-nested.conf <<EOF
options kvm_intel nested=1 ept=0 unrestricted_guest=0
EOF
        rmmod kvm_intel
        modprobe kvm_intel nested=1 ept=0 unrestricted_guest=0
        nested=$(cat /sys/module/kvm_intel/parameters/nested)
        echo "$nested"
        if [ "$nested" != Y ]; then
            echo "错误: CPU 嵌套虚拟化配置失败。"
            exit 1
        else
            echo "$nested"
        fi
    else
        echo "$nested"
    fi

    add-apt-repository cloud-archive:bobcat  #caracal  2024.1  #bobcat 2023.1
    apt -y install python3-openstackclient
    cat >/etc/apt/sources.list.d/qh.list <<EOF
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse

deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
# deb-src http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse

# 预发布软件源，不建议启用
# deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-proposed main restricted universe multiverse
# # deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-proposed main restricted universe multiverse
EOF
    apt-get update
    systemctl daemon-reload
    systemctl enable chrony.service
    systemctl restart chrony.service
    systemctl restart chronyd.service
    sleep 10
    chronyc sources
    sudo apt-get install -y crudini
}

configuration
