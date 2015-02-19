#!/bin/bash
#    Copyright (c) 2014 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#

TOP_DIR=~

DEST=$TOP_DIR/murano
SCREEN_LOGDIR=$DEST/logs
CURRENT_LOG_TIME=$(TZ=Europe/Moscow date +"%Y-%m-%d-%H%M%S")

MURANO_CONF=./etc/murano/murano.conf

# Any non-empty string means 'true'
WITH_VENV=${WITH_VENV:-''}

#set -o nounset

function screen_service {
    local service=$1
    local workdir="$2"
    local command="$3"

    echo ''
    echo "Starting ${service} in '${workdir}' ..."

    SCREEN_NAME=${SCREEN_NAME:-murano}
    SERVICE_DIR=${SERVICE_DIR:-${DEST}/status}

    mkdir -p $SERVICE_DIR/$SCREEN_NAME

    # Append the service to the screen rc file
    screen_rc "$service" "$command"

    screen -S $SCREEN_NAME -X screen -t $service

    if [[ -n ${SCREEN_LOGDIR} ]]; then
        screen -S $SCREEN_NAME -p $service -X logfile ${SCREEN_LOGDIR}/screen-${service}.${CURRENT_LOG_TIME}.log
        screen -S $SCREEN_NAME -p $service -X log on
        ln -sf ${SCREEN_LOGDIR}/screen-${service}.${CURRENT_LOG_TIME}.log ${SCREEN_LOGDIR}/screen-${service}.log
    fi

    # sleep to allow bash to be ready to send the command - we are
    # creating a new window in screen and then send characters, so if
    # bash isn't running by the time we send the command, nothing will happen
    sleep 3

    NL=`echo -ne '\015'`
    # This fun command does the following:
    # - the passed server command is backgrounded
    # - the pid of the background process is saved in the usual place
    # - the server process is brought back to the foreground
    # - if the server process exits prematurely the fg command errors
    #   and a message is written to stdout and the service failure file
    # The pid saved can be used in stop_process() as a process group
    # id to kill off all child processes
    screen -S $SCREEN_NAME -p $service -X stuff "cd \"$workdir\" $NL"
    if [[ "${WITH_VENV}" ]]; then
        screen -S $SCREEN_NAME -p $service -X stuff "source .tox/venv/bin/activate $NL"
    fi
    screen -S $SCREEN_NAME -p $service -X stuff "$command & echo \$! >$SERVICE_DIR/$SCREEN_NAME/${service}.pid; fg || echo \"$service failed to start\" | tee \"$SERVICE_DIR/$SCREEN_NAME/${service}.failure\" $NL"

    echo '... done'
}


function screen_stop_service {
    local service=$1

    SCREEN_NAME=${SCREEN_NAME:-murano}
    SERVICE_DIR=${SERVICE_DIR:-${DEST}/status}

    echo ''
    echo "Stopping ${service} ..."

    # Clean up the screen window
    screen -S $SCREEN_NAME -p $service -X kill

    echo '... done'
}


function screen_rc {
    SCREEN_NAME=${SCREEN_NAME:-murano}
    SCREENRC=$TOP_DIR/$SCREEN_NAME-screenrc

    if [[ ! -e $SCREENRC ]]; then
        # Name the screen session
        echo "sessionname $SCREEN_NAME" > $SCREENRC
        # Set a reasonable statusbar
        echo "hardstatus alwayslastline '$SCREEN_HARDSTATUS'" >> $SCREENRC
        # Some distributions override PROMPT_COMMAND for the screen terminal type - turn that off
        echo "setenv PROMPT_COMMAND /bin/true" >> $SCREENRC
        echo "screen -t shell bash" >> $SCREENRC
    fi

    # If this service doesn't already exist in the screenrc file
    if ! grep $1 $SCREENRC 2>&1 > /dev/null; then
        NL=`echo -ne '\015'`
        echo "screen -t $1 bash" >> $SCREENRC
        echo "stuff \"$2$NL\"" >> $SCREENRC

        if [[ -n ${SCREEN_LOGDIR} ]]; then
            echo "logfile ${SCREEN_LOGDIR}/screen-${1}.${CURRENT_LOG_TIME}.log" >>$SCREENRC
            echo "log on" >>$SCREENRC
        fi
    fi
}


