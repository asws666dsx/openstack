#!/bin/bash
source /var/openstack/export

source /etc/keystone/admin-openrc.sh


mysql -uroot -p$db_password -e "CREATE DATABASE IF NOT EXISTS placement;"
mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$placement';"
mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$placement';"


openstack user create --domain default --password $placement placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement
openstack endpoint create --region RegionOne placement public http://controller:8778
openstack endpoint create --region RegionOne placement internal http://controller:8778  
openstack endpoint create --region RegionOne placement admin http://controller:8778




apt -y install placement-api

cp  /etc/placement/placement.conf   /etc/placement/placement.conf.source  

# 设置 [api] 部分的属性
crudini --set /etc/placement/placement.conf api auth_strategy keystone

# 设置 [keystone_authtoken] 部分的属性
crudini --set /etc/placement/placement.conf keystone_authtoken auth_url http://controller:5000/v3
crudini --set /etc/placement/placement.conf keystone_authtoken memcached_servers controller:11211
crudini --set /etc/placement/placement.conf keystone_authtoken auth_type password
crudini --set /etc/placement/placement.conf keystone_authtoken project_domain_name Default
crudini --set /etc/placement/placement.conf keystone_authtoken user_domain_name Default
crudini --set /etc/placement/placement.conf keystone_authtoken project_name service
crudini --set /etc/placement/placement.conf keystone_authtoken username placement
crudini --set /etc/placement/placement.conf keystone_authtoken password $placement

# 设置 [placement_database] 部分的属性
crudini --set /etc/placement/placement.conf placement_database connection mysql+pymysql://placement:$placement@controller/placement


su -s /bin/sh -c "placement-manage db sync" placement
service apache2 restart
placement-status upgrade check



openstack --os-placement-api-version 1.2 resource class list --sort-column name

openstack --os-placement-api-version 1.6 trait list --sort-column name

