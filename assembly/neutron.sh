#!/bin/bash

source /var/openstack/export

br_eth="br-ex"




# 检查 net.bridge.bridge-nf-call- 配置是否存在
test=$(sysctl -p | grep net.bridge.bridge-nf-call-)

if [ -z "$test" ]; then
    # 如果 net.bridge.bridge-nf-call- 配置不存在，追加到 /etc/sysctl.conf
    if ! grep -q "net.bridge.bridge-nf-call-iptables = 1" /etc/sysctl.conf; then
        echo "net.bridge.bridge-nf-call-iptables = 1" >>/etc/sysctl.conf
    fi

    if ! grep -q "net.bridge.bridge-nf-call-ip6tables = 1" /etc/sysctl.conf; then
        echo "net.bridge.bridge-nf-call-ip6tables = 1" >>/etc/sysctl.conf
    fi

    # 加载 br_netfilter 模块并应用新的 sysctl 配置
    modprobe br_netfilter && sysctl -p
fi


eth=

read -p "当前为controller[Y/N]:" node
node=$(echo "$node" | tr '[:upper:]' '[:lower:]')


linuxbridge_install() {
    
    apt install -y neutron-server neutron-plugin-ml2 neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent
    cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.source
    cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.source
    cp /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.source
    cp /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.source
    cp /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.source
    cp /etc/neutron/plugins/ml2/linuxbridge_agent.ini /etc/neutron/plugins/ml2/linuxbridge_agent.ini.source
    # neutron
    crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
    crudini --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://openstack:$rabbitmq_password@controller
    crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
    crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes true
    crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes true
    crudini --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips true
    crudini --set /etc/neutron/neutron.conf agent root_helper "sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf"
    crudini --set /etc/neutron/neutron.conf database connection mysql+pymysql://neutron:$neutron@controller/neutron
    crudini --set /etc/neutron/neutron.conf keystone_authtoken www_authenticate_uri http://controller:5000
    crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://controller:5000
    crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers controller:11211
    crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
    crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name Default
    crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name Default
    crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
    crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
    crudini --set /etc/neutron/neutron.conf keystone_authtoken password $neutron
    crudini --set /etc/neutron/neutron.conf keystone_authtoken token_cache_time 3600
    crudini --set /etc/neutron/neutron.conf nova region_name RegionOne
    crudini --set /etc/neutron/neutron.conf nova project_domain_name Default
    crudini --set /etc/neutron/neutron.conf nova project_name service
    crudini --set /etc/neutron/neutron.conf nova auth_type password
    crudini --set /etc/neutron/neutron.conf nova user_domain_name Default
    crudini --set /etc/neutron/neutron.conf nova auth_url http://controller:5000
    crudini --set /etc/neutron/neutron.conf nova username nova
    crudini --set /etc/neutron/neutron.conf nova password $nova
    crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp
    crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins router
    crudini --set /etc/neutron/neutron.conf experimental linuxbridge  true

    # 配置 [ml2] 部分
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers flat,vlan,vxlan
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types vxlan
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers linuxbridge,l2population
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks provider
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan network_vlan_ranges provider
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan vni_ranges 1:1000
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset true

    #配置 [linux_bridge] 部分
    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini linux_bridge physical_interface_mappings provider:$eth
    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan true
    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan local_ip $controller
    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan l2_population true
    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup enable_security_group true
    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

    # 配置 l3_agent.ini
    crudini --set /etc/neutron/l3_agent.ini DEFAULT interface_driver linuxbridge
    crudini --set /etc/neutron/l3_agent.ini DEFAULT verbose true
    crudini --set /etc/neutron/l3_agent.ini DEFAULT external_network_bridge ""

    #metadata_agent.ini
    crudini --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_host controller
    crudini --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret openstack

    # dhcp_agent.ini
    crudini --set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver linuxbridge
    crudini --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
    crudini --set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata true

    ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
    su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
    service neutron-server restart
    service neutron-dhcp-agent restart
    service neutron-metadata-agent restart
    service neutron-l3-agent restart
    service neutron-linuxbridge-agent restart
    systemctl enable neutron-server neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent neutron-linuxbridge-agent
    sleep 4
    openstack network agent list
}