function screen_session_start {
    SCREEN_NAME=${SCREEN_NAME:-murano}

    echo ''
    echo 'Starting new screen session ...'

    screen_count=$(screen -ls | awk "/[0-9]\.${SCREEN_NAME}/{print \$0}" | wc -l)

    if [[ ${screen_count} -eq 0 ]]; then
        echo 'No screen sessions found, creating a new one'
        screen -dmS ${SCREEN_NAME}
    elif [[ ${screen_count} -eq 1 ]]; then
        echo 'Screen session found'
    else
        echo "${screen_count} sessions found, should be 1."
        exit 1
    fi

    echo '... done'
}


function screen_session_quit {
    SCREEN_NAME=${SCREEN_NAME:-murano}
    SCREENRC=$TOP_DIR/$SCREEN_NAME-screenrc

    echo ''
    echo 'Terminating screen sessions ...'

    for session in $(screen -ls | awk "/[0-9]\.${SCREEN_NAME}/{print \$1}"); do
        screen -X -S ${session} quit
    done

    rm -f $SCREENRC

    echo '... done'
}


function create_venv {
    local path="$1"

    echo ''
    echo "Creating virtual env in '${path}' ..."

    pushd ${path}
    tox -r -e venv -- python setup.py install
    popd

    echo '... done'
}


function prepare_devbox {
    sudo apt-get update
    sudo apt-get --yes upgrade

    # Install prerequisites for using tox
    sudo apt-get --yes install \
        python-dev \
        python-pip \
        libmysqlclient-dev \
        libpq-dev \
        libxml2-dev \
        libxslt1-dev \
        libffi-dev \
        screen

    # Install other prereqisites
    sudo apt-get --yes install \
        git \
        rabbitmq-server

    # Install MySQL server
    sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password ${MYSQL_ROOT_PASSWORD}"
    sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${MYSQL_ROOT_PASSWORD}"
    sudo apt-get -qq --yes install mysql-server

    # Change RabbitMQ 'guest' password
    sudo rabbitmqctl change_password guest ${RABBIT_PASSWORD}
    # Enable rabbitmq_management plugin
    sudo /usr/lib/rabbitmq/bin/rabbitmq-plugins enable rabbitmq_management
    sudo service rabbitmq-server restart

    mysqladmin -u root -p${MYSQL_ROOT_PASSWORD} -f drop murano
    mysqladmin -u root -p${MYSQL_ROOT_PASSWORD} create murano
    mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "GRANT ALL PRIVILEGES ON murano.* TO murano@localhost IDENTIFIED BY '${MYSQL_MURANO_PASSWORD}'" murano

    sudo pip install tox

    mkdir -p ${DEST}/logs
    mkdir -p ${DEST}/status

    pushd ${DEST}
        git clone ${MURANO_REPO}
        
        pushd ${DEST}/murano
        if [ -n "$MURANO_BRANCH" ]; then
            git checkout ${MURANO_BRANCH}
        fi
        popd
        
        git clone ${MURANO_DASHBOARD_REPO}
        
        pushd ${DEST}/murano-dasbboard
        if [ -n "$MURANO_DASHBOARD_BRANCH" ]; then
            git checkout ${MURANO_DASHBOARD_BRANCH}
        fi
        popd
        
        git clone ${MURANO_APPS_REPO}
        
        pushd ${DEST}/murano-app-incubator
        if [ -n "$MURANO_APPS_BRANCH" ]; then
            git checkout ${MURANO_APPS_BRANCH}
        fi
        popd
    popd

    create_venv ${DEST}/murano
    create_venv ${DEST}/murano-dashboard

    pushd ${DEST}/murano
    tox -e venv -- oslo-config-generator --config-file etc/oslo-config-generator/murano.conf
    popd
}

function collect_static {
    pushd ${DEST}/murano-dashboard
    tox -e venv -- python manage.py collectstatic --noinput
    popd
}

function iniset {
    local xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local file=$1
    local section=$2
    local option=$3
    local value=$4

    [[ -z $section || -z $option ]] && return

    if ! grep -q "^\[$section\]" "$file" 2>/dev/null; then
        # Add section at the end
        echo -e "\n[$section]" >>"$file"
    fi
    if ! ini_has_option "$file" "$section" "$option"; then
        # Add it
        sed -i -e "/^\[$section\]/ a\\
$option = $value
" "$file"
    else
        local sep=$(echo -ne "\x01")
        # Replace it
        sed -i -e '/^\['${section}'\]/,/^\[.*\]/ s'${sep}'^\('${option}'[ \t]*=[ \t]*\).*$'${sep}'\1'"${value}"${sep} "$file"
    fi
    $xtrace
}

function ini_has_option {
    local xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local file=$1
    local section=$2
    local option=$3
    local line
    line=$(sed -ne "/^\[$section\]/,/^\[.*\]/ { /^$option[ \t]*=/ p; }" "$file")
    $xtrace
    [ -n "$line" ]
}

