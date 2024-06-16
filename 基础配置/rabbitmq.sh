#!/bin/bash

source /var/openstack/export

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

setup_rabbitmq