linuxbridge_compute() {
    apt install -y neutron-linuxbridge-agent  ebtables ipset

    read -p "这是第几个compute: " number
    in_node="compute_ip_$number"
    in_node_ip=${!in_node}
    ip a
    read -p "请输入当前节点provider 网卡名:" eth

    cp /etc/neutron/plugins/ml2/linuxbridge_agent.ini /etc/neutron/plugins/ml2/linuxbridge_agent.ini.source
    cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.source
    # neutron.conf
    crudini --set /etc/neutron/neutron.conf DEFAULT transport_url "rabbit://openstack:$rabbitmq_password@controller"
    crudini --set /etc/neutron/neutron.conf agent root_helper "sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf"
    crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp
    crudini --set /etc/neutron/neutron.conf nova region_name RegionOne
    crudini --set /etc/neutron/neutron.conf nova project_domain_name Default
    crudini --set /etc/neutron/neutron.conf nova project_name service
    crudini --set /etc/neutron/neutron.conf nova auth_type password
    crudini --set /etc/neutron/neutron.conf nova user_domain_name Default
    crudini --set /etc/neutron/neutron.conf nova auth_url http://controller:5000
    crudini --set /etc/neutron/neutron.conf nova username nova
    crudini --set /etc/neutron/neutron.conf nova password $nova

    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini linux_bridge physical_interface_mappings provider:$eth

    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan true
    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan local_ip $in_node_ip
    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan l2_population true

    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup enable_security_group true
    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

    systemctl enable neutron-linuxbridge-agent
    systemctl restart neutron-linuxbridge-agent
}

open_vSwitch() {




    apt install -y neutron-server neutron-plugin-ml2 neutron-openvswitch-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent


    cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.source
    cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.source
    cp /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.source
    cp /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.source
    cp /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.source

    ovs-vsctl add-br "$br_eth"

    # neutron.conf
    crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2

    crudini --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://openstack:$rabbitmq_password@controller
    crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
    crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes true
    crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes true
    crudini --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips true

    crudini --set /etc/neutron/neutron.conf agent root_helper "sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf"

    crudini --set /etc/neutron/neutron.conf database connection mysql+pymysql://neutron:$neutron@controller/neutron

    crudini --set /etc/neutron/neutron.conf keystone_authtoken www_authenticate_uri http://controller:5000
    crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://controller:5000
    crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers controller:11211
    crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
    crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name Default
    crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name Default
    crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
    crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
    crudini --set /etc/neutron/neutron.conf keystone_authtoken password $neutron
    crudini --set /etc/neutron/neutron.conf keystone_authtoken token_cache_time 3600

    crudini --set /etc/neutron/neutron.conf nova region_name RegionOne
    crudini --set /etc/neutron/neutron.conf nova project_domain_name Default
    crudini --set /etc/neutron/neutron.conf nova project_name service
    crudini --set /etc/neutron/neutron.conf nova auth_type password
    crudini --set /etc/neutron/neutron.conf nova user_domain_name Default
    crudini --set /etc/neutron/neutron.conf nova auth_url http://controller:5000
    crudini --set /etc/neutron/neutron.conf nova username nova
    crudini --set /etc/neutron/neutron.conf nova password $nova

    crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp

    #ml2_conf.ini
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks provider
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan vni_ranges 1:1000


    #neutron.conf
    crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins router
    #ml2_conf.ini
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers flat,vlan,vxlan
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types vxlan
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch,l2population

    #openvswitch_agent.ini
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent tunnel_types vxlan
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent l2_population true
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings provider:"$br_eth"
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip $controller
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs tunnel_bridge br-tun
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs integration_bridge br-int
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs tenant_network_type vxlan
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs tunnel_type vxlan
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs tunnel_id_ranges 1:1000
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs enable_tunneling true
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs prevent_arp_spoofing true

    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup enable_security_group true
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup firewall_driver openvswitch

    # l3_agent.ini
    cp /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.source
    crudini --set /etc/neutron/l3_agent.ini DEFAULT interface_driver openvswitch


    #metadata_agent.ini
    crudini --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_host controller
    crudini --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret openstack

    # dhcp_agent.ini
    crudini --set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver openvswitch
    crudini --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
    crudini --set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata true

    ovs-vsctl add-port "$br_eth" "$eth"
    netplan apply
    ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
    su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

    service neutron-server restart
    service neutron-openvswitch-agent restart
    service neutron-dhcp-agent restart
    service neutron-metadata-agent restart

    service neutron-l3-agent restart
    systemctl enable neutron-server neutron-openvswitch-agent neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent

    sleep 4
    openstack network agent list
}