function configure_murano {
    cp ${DEST}/murano/${MURANO_CONF}.sample ${DEST}/murano/${MURANO_CONF}

    iniset ${DEST}/murano/${MURANO_CONF} DEFAULT debug true
    iniset ${DEST}/murano/${MURANO_CONF} DEFAULT use_syslog false
    iniset ${DEST}/murano/${MURANO_CONF} DEFAULT rabbit_password $RABBIT_PASSWORD
    # Configure notifications for status information during provisioning
    iniset ${DEST}/murano/${MURANO_CONF} DEFAULT notification_driver messagingv2

    iniset ${DEST}/murano/${MURANO_CONF} rabbitmq host $RABBIT_HOST
    iniset ${DEST}/murano/${MURANO_CONF} rabbitmq password $RABBIT_PASSWORD

    # Setup keystone_authtoken section
    iniset ${DEST}/murano/${MURANO_CONF} keystone_authtoken auth_uri "http://${KEYSTONE_AUTH_HOST}:5000/v2.0"
    iniset ${DEST}/murano/${MURANO_CONF} keystone_authtoken auth_host $KEYSTONE_AUTH_HOST
    iniset ${DEST}/murano/${MURANO_CONF} keystone_authtoken auth_port $KEYSTONE_AUTH_PORT
    iniset ${DEST}/murano/${MURANO_CONF} keystone_authtoken auth_protocol $KEYSTONE_AUTH_PROTOCOL
    iniset ${DEST}/murano/${MURANO_CONF} keystone_authtoken cafile $KEYSTONE_SSL_CA
    iniset ${DEST}/murano/${MURANO_CONF} keystone_authtoken admin_tenant_name $SERVICE_TENANT_NAME
    iniset ${DEST}/murano/${MURANO_CONF} keystone_authtoken admin_user $MURANO_ADMIN_USER
    iniset ${DEST}/murano/${MURANO_CONF} keystone_authtoken admin_password $SERVICE_PASSWORD

    # configure the database.
    iniset ${DEST}/murano/${MURANO_CONF} database connection "mysql://murano:${MYSQL_MURANO_PASSWORD}@localhost/murano"

    # Configure keystone auth url
    iniset ${DEST}/murano/${MURANO_CONF} keystone auth_url "http://${KEYSTONE_AUTH_HOST}:5000/v2.0"

    # Configure Murano API URL
    iniset ${DEST}/murano/${MURANO_CONF} murano url "http://127.0.0.1:8082"
}

function configure_murano_dashboard {
    pushd ${DEST}/murano-dashboard/muranodashboard/local

    cp local_settings.py.example local_settings.py
    sed -i "s/OPENSTACK_HOST = \"127.0.0.1\"/OPENSTACK_HOST = \"${KEYSTONE_AUTH_HOST}\"/g" ./local_settings.py

    cat << EOF >> ./local_settings.py


#DATABASES = {
#    'default': {
#    'ENGINE': 'django.db.backends.sqlite3',
#    'NAME': '/tmp/murano-dashboard.sqlite',
#    }
#}
#SESSION_ENGINE = 'django.contrib.sessions.backends.db'

MURANO_API_URL = 'http://${DEVBOX_IP}:8082'
EOF
    popd

    pushd ${DEST}/murano-dashboard
    ./prepare_murano.sh --openstack-dashboard .tox/venv/lib/python2.7/site-packages/openstack_dashboard
#    tox -e venv -- python ./manage.py syncdb
    tox -e venv -- python manage.py collectstatic --noinput
    popd
}

function import_app {
    local path=${1:-.}

    echo ''
    if [[ -f "${path}/manifest.yaml" ]]; then
        app_path=$(cd "${path}" && pwd)
    elif [[ -f "${DEST}/murano-app-incubator/${path}/manifest.yaml" ]]; then
        app_path="${DEST}/murano-app-incubator/${path}"
    else
        app_path=''
    fi

    if [[ -n "${app_path}" ]]; then
        echo ''
        echo "Importing Murano Application from '${app_path}' ..."

        pushd ${DEST}/murano
        if [[ "${WITH_VENV}" ]]; then
            source .tox/venv/bin/activate
            murano-manage --config-file ${MURANO_CONF} import-package "${app_path}" --update
            deactivate
        else
            tox -e venv -- murano-manage --config-file ${MURANO_CONF} import-package "${app_path}" --update
        fi
        popd

        echo '... done'
    else
        echo "No Murano Application found using pathspec '${path}'."
    fi
}

