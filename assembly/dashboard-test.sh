#!/bin/bash

source /var/openstack/export
source /etc/keystone/admin-openrc.sh


horizon(){
    apt install -y  openstack-dashboard
    cp /etc/openstack-dashboard/local_settings.py  /etc/openstack-dashboard/local_settings.py.source
    sed -i 's/^OPENSTACK_HOST = ".*"/OPENSTACK_HOST = "controller"/' /etc/openstack-dashboard/local_settings.py
    sed -i 's|^OPENSTACK_KEYSTONE_URL = "http://%s/identity/v3" % OPENSTACK_HOST|OPENSTACK_KEYSTONE_URL = "http://%s:5000/identity/v3" % OPENSTACK_HOST|' /etc/openstack-dashboard/local_settings.py
    echo  "OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True"  >> /etc/openstack-dashboard/local_settings.py
    cat <<EOL >> /etc/openstack-dashboard/local_settings.py
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 3,
}
EOL
    # 将 Default 配置为您通过仪表板创建的用户的默认域：
    #echo "OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "Default"" >>   /etc/openstack-dashboard/local_settings.py
    # 将 user 配置为您通过仪表板创建的用户的默认角色
    #echo "OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"" >>   /etc/openstack-dashboard/local_settings.py
    zone=$(timedatectl status  | grep  zone  | awk   '{print $3}')
    sed -i "s|TIME_ZONE = \"UTC\"|TIME_ZONE = \"$zone\"|g" /etc/openstack-dashboard/local_settings.py
    sed -i "s|'127.0.0.1:11211'|'controller:11211'|g" /etc/openstack-dashboard/local_settings.py


    if  [ "$neutron_mode" == 2  ]; then 
        cat <<EOL >> /etc/openstack-dashboard/local_settings.py
OPENSTACK_NEUTRON_NETWORK = {
    'enable_router': False,
    'enable_quotas': False,
    'enable_ipv6': False,
    'enable_distributed_router': False,
    'enable_ha_router': False,
    'enable_fip_topology_check': False,
}
EOL
    else
        cat <<EOL >> /etc/openstack-dashboard/local_settings.py
OPENSTACK_NEUTRON_NETWORK = {
    'enable_router': True,
    'enable_quotas': True,
    'enable_rbac_policy': True,
    'enable_distributed_router': False,
    'enable_ha_router': False,
    'enable_ipv6': False,
    'enable_lb': False,
    'enable_firewall': False,
    'enable_vpn': False,
    'enable_fip_topology_check': True,
    'default_dns_nameservers': [],
    'supported_provider_types': ['*'],
    'segmentation_id_range': {},
    'extra_provider_types': {},
    'supported_vnic_types': ['*'],
}
EOL


    fi 


    systemctl reload apache2.service
    echo  "服务http://controller/horizon"


}

skyline() {
    mysql -uroot -p$db_password -e "CREATE DATABASE IF NOT EXISTS skyline DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci";
    mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON skyline.* TO 'skyline'@'localhost' IDENTIFIED BY '$skyline';"
    mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON skyline.* TO 'skyline'@'%' IDENTIFIED BY '$skyline';"
    openstack user create --domain default --password $skyline skyline
    openstack role add --project service --user skyline admin

    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
    sudo curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
    apt-get install -y docker.io

    mkdir -vp /etc/docker/
    sudo tee /etc/docker/daemon.json <-'EOF'
{
    "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://reg-mirror.qiniu.com",
    "https://registry.docker-cn.com"
    ],
    "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF

    sudo systemctl daemon-reload
    sudo systemctl start docker
    sudo systemctl enable docker

    docker pull registry.cn-beijing.aliyuncs.com/wdtn/skyline
    mkdir -p /etc/skyline /var/log/skyline /var/lib/skyline /var/log/nginx /etc/skyline/policy
    wget -O  /etc/skyline/skyline.yaml https://github.com/asws666dsx/image/releases/download/v1/skyline.yaml 
    sed -i 's/\r//' /etc/skyline/skyline.yaml


    CONFIG_FILE="/etc/skyline/skyline.yaml"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "文件 $CONFIG_FILE 不存在."
        exit 1
    fi

    sed -i -e "/^default:/,/^openstack:/ s|^\(  database_url: \).*|\1mysql://skyline:$skyline@$controller:3306/skyline|" \
           -e "/^default:/,/^openstack:/ s|^\(  debug: \).*|\1true|" \
           -e "/^default:/,/^openstack:/ s|^\(  log_dir: \).*|\1/var/log/skyline|" \
           "$CONFIG_FILE"

    sed -i -e "/^openstack:/,/^setting:/ s|^\(  keystone_url: \).*|\1http://$controller:5000/v3/|" \
           -e "/^openstack:/,/^setting:/ s|^\(  system_user_password: \).*|\1$skyline|" \
           "$CONFIG_FILE"

    docker run -d --name skyline_bootstrap -e KOLLA_BOOTSTRAP="" -v /etc/skyline/skyline.yaml:/etc/skyline/skyline.yaml -v /var/log:/var/log --net=host registry.cn-beijing.aliyuncs.com/wdtn/skyline

    sleep 8

    docker logs skyline_bootstrap
    docker rm -f skyline_bootstrap
    docker run -d --name skyline --restart=always -v /etc/skyline/skyline.yaml:/etc/skyline/skyline.yaml -v /var/log:/var/log --net=host registry.cn-beijing.aliyuncs.com/wdtn/skyline

    UP=$(docker ps -a | awk '$NF=="skyline" {print $7}')
    if [ "$UP" == "Up" ]; then 
        echo "http://$controller:9999"
    else
        echo "部署失败"
    fi
}

if [ "$dashboard_choice" == "1" ]; then 
    horizon
else 
    skyline
fi
