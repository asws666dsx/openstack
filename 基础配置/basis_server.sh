#!/bin/bash
source /var/openstack/export



setup_mariadb() {
    if [ "$(id -u)" != 0 ]; then
        echo "请使用 root 权限执行此脚本"
        exit 1
    fi

    #sudo apt-get install -y  mariadb-server=1:10.11.7-2ubuntu2 python3-pymysql   ## 24.02
    #sudo apt-get install -y  mariadb-server=1:10.6.16-0ubuntu0.22.04.1 python3-pymysql 
    sudo apt-get install -y  mariadb-server python3-pymysql 
    cp /etc/mysql/my.cnf /etc/mysql/my.cnf.bak

    cat <<EOF >>/etc/mysql/my.cnf
[mysqld]
bind-address = 0.0.0.0
default-storage-engine = innodb
innodb_file_per_table = on 
max_connections = 8192 
collation-server = utf8_general_ci 
character-set-server = utf8
EOF

    awk '/\[Service\]/{if(!found){print;print "LimitNPROC=65535";found=1;next}}1' /usr/lib/systemd/system/mariadb.service >/tmp/mariadb.service && mv /tmp/mariadb.service /usr/lib/systemd/system/mariadb.service

    crudini --set /usr/lib/systemd/system/mariadb.service Service LimitNOFILE 65535

    systemctl daemon-reload
    systemctl enable mariadb.service
    systemctl restart mariadb.service

    /usr/bin/expect <<EOF >/dev/null
log_user 0
spawn /usr/bin/mysql_secure_installation

expect "Enter current password for root (enter for none):"
send "\r"

expect "Switch to unix_socket authentication \[Y/n\] "
send "y\r"

expect "Change the root password? \[Y/n\] "
send "y\r"

expect "New password:"
send "$db_password\r"

expect "Re-enter new password:"
send "$db_password\r"

expect "Remove anonymous users? \[Y/n\] "
send "y\r"

expect "Disallow root login remotely? \[Y/n\] "
send "n\r"

expect "Remove test database and access to it? \[Y/n\] "
send "y\r"

expect "Reload privilege tables now? \[Y/n\] "
send "y\r"

expect eof
EOF

    mysql -uroot -p$db_password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$db_password';"
}

setup_memcache() {
    apt install -y  memcached python3-memcache
    sed -i 's/-m 64/-m 245/' /etc/memcached.conf
    sed -i 's/-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf
    sed -i 's/# -u memcache/-u memcache/' /etc/memcached.conf
    sed -i 's/# -c 1024/-c 4096/' /etc/memcached.conf

    systemctl enable memcached.service
    systemctl restart memcached.service
    systemctl status memcached.service

    ss -ntpl | grep 11211
}

setup_rabbitmq() {
    apt -y install rabbitmq-server
    systemctl daemon-reload
    systemctl enable rabbitmq-server.service
    systemctl restart rabbitmq-server.service
    rabbitmqctl add_user openstack $rabbitmq_password
    rabbitmqctl set_user_tags openstack administrator
    rabbitmqctl set_permissions openstack ".*" ".*" ".*"
    read -p "是否要开启rabbitmq的控制台[y/n]:" y
    y=$(echo "$y" | tr '[:upper:]' '[:lower:]')
    if [ "$y" == "y" ]; then
        rabbitmq-plugins enable rabbitmq_management
    fi
    ss -ntpl | grep 5672
}


while true; do
    read -p "请选择要安装的服务[1.mysql,2.memcache,3.rabbitmq]:" number

    case $number in
        1)
            setup_mariadb
            ;;
        2)
            setup_memcache
            ;;
        3)
            setup_rabbitmq
            ;;
        *)
            echo "无效的选项,请输入1、2或3"
            ;;
    esac

    read -p "是否要退出脚本? [y/n]:" exit_choice
    exit_choice=$(echo "$exit_choice" | tr '[:upper:]' '[:lower:]')
    if [ "$exit_choice" == "y" ]; then
        echo "退出脚本"
        exit 0
    fi
done