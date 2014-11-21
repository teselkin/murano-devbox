#!/bin/bash
export RABBIT_HOST=127.0.0.1
export RABBIT_PASSWORD=password
export KEYSTONE_AUTH_HOST=127.0.0.1
export KEYSTONE_AUTH_PORT=5000
export KEYSTONE_AUTH_PROTOCOL=http
export KEYSTONE_SSL_CA=keystone.ca
export SERVICE_TENANT_NAME=murano
export MURANO_ADMIN_USER=admin
export SERVICE_PASSWORD=password
export MYSQL_ROOT_PASSWORD=password
export MYSQL_MURANO_PASSWORD=password
export MURANO_REPO=https://github.com/stackforge/murano
export MURANO_DASHBOARD_REPO=https://github.com/stackforge/murano-dashboard
export MURANO_APPS_REPO=https://github.com/murano-project/murano-app-incubator
export MURANO_BRANCH=master
export MURANO_DASHBOARD_BRANCH=master
export MURANO_APPS_BRANCH=master

case $1 in
  install-only)
    ./manage-devbox.sh install
  ;;
	install)
		./manage-devbox.sh install
		./manage-devbox.sh configure
		./manage-devbox.sh start
	;;
	configure)
		./manage-devbox.sh configure
		./manage-devbox.sh restart
	;;
	restart)
		./manage-devbox.sh restart
  ;;
  set)
    case $2 in
      RABBIT_HOST|RABBIT_PASSWORD|KEYSTONE_AUTH_HOST|KEYSTONE_SSL_CA|SERVICE_TENANT_NAME|MURANO_ADMIN_USER|SERVICE_PASSWORD|MYSQL_ROOT_PASSWORD|MYSQL_MURANO_PASSWORD)
        sed -ir "s/^export $2=\(.*\)$/export $2=$3/g" $0;
      ;;
      KEYSTONE_AUTH_PORT|KEYSTONE_AUTH_PROTOCOL|MURANO_REPO|MURANO_DASHBOARD_REPO|MURANO_APPS_REPO|MURANO_BRANCH|MURANO_DASHBOARD_BRANCH|MURANO_APPS_BRANCH)
        if [ -n "$3" ];
          then sed -ir "s/^export $2=\(.*\)$/export $2=$3/g" $0;
        fi
      ;;
      *)
        echo "Available parameters and it's values"
        for KEY in `cat $0 | grep '^export' | awk '{ print $2 }' | awk -F'=' '{ print $1 }'`; 
        do
          VALUE=`cat $0 | grep "^export $KEY" | awk '{ print $2 }' | awk -F'=' '{ print $2 }'`;
          echo "$KEY = $VALUE";
        done
      ;;
    esac
  ;;
  *)
    cat << EOF | less
devbox - Murano Deployment Script launcher

SYNOPSIS

    devbox <command> [<argument>]

COMMANDS

    install
        Install, configure and start murano instance. (.aka Make Me Happy)

    install-only
        Just install murano. (Do nothing else. Trust me)

    configure
        Generate set of murano config files and restart murano instance.

    restart
        Restart murano instance.

    set
        Set murano configuration variable value.

EOF
esac
