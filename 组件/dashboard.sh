#!/bin/bash



read -p "选择要安装的dashboard[1.horizon,2.skyline]": number


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
    GRANT ALL PRIVILEGES ON skyline.* TO 'skyline'@'localhost' IDENTIFIED BY 'skylineredhat';
    GRANT ALL PRIVILEGES ON skyline.* TO 'skyline'@'%' IDENTIFIED BY 'skylineredhat';
    openstack user create --domain default --password  skyline skyline
    openstack role add --project service --user skyline admin
    sudo apt-get install -y  apt-transport-https  ca-certificates curl gnupg-agent  software-properties-common

    sudo curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
    apt-get install -y docker.io

    mkdir -vp /etc/docker/
sudo tee /etc/docker/daemon.json <<-'EOF'
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
}
docker pull registry.cn-beijing.aliyuncs.com/wdtn/skyline
mkdir -p /etc/skyline /var/log/skyline /var/lib/skyline /var/log/nginx /etc/skyline/policy

if [ "$number" == "1" ]; then 

    horizon
else 
    :
fi 