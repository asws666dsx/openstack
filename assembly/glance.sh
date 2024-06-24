#!/bin/bash
source /var/openstack/export

source /etc/keystone/admin-openrc.sh

mysql -uroot -p$db_password -e "create database IF NOT EXISTS glance;"
mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$glance';"
mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$glance';"




openstack user create --domain default --password  $glance glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://controller:9292
openstack endpoint create --region RegionOne image internal http://controller:9292 
openstack endpoint create --region RegionOne image admin http://controller:9292



apt -y install glance

cp /etc/glance/glance-api.conf  /etc/glance/glance-api.conf.source


# 设置 [DEFAULT] 部分的属性
crudini --set /etc/glance/glance-api.conf DEFAULT enabled_backends fs:file
crudini --set /etc/glance/glance-api.conf DEFAULT show_image_direct_url True
crudini --set /etc/glance/glance-api.conf DEFAULT transport_url rabbit://openstack:$rabbitmq_password@controller

# 设置 [database] 部分的属性
crudini --set /etc/glance/glance-api.conf database connection mysql+pymysql://glance:$glance@controller/glance

# 设置 [glance_store] 部分的属性
crudini --set /etc/glance/glance-api.conf glance_store default_backend fs

# 设置 [keystone_authtoken] 部分的属性
crudini --set /etc/glance/glance-api.conf keystone_authtoken www_authenticate_uri http://controller:5000
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_url http://controller:5000
crudini --set /etc/glance/glance-api.conf keystone_authtoken memcached_servers controller:11211
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_type password
crudini --set /etc/glance/glance-api.conf keystone_authtoken project_domain_name Default
crudini --set /etc/glance/glance-api.conf keystone_authtoken user_domain_name Default
crudini --set /etc/glance/glance-api.conf keystone_authtoken project_name service
crudini --set /etc/glance/glance-api.conf keystone_authtoken username glance
crudini --set /etc/glance/glance-api.conf keystone_authtoken password $glance

# 设置 [paste_deploy] 部分的属性
crudini --set /etc/glance/glance-api.conf paste_deploy flavor keystone

# 设置 [fs] 部分的属性
crudini --set /etc/glance/glance-api.conf fs filesystem_store_datadir /var/lib/glance/images/


# 设置 [oslo_limit] 部分的属性
crudini --set /etc/glance/glance-api.conf oslo_limit auth_url http://controller:5000
crudini --set /etc/glance/glance-api.conf oslo_limit auth_type password
crudini --set /etc/glance/glance-api.conf oslo_limit user_domain_id Default
crudini --set /etc/glance/glance-api.conf oslo_limit username glance
crudini --set /etc/glance/glance-api.conf oslo_limit system_scope all
crudini --set /etc/glance/glance-api.conf oslo_limit password $glance

endpoint_id=$(openstack endpoint list | grep glance  | grep admin | awk '{print $2}')
crudini --set /etc/glance/glance-api.conf oslo_limit endpoint_id  $endpoint_id
crudini --set /etc/glance/glance-api.conf oslo_limit region_name RegionOne



su -s /bin/sh -c "glance-manage db_sync" glance



systemctl daemon-reload
service glance-api restart
systemctl enable glance-api
