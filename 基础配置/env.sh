#!/bin/bash

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root执行"
    exit 1
fi


sudo apt-get install -y expect


function auto_scp {
    local user=$1
    local pass=$2
    local host=$3
    local file=$4

    expect -c "
    log_user 0
    spawn scp $file $user@$host:/home/$user/
    expect {
        \"*yes/no*\" { send \"yes\r\"; exp_continue }
        \"*password:*\" { send \"$pass\r\" }
    }
    expect eof
    " >/dev/null 2>&1
}





# 定义环境变量配置函数
env_variables() {
    choice=
    mkdir -p /var/openstack/
    touch /var/openstack/export
    echo "---------------------------基础环境信息---------------------------"
    read -p "输入登入用户名: " username
    read -sp "输入登入密码: " password
    echo ""

    read -p "控制节点 IP: " controller
    read -p "计算节点 IP(用空格分隔): " -a compute_ip
    read -p "请输入外网网段,格式如[xxx.xxx.xxx.0/24]: " network_segment
    read -p "请输入网桥名称(名称自定义如: br-eth1):" 
    echo "---------------------------基础服务配置信息---------------------------"
    read -sp "请输入mysql 密码: " db_password
    echo ""
    read -sp "请输入rabbitmq 密码: " rabbitmq_password
    echo ""
    echo "---------------------------openstack服务配置信息---------------------------"
    read -sp "请输入keystone 密码: " keystone
    echo ""
    read -sp "请输入glance 密码: " glance
    echo ""
    read -sp "请输入placement密码: " placement
    echo ""
    read -sp "请输入neutron密码: " neutron
    echo "请选择要使用的网络模式[1.Linux Bridge 2.Open vSwitch]"
    read -p "请输入你的选择 [1 或 2]:"  inpute_choice
    if [ "$input_choice" == "1" ]; then
        choice=1
    else
        echo "请选择Open vSwitch 网络模式使用的模式[1.Provider networks  2.Self-service networks]"
        read -p "请输入你的选择 [1 或 2]: " input_open_choice
        if [ "$input_open_choice" == "1" ]; then 
            choice=2
        else
            choice=3
        fi
    fi
    read -sp "请输入nova密码: " nova
    echo ""

    export_file="/var/openstack/export"

    # 检查文件写权限
    if [ ! -w "$export_file" ]; then
        echo "错误：没有权限写入 $export_file 文件。请检查权限"
        exit 1
    fi

    # 检查变量是否为空
    if [ -z "$username" ] || [ -z "$password" ] ||  [ -z "$controller" ] ||  # 修改：添加对密码变量的检查
        [ -z "$network_segment" ]  || [ ${#compute_ip[@]} -eq 0 ]; then
        echo "检查配置输入不能为空"
        exit 1
    fi

    # 写入环境变量到文件
    {
        echo "export username=\"$username\""
        echo "export controller=\"$controller\""
        for ((i = 0; i < ${#compute_ip[@]}; i++)); do
            echo "export compute_ip_$(($i + 1))=\"${compute_ip[i]}\""
        done
        echo "export network_segment=\"$network_segment\""
        echo "export db_password=\"$db_password\""
        echo "export rabbitmq_password=\"$rabbitmq_password\""
        echo "export keystone=\"$keystone\""
        echo "export glance=\"$glance\""
        echo "export placement=\"$placement\""
        echo "export neutron=\"$neutron\""
        echo "export neutron_mode=\"$choice\""
        echo "export nova=\"$nova\""
    } > "$export_file"

    # 写入 /etc/hosts 文件
    {
        echo "$controller controller"


        number=1
        for ((i = 0; i < ${#compute_ip[@]}; i++)); do
            echo "${compute_ip[i]} compute-$number"
            ((number++))
        done
    } >> /etc/hosts

    # 拷贝文件到其他主机
    for ((i = 0; i < ${#compute_ip[@]}; i++)); do
        auto_scp $username $password ${compute_ip[i]} /var/openstack/export
        auto_scp $username $password ${compute_ip[i]} /etc/hosts
    done
}

env_variables
