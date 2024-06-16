#!/bin/bash

source /var/openstack/export
source /etc/keystone/admin-openrc.sh





read -p "当前为controller[Y/N]:" node
node=$(echo "$node" | tr '[:upper:]' '[:lower:]')


nova_controller() {
    mysql -uroot -p$db_password -e "CREATE DATABASE IF NOT EXISTS nova_api;"
    mysql -uroot -p$db_password -e "CREATE DATABASE IF NOT EXISTS nova;"
    mysql -uroot -p$db_password -e "CREATE DATABASE IF NOT EXISTS nova_cell0;"
    mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$nova';"
    mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$nova';"
    mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$nova';"
    mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$nova';"
    mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$nova';"
    mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$nova';"

    openstack user create --domain default --password $nova nova
    openstack role add --project service --user nova admin
    openstack service create --name nova --description "OpenStack Compute" compute
    openstack endpoint create --region RegionOne compute public http://controller:8774/v2.1
    openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1
    openstack endpoint create --region RegionOne compute admin http://controller:8774/v2.1

    apt install -y nova-api nova-conductor nova-novncproxy nova-scheduler

    crudini --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
    crudini --set /etc/nova/nova.conf DEFAULT transport_url rabbit://openstack:$rabbitmq_password@controller
    crudini --set /etc/nova/nova.conf DEFAULT my_ip $controller
    crudini --set /etc/nova/nova.conf DEFAULT use_neutron true
    crudini --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
    crudini --set /etc/nova/nova.conf DEFAULT allow_resize_to_same_host true
    crudini --set /etc/nova/nova.conf DEFAULT metadata_proxy_shared_secret openstack

    crudini --set /etc/nova/nova.conf api_database connection mysql+pymysql://nova:$nova@controller/nova_api

    crudini --set /etc/nova/nova.conf database connection mysql+pymysql://nova:$nova@controller/nova

    crudini --set /etc/nova/nova.conf api auth_strategy keystone
    crudini --set /etc/nova/nova.conf api token_cache_time 3600

    crudini --set /etc/nova/nova.conf keystone_authtoken auth_url http://controller:5000/v3
    crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers controller:11211
    crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
    crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name Default
    crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name Default
    crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
    crudini --set /etc/nova/nova.conf keystone_authtoken username nova
    crudini --set /etc/nova/nova.conf keystone_authtoken password $nova
    crudini --set /etc/nova/nova.conf keystone_authtoken token_cache_time 3600

    crudini --set /etc/nova/nova.conf neutron url http://controller:9696
    crudini --set /etc/nova/nova.conf neutron auth_url http://controller:5000
    crudini --set /etc/nova/nova.conf neutron auth_type password
    crudini --set /etc/nova/nova.conf neutron project_domain_name Default
    crudini --set /etc/nova/nova.conf neutron user_domain_name Default
    crudini --set /etc/nova/nova.conf neutron region_name RegionOne
    crudini --set /etc/nova/nova.conf neutron project_name service
    crudini --set /etc/nova/nova.conf neutron username neutron
    crudini --set /etc/nova/nova.conf neutron password $neutron
    crudini --set /etc/nova/nova.conf neutron service_metadata_proxy true
    crudini --set /etc/nova/nova.conf neutron metadata_proxy_shared_secret openstack

    crudini --set /etc/nova/nova.conf vnc enabled true
    crudini --set /etc/nova/nova.conf vnc server_listen '$my_ip'
    crudini --set /etc/nova/nova.conf vnc server_proxyclient_address '$my_ip'


    crudini --set /etc/nova/nova.conf glance api_servers http://controller:9292

    crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp

    crudini --set /etc/nova/nova.conf placement region_name RegionOne
    crudini --set /etc/nova/nova.conf placement project_domain_name Default
    crudini --set /etc/nova/nova.conf placement project_name service
    crudini --set /etc/nova/nova.conf placement auth_type password
    crudini --set /etc/nova/nova.conf placement user_domain_name Default
    crudini --set /etc/nova/nova.conf placement auth_url http://controller:5000/v3
    crudini --set /etc/nova/nova.conf placement username placement
    crudini --set /etc/nova/nova.conf placement password $placement

    crudini --set /etc/nova/nova.conf scheduler discover_hosts_in_cells_interval 180

    crudini --set /etc/nova/nova.conf service_user send_service_user_token true
    crudini --set /etc/nova/nova.conf service_user auth_url http://controller:5000/identity
    crudini --set /etc/nova/nova.conf service_user auth_strategy keystone
    crudini --set /etc/nova/nova.conf service_user auth_type password
    crudini --set /etc/nova/nova.conf service_user project_domain_name Default
    crudini --set /etc/nova/nova.conf service_user project_name service
    crudini --set /etc/nova/nova.conf service_user user_domain_name Default
    crudini --set /etc/nova/nova.conf service_user username nova
    crudini --set /etc/nova/nova.conf service_user password $nova

    su -s /bin/sh -c "nova-manage api_db sync" nova
    su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
    su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
    su -s /bin/sh -c "nova-manage db sync" nova
    service nova-api restart
    service nova-scheduler restart
    service nova-conductor restart
    service nova-novncproxy restart
    systemctl enable nova-api nova-scheduler nova-conductor nova-novncproxy
    systemctl status nova-api nova-scheduler nova-conductor nova-novncproxy

}

