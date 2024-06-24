#!/bin/bash

source /var/openstack/export

mysql -uroot -p$db_password -e "create database IF NOT EXISTS keystone ;"
mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$keystone' ;"
mysql -uroot -p$db_password -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$keystone' ;"

apt -y install keystone
cp /etc/keystone/keystone.conf{,.bak}


crudini --set /etc/keystone/keystone.conf database connection mysql+pymysql://keystone:$keystone@controller/keystone
crudini --set /etc/keystone/keystone.conf token expiration 86400
crudini --set /etc/keystone/keystone.conf token provider fernet
su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password $keystone \
    --bootstrap-admin-url http://controller:5000/v3/ \
    --bootstrap-internal-url http://controller:5000/v3/ \
    --bootstrap-public-url http://controller:5000/v3/ \
    --bootstrap-region-id RegionOne
echo "ServerName controller"   >> /etc/apache2/apache2.conf
systemctl enable apache2
service apache2 restart

cat >/etc/keystone/admin-openrc.sh <<EOF
#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD=$keystone
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

source /etc/keystone/admin-openrc.sh
openstack user list
openstack project create --domain default  --description "Service Project" service

openstack role add --user admin --domain default admin 
openstack role add --user admin --domain default reader


openstack domain create --description "An Example Domain" example
openstack project create --domain example   --description "Service Project" example
openstack user create --domain example --password example example
openstack role add --project example --user example --project-domain  example admin



