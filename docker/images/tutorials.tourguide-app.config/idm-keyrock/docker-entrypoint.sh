#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends curl
source /tourguide/common/entrypoint-common.sh

declare DOMAIN=''

# Funtion that checks if the domain has been already created at Authzforce

function check_domain () {

    if [ $# -lt 2 ] ; then
        echo "check_host_port: missing parameters."
        echo "Usage: check_host_port <host> <port> [max-tries]"
        exit 1
    fi

    local _host=$1
    local _port=$2
    local CURL=$( which curl )

    if [ ! -e "${CURL}" ] ; then
        echo "Unable to find 'curl' command."
        exit 1
    fi

    if [ ! -e /config/domain-ready ] ; then

        # Creates the domain

        payload_440='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><ns4:domainProperties xmlns:ns4="http://authzforce.github.io/rest-api-model/xmlns/authz/4" externalId="external0"><description>This is my domain</description></ns4:domainProperties>'
        payload_420='<?xml version="1.0" encoding="UTF-8"?><taz:properties xmlns:taz="http://thalesgroup.com/authz/model/3.0/resource"><name>MyDomain</name><description>This is my domain.</description></taz:properties>'

        case "${AUTHZFORCE_VERSION}" in
            "4.2.0")
                payload="${payload_420}"
                ;;
            *)
                payload="${payload_440}"
                ;;
        esac

        ${CURL} -s \
                --request POST \
                --header "Content-Type: application/xml;charset=UTF-8" \
                --data "$payload" \
                --header "Accept: application/xml" \
                --output /dev/null \
                http://${_host}:${_port}/${AUTHZFORCE_BASE_PATH}/domains

    fi

    DOMAIN=$( ${CURL} -s --request GET http://${_host}:${_port}/${AUTHZFORCE_BASE_PATH}/domains | awk '/href/{print $NF}' | cut -d '"' -f2 )
    if [ -z "${DOMAIN}" ] ; then
        echo "Unable to find domain."
        exit 1
    else
        echo "Domain: $DOMAIN"
        if [ ! -e /config/domain-ready ] ; then
            touch /config/domain-ready
        fi
    fi
}

# Function to call a script that generates a JSON with the app information

function _config_file () {

    echo "Parsing App information into a JSON file"
    python /tourguide/idm-keyrock/params-config.py --name ${APP_NAME} --file ${CONFIG_FILE} --database ${KEYSTONE_DB}
}

# Syncronize roles and permissions to Authzforce from the scratch

function _authzforce_sync () {

    echo "Syncing with Authzforce."
    pushd /horizon/
    cp /tourguide/idm-keyrock/access_control_xacml.py access_control_xacml.py
    if [ "${AUTHZFORCE_VERSION}" != "4.2.0" ] ; then
        sed -i openstack_dashboard/fiware_api/access_control_ge.py \
            -e 's|/authzforce/|/|g' \
            -e 's|policySet|policies|g' \
            -e '/\/pap\/policies/,$ s/requests.put/requests.post/'
    fi
    tools/with_venv.sh python access_control_xacml.py --file ${CONFIG_FILE} --domain ${DOMAIN}
    rm -f access_control_xacml.py
    popd
    echo "Authzforce sucessfully parsed."

}

# Provide a set of users, roles, permissions, etc to handle KeyRock

function _data_provision () {

    if [ -e /config/provision-ready ] ; then
        echo "Data provision already done."
    else
        pushd /keystone

        # remove existing database
        if [ -f keystone.db ] ; then
            rm -f keystone.db
        fi

        # create a new database
        echo "Creating Keystone database."
        source .venv/bin/activate
        bin/keystone-manage -v db_sync
        bin/keystone-manage -v db_sync --extension=oauth2
        bin/keystone-manage -v db_sync --extension=roles
        bin/keystone-manage -v db_sync --extension=user_registration
        bin/keystone-manage -v db_sync --extension=two_factor_auth
        bin/keystone-manage -v db_sync --extension=endpoint_filter
        echo "Provisioning users, roles, and apps."
        (sleep 5 ; echo idm) | bin/keystone-manage -v db_sync --populate

        check_file ${PROVISION_FILE} 30
        if [ $? -ne 0 ]; then
            echo "Provision file '${PROVISION_FILE}' not found."
            echo "Aborting."
            exit 1
        fi

        cp /tourguide/idm-keyrock/settings.py /config/settings.py
        python ${PROVISION_FILE}
        echo "Provision done."
        _config_file
        deactivate
        popd
        _authzforce_sync
        touch /config/provision-ready
    fi

}

function start_keystone () {
    echo "Starting Keystone server."
    (
        cd /keystone/
        ./tools/with_venv.sh bin/keystone-all ${KEYSTONE_VERBOSE_LOG} >> /var/log/keystone.log 2>&1 &
        # wait for keystone to be ready
        check_host_port localhost 5000
    )
}

function start_horizon () {
    echo "Starting Horizon server."
    (
        cd /horizon/
        ./tools/with_venv.sh python manage.py runserver 0.0.0.0:${HORIZON_PORT} >> /var/log/horizon.log 2>&1 &
        # wait for horizon to be ready
        check_host_port 0.0.0.0 ${HORIZON_PORT}
    )
}

function tail_logs () {
    horizon_logs='/var/log/horizon.log'
    keystone_logs='/var/log/keystone.log'
    tail -F ${horizon_logs} ${keystone_logs}
}

if [ $# -eq 0 -o "${1:0:1}" = '-' ] ; then

    check_var AUTHZFORCE_HOSTNAME authzforce
    check_var AUTHZFORCE_PORT 8080
    check_var AUTHZFORCE_VERSION 4.2.0
    case "${AUTHZFORCE_VERSION}" in
        "4.2.0")
            check_var AUTHZFORCE_BASE_PATH authzforce
            ;;
        *)
            check_var AUTHZFORCE_BASE_PATH authzforce-ce
            ;;
    esac
    check_var MAGIC_KEY daf26216c5434a0a80f392ed9165b3b4
    check_var APP_NAME "TourGuide"
    check_var KEYSTONE_DB /keystone/keystone.db
    check_var CONFIG_FILE /config/idm2chanchan.json
    check_var PROVISION_FILE /config/keystone_provision.py
    check_var KEYSTONE_VERBOSE no
    check_var HORIZON_PORT 80

    # fix variables when using docker-compose
    if [[ ${AUTHZFORCE_PORT} =~ ^tcp://[^:]+:(.*)$ ]] ; then
        export AUTHZFORCE_PORT=${BASH_REMATCH[1]}
    fi

    if [ "${KEYSTONE_VERBOSE}" = "yes" ] ; then
        export KEYSTONE_VERBOSE_LOG="-v"
    else
        export KEYSTONE_VERBOSE_LOG=""
    fi

    # Call checks

    check_host_port ${AUTHZFORCE_HOSTNAME} ${AUTHZFORCE_PORT}
    check_domain ${AUTHZFORCE_HOSTNAME} ${AUTHZFORCE_PORT}

    # Start keystone first
    start_keystone

    tail_logs & _waitpid=$!

    # Configure access control settings
    ACCESS_CONTROL_URL="http://${AUTHZFORCE_HOSTNAME}:${AUTHZFORCE_PORT}/${AUTHZFORCE_BASE_PATH}"
    sed  -i /horizon/openstack_dashboard/local/local_settings.py \
         -e "s|^ACCESS_CONTROL_URL = None|ACCESS_CONTROL_URL = '${ACCESS_CONTROL_URL}'|" \
         -e "s|^ACCESS_CONTROL_MAGIC_KEY = None|ACCESS_CONTROL_MAGIC_KEY = '${MAGIC_KEY}'|"

    # Do data provision if needed
    _data_provision

    # Then start horizon
    start_horizon

    # follow logs
    wait "${_waitpid}"
else
    exec "$@"
fi
