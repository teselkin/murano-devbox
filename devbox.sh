#!/bin/bash
export RABBIT_HOST=127.0.0.1
export RABBIT_PASSWORD=
export KEYSTONE_AUTH_HOST=172.16.40.137
export KEYSTONE_AUTH_PORT=5000
export KEYSTONE_AUTH_PROTOCOL=http
export KEYSTONE_SSL_CA=
export SERVICE_TENANT_NAME=velovec-murano
export MURANO_ADMIN_USER=velovec
export SERVICE_PASSWORD=19v9m24u~
export MURANO_DATABASE_URL=mysql://murano:904718@localhost/murano
export MURANO_REPO=https://github.com/stackforge/murano
export MURANO_DASHBOARD_REPO=https://github.com/stackforge/murano-dashboard
export MURANO_APPS_REPO=https://github.com/murano-project/murano-app-incubator

./manage-devbox.sh install
./manage-devbox.sh configure
./manage-devbox.sh start