nova_compute() {
    apt install -y  nova-compute
    cp /etc/nova/nova.conf /etc/nova/nova.conf.source

    read -p "这是第几个compute: " number
    in_node="compute_$number"
    in_node_ip=${!in_node}
    
    crudini --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
    crudini --set /etc/nova/nova.conf DEFAULT transport_url rabbit://openstack:$rabbitmq_password@controller
    crudini --set /etc/nova/nova.conf DEFAULT my_ip $in_node_ip
    crudini --set /etc/nova/nova.conf DEFAULT use_neutron true
    crudini --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver

    crudini --set /etc/nova/nova.conf api auth_strategy keystone

    crudini --set /etc/nova/nova.conf keystone_authtoken auth_url http://controller:5000/v3
    crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers controller:11211
    crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
    crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name Default
    crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name Default
    crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
    crudini --set /etc/nova/nova.conf keystone_authtoken username nova
    crudini --set /etc/nova/nova.conf keystone_authtoken password $nova
    crudini --set /etc/nova/nova.conf keystone_authtoken token_cache_time 3600

    crudini --set /etc/nova/nova.conf neutron url http://controller:9696
    crudini --set /etc/nova/nova.conf neutron auth_url http://controller:5000/v3
    crudini --set /etc/nova/nova.conf neutron auth_type password
    crudini --set /etc/nova/nova.conf neutron project_domain_name Default
    crudini --set /etc/nova/nova.conf neutron user_domain_name Default
    crudini --set /etc/nova/nova.conf neutron region_name RegionOne
    crudini --set /etc/nova/nova.conf neutron project_name service
    crudini --set /etc/nova/nova.conf neutron username neutron
    crudini --set /etc/nova/nova.conf neutron password $neutron

    crudini --set /etc/nova/nova.conf vnc enabled true
    crudini --set /etc/nova/nova.conf vnc server_listen 0.0.0.0
    crudini --set /etc/nova/nova.conf vnc server_proxyclient_address '$my_ip'
    crudini --set /etc/nova/nova.conf vnc novncproxy_base_url http://controller:6080/vnc_auto.html
    # crudini --set /etc/nova/nova.conf vnc vncserver_proxyclient_address $my_ip

    crudini --set /etc/nova/nova.conf glance api_servers http://controller:9292

    crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp

    crudini --set /etc/nova/nova.conf placement region_name RegionOne
    crudini --set /etc/nova/nova.conf placement project_domain_name Default
    crudini --set /etc/nova/nova.conf placement project_name service
    crudini --set /etc/nova/nova.conf placement auth_type password
    crudini --set /etc/nova/nova.conf placement user_domain_name Default
    crudini --set /etc/nova/nova.conf placement auth_url http://controller:5000/v3
    crudini --set /etc/nova/nova.conf placement username placement
    crudini --set /etc/nova/nova.conf placement password $placement

    crudini --set /etc/nova/nova.conf scheduler discover_hosts_in_cells_interval 180

    crudini --set /etc/nova/nova.conf libvirt virt_type qemu
    crudini --set /etc/nova/nova.conf libvirt num_pcie_ports 10

    crudini --set /etc/nova/nova.conf service_user send_service_user_token true
    crudini --set /etc/nova/nova.conf service_user auth_url http://controller:5000/identity
    crudini --set /etc/nova/nova.conf service_user auth_strategy keystone
    crudini --set /etc/nova/nova.conf service_user auth_type password
    crudini --set /etc/nova/nova.conf service_user project_domain_name Default
    crudini --set /etc/nova/nova.conf service_user project_name service
    crudini --set /etc/nova/nova.conf service_user user_domain_name Default
    crudini --set /etc/nova/nova.conf service_user username nova
    crudini --set /etc/nova/nova.conf service_user password $nova
    service nova-compute restart
    echo  "请在controller中执行: openstack compute service list --service nova-compute"
    echo "请在controller中执行: su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova "


}


if [ "$node" == 'y' ]; then
    nova_controller
else 
    nova_compute
fi