function import_from {
    local path=${1}
    if [ -d ${path} ]; then
        for app in $(find ${path} -type d -maxdepth 1); do
            import_app "${app}"
        done
    else
        echo "Directory not found '${path}'"
    fi
}

function show_help {
    cat << EOF | less

manage-devbox - manage Murano Development Box.

SYNOPSIS

    manage-devbox <command>

COMMANDS

    start
        Start Murano services inside screen session. If a session already
        exists it will be used. If not a new one will be created.

    stop
        Stop Murano services and quit screen session.

    dbsync
        Remove Murano SQLite database and create it from scratch.

    dbinit
        Import Murano Core package.

    install
        Install Murano services and prerequisites into virtual env.

    configure
        Configure Murano services.

    import <path[ path2[ path3[...]]]>
        Import Murano Applications from <path>.

    import-app-incubator
        Import all packages from murano-app-incubator directory.

    import-from
        Import all packages from a directory.
EOF
}


case $1 in
    'start')
        screen_session_start
        if [[ "${WITH_VENV}" ]]; then
            screen_service 'murano-api' "${DEST}/murano" "murano-api --config-file ${MURANO_CONF}"
            screen_service 'murano-engine' "${DEST}/murano" "murano-engine --config-file ${MURANO_CONF}"
            screen_service 'murano-dashboard' "${DEST}/murano-dashboard" 'python manage.py runserver 0.0.0.0:8080'
        else
            screen_service 'murano-api' "${DEST}/murano" "tox -e venv -- murano-api --config-file ${MURANO_CONF}"
            screen_service 'murano-engine' "${DEST}/murano" "tox -e venv -- murano-engine --config-file ${MURANO_CONF}"
            screen_service 'murano-dashboard' "${DEST}/murano-dashboard" 'tox -e venv -- python manage.py runserver 0.0.0.0:8080'
        fi
    ;;
    'stop')
        screen_stop_service 'murano-dashboard'
        screen_stop_service 'murano-engine'
        screen_stop_service 'murano-api'
        screen_session_quit
    ;;
    'restart')
        screen_stop_service 'murano-dashboard'
        screen_stop_service 'murano-engine'
        screen_stop_service 'murano-api'
        screen_session_quit

        screen_session_start
        if [[ "${WITH_VENV}" ]]; then
            screen_service 'murano-api' "${DEST}/murano" "murano-api --config-file ${MURANO_CONF}"
            screen_service 'murano-engine' "${DEST}/murano" "murano-engine --config-file ${MURANO_CONF}"
            screen_service 'murano-dashboard' "${DEST}/murano-dashboard" 'python manage.py runserver 0.0.0.0:8080'
        else
            screen_service 'murano-api' "${DEST}/murano" "tox -e venv -- murano-api --config-file ${MURANO_CONF}"
            screen_service 'murano-engine' "${DEST}/murano" "tox -e venv -- murano-engine --config-file ${MURANO_CONF}"
            screen_service 'murano-dashboard' "${DEST}/murano-dashboard" 'tox -e venv -- python manage.py runserver 0.0.0.0:8080'
        fi
    ;;
    'dbsync')
        rm ${DEST}/murano/murano.sqlite
        pushd ${DEST}/murano
        if [[ "${WITH_VENV}" ]]; then
            source .tox/venv/bin/activate
            murano-db-manage --config-file ${MURANO_CONF} upgrade
            deactivate
        else
            tox -e venv -- murano-db-manage --config-file ${MURANO_CONF} upgrade
        fi
        popd
    ;;
    'dbinit')
        pushd ${DEST}/murano
        if [[ "${WITH_VENV}" ]]; then
            source .tox/venv/bin/activate
            murano-manage --config-file ${MURANO_CONF} import-package ./meta/io.murano --update
            deactivate
        else
            tox -e venv -- murano-manage --config-file ${MURANO_CONF} import-package ./meta/io.murano --update
        fi
        popd
    ;;
    'install')
        prepare_devbox
    ;;
    'configure')
        configure_murano
        configure_murano_dashboard
    ;;
    'import')
        shift
        while [ -n "$1" ]; do
            import_app "$1"
            shift
        done
    ;;
    'import-app-incubator')
        if [ ! -d ${DEST}/murano-app-incubator ]; then
            git clone https://github.com/murano-project/murano-app-incubator ${DEST}/murano-app-incubator
        fi
        import_from ${DEST}/murano-app-incubator
    ;;
    'import-from')
        import_from ${2}
    ;;
    *)
        show_help
    ;;
esac

