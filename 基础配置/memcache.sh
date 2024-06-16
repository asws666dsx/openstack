#!/bin/bash

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


setup_memcache
