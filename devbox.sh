#!/bin/bash
export RABBIT_HOST=10.20.30.50
export RABBIT_PASSWORD=904718
export KEYSTONE_AUTH_HOST=10.20.30.50
export KEYSTONE_AUTH_PORT=5000
export KEYSTONE_AUTH_PROTOCOL=http
export KEYSTONE_SSL_CA=
export SERVICE_TENANT_NAME=murano
export MURANO_ADMIN_USER=admin
export SERVICE_PASSWORD=904718
export MURANO_DATABASE_URL=mysql://murano:904718@10.20.30.50/murano
export MURANO_REPO=https://github.com/stackforge/murano
export MURANO_DASHBOARD_REPO=https://github.com/stackforge/murano-dashboard
export MURANO_APPS_REPO=https://github.com/murano-project/murano-app-incubator

./manage-devbox.sh configure