neutron_controller() {
    source /etc/keystone/admin-openrc.sh
    mysql -uroot -p"$db_password" -e "CREATE DATABASE IF NOT EXISTS neutron;"
    mysql -uroot -p"$db_password" -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$neutron';"
    mysql -uroot -p"$db_password" -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$neutron';"
    openstack user create --domain default --password "$neutron" neutron
    openstack role add --project service --user neutron admin
    openstack service create --name neutron --description "OpenStack Networking" network
    openstack endpoint create --region RegionOne network public http://controller:9696
    openstack endpoint create --region RegionOne network internal http://controller:9696
    openstack endpoint create --region RegionOne network admin http://controller:9696

    ip a
    read -p "请输入当前节点provider 网卡名:" eth

    if [ "$neutron_mode" == 1 ]; then
        linuxbridge_install
    else
        open_vSwitch 
    fi
}

open_vSwitch_compute() {


    apt -y install neutron-openvswitch-agent

    read -p "这是第几个compute: " number
    read -p "是否开启flat:[y/n]": Whether
    Whether=$(echo "$Whether" | tr '[:upper:]' '[:lower:]')
    if [ "$Whether" == 'y' ]; then 
        ip a
        read -p "请输入当前节点provider 网卡名:" eth
            crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings provider:"$br_eth"
    fi

    
    in_node="compute_ip_$number"
    in_node_ip=${!in_node}

    cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.source
    cp /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.source

    # neutron.conf
    crudini --set /etc/neutron/neutron.conf DEFAULT transport_url "rabbit://openstack:$rabbitmq_password@controller"
    crudini --set /etc/neutron/neutron.conf agent root_helper "sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf"
    crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp
    crudini --set /etc/neutron/neutron.conf nova region_name RegionOne
    crudini --set /etc/neutron/neutron.conf nova project_domain_name Default
    crudini --set /etc/neutron/neutron.conf nova project_name service
    crudini --set /etc/neutron/neutron.conf nova auth_type password
    crudini --set /etc/neutron/neutron.conf nova user_domain_name Default
    crudini --set /etc/neutron/neutron.conf nova auth_url http://controller:5000
    crudini --set /etc/neutron/neutron.conf nova username nova
    crudini --set /etc/neutron/neutron.conf nova password $nova

    # openvswitch_agent.ini

    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent tunnel_types vxlan
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent l2_population true

    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip $in_node_ip
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs tunnel_bridge br-tun
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs integration_bridge br-int
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs tenant_network_type vxlan
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs enable_tunneling true
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs tunnel_id_ranges 1:1000
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs tunnel_type vxlan
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup enable_security_group true
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup firewall_driver openvswitch


    service neutron-openvswitch-agent restart
    systemctl enable neutron-openvswitch-agent
    systemctl status neutron-openvswitch-agent
}

if [ "$node" == 'y' ]; then
    neutron_controller
else
    if [ "$neutron_mode" == 1 ]; then
        linuxbridge_compute
    else
        open_vSwitch_compute 
    fi
fi
