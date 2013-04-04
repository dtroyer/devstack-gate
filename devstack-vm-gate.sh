#!/bin/bash

# Script that is run on the devstack vm; configures and
# invokes devstack.

# Copyright (C) 2011-2012 OpenStack LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit

function setup_localrc() {
    LOCALRC_OLDNEW=$1;
    LOCALRC_BRANCH=$2;

    # Allow calling context to pre-populate the localrc file
    # with additional values
    if [ -z $KEEP_LOCALRC ] ; then
        rm -f localrc
    fi

    DEFAULT_ENABLED_SERVICES=g-api,g-reg,key,n-api,n-crt,n-obj,n-cpu,n-sch,horizon,mysql,rabbit,sysstat

    # Allow optional injection of ENABLED_SERVICES from the calling context
    if [ -z $ENABLED_SERVICES ] ; then
        MY_ENABLED_SERVICES=$DEFAULT_ENABLED_SERVICES
    else
        MY_ENABLED_SERVICES=$DEFAULT_ENABLED_SERVICES,$ENABLED_SERVICES
    fi

    if [ "$DEVSTACK_GATE_TEMPEST" -eq "1" ]; then
        MY_ENABLED_SERVICES=$MY_ENABLED_SERVICES,tempest
    fi

    SKIP_EXERCISES=boot_from_volume,client-env

    if [ "$LOCALRC_BRANCH" == "stable/diablo" ] ||
        [ "$LOCALRC_BRANCH" == "stable/essex" ]; then
        MY_ENABLED_SERVICES=$MY_ENABLED_SERVICES,n-vol,n-net
        SKIP_EXERCISES=$SKIP_EXERCISES,swift
    elif [ "$LOCALRC_BRANCH" == "stable/folsom" ]; then
        MY_ENABLED_SERVICES=$MY_ENABLED_SERVICES,n-net,swift
        if [ "$DEVSTACK_GATE_CINDER" -eq "1" ]; then
            MY_ENABLED_SERVICES=$MY_ENABLED_SERVICES,cinder,c-api,c-vol,c-sch
        else
            MY_ENABLED_SERVICES=$MY_ENABLED_SERVICES,n-vol
        fi
    else # master
        MY_ENABLED_SERVICES=$MY_ENABLED_SERVICES,s-proxy,s-account,s-container,s-object,cinder,c-api,c-vol,c-sch,n-cond
        if [ "$DEVSTACK_GATE_QUANTUM" -eq "1" ]; then
            MY_ENABLED_SERVICES=$MY_ENABLED_SERVICES,quantum,q-svc,q-agt,q-dhcp,q-l3,q-meta
            echo "Q_USE_DEBUG_COMMAND=True" >>localrc
            echo "NETWORK_GATEWAY=10.1.0.1" >>localrc
        else
            MY_ENABLED_SERVICES=$MY_ENABLED_SERVICES,n-net
        fi
    fi

cat <<EOF >>localrc
DEST=$BASE/$LOCALRC_OLDNEW
ACTIVE_TIMEOUT=90
BOOT_TIMEOUT=90
ASSOCIATE_TIMEOUT=60
TERMINATE_TIMEOUT=60
MYSQL_PASSWORD=secret
DATABASE_PASSWORD=secret
RABBIT_PASSWORD=secret
ADMIN_PASSWORD=secret
SERVICE_PASSWORD=secret
SERVICE_TOKEN=111222333444
SWIFT_HASH=1234123412341234
ROOTSLEEP=0
ERROR_ON_CLONE=True
ENABLED_SERVICES=$MY_ENABLED_SERVICES
SKIP_EXERCISES=$SKIP_EXERCISES
SERVICE_HOST=127.0.0.1
# Screen console logs will capture service logs.
SYSLOG=False
SCREEN_LOGDIR=$BASE/$LOCALRC_OLDNEW/screen-logs
LOGFILE=$BASE/$LOCALRC_OLDNEW/devstacklog.txt
VERBOSE=True
FIXED_RANGE=10.1.0.0/24
FIXED_NETWORK_SIZE=256
VIRT_DRIVER=$DEVSTACK_GATE_VIRT_DRIVER
SWIFT_REPLICAS=1
LOG_COLOR=False
PIP_USE_MIRRORS=False
export OS_NO_CACHE=True
EOF

    if [ "$DEVSTACK_CINDER_SECURE_DELETE" -eq "0" ]; then
        echo "CINDER_SECURE_DELETE=False" >>localrc
    fi

    if [ "$DEVSTACK_GATE_TEMPEST_COVERAGE" -eq "1" ] ; then
        echo "EXTRA_OPTS=(backdoor_port=0)" >>localrc
    fi

    if [ "$DEVSTACK_GATE_POSTGRES" -eq "1" ]; then
        echo "use_database postgresql" >>localrc
    fi

    if [ "$DEVSTACK_GATE_VIRT_DRIVER" == "openvz" ]; then
        echo "SKIP_EXERCISES=${SKIP_EXERCISES},volumes" >>localrc
        echo "DEFAULT_INSTANCE_TYPE=m1.small" >>localrc
        echo "DEFAULT_INSTANCE_USER=root" >>localrc

        echo "DEFAULT_INSTANCE_TYPE=m1.small" >>exerciserc
        echo "DEFAULT_INSTANCE_USER=root" >>exerciserc
    fi

    if [ "$DEVSTACK_GATE_TEMPEST" -eq "1" ]; then
        # We need to disable ratelimiting when running
        # Tempest tests since so many requests are executed
        echo "API_RATE_LIMIT=False" >> localrc
        # Volume tests in Tempest require a number of volumes
        # to be created, each of 1G size. Devstack's default
        # volume backing file size is 2G, so we increase to 5G
        # (apparently 4G is not always enough).
        #
        # NOTE(sdague): the 10G setting is far larger than should
        # be needed, however cinder tempest tests are currently
        # not cleaning up correctly, and this is a temp measure
        # to prevent it from blocking unrelated changes
        echo "VOLUME_BACKING_FILE_SIZE=10G" >> localrc
    fi

    if [ "$DEVSTACK_GATE_GRENADE" -eq "1" ]; then
        echo "DATA_DIR=/opt/stack/data" >> localrc
        echo "SWIFT_DATA_DIR=/opt/stack/data/swift" >> localrc
        if [ "$LOCALRC_OLDNEW" == "old" ]; then
            echo "GRENADE_PHASE=base" >> localrc
        else
            echo "GRENADE_PHASE=target" >> localrc
        fi
    else
        # Grenade needs screen, so only turn this off if we aren't
        # running grenade.
        echo "USE_SCREEN=False" >>localrc
    fi
}


if [ "$ZUUL_BRANCH" == "stable/diablo" ]; then
    export DEVSTACK_GATE_TEMPEST=0
fi

if [ "$DEVSTACK_GATE_GRENADE" -eq "1" ]; then
    cd $BASE/old/devstack
    setup_localrc "old" "$GRENADE_OLD_BRANCH"

    cat <<EOF >$BASE/grenade/localrc
BASE_RELEASE=old
BASE_RELEASE_DIR=$BASE/\$BASE_RELEASE
BASE_DEVSTACK_DIR=\$BASE_RELEASE_DIR/devstack
TARGET_RELEASE=new
TARGET_RELEASE_DIR=$BASE/\$TARGET_RELEASE
TARGET_DEVSTACK_DIR=\$TARGET_RELEASE_DIR/devstack
SAVE_DIR=\$BASE_RELEASE_DIR/save
EOF
fi

cd $BASE/new/devstack
setup_localrc "new" "$ZUUL_BRANCH"

# Make the workspace owned by the stack user
sudo chown -R stack:stack $BASE

if [ "$DEVSTACK_GATE_GRENADE" -eq "1" ]; then
    cd $BASE/grenade
    sudo -H -u stack ./grenade.sh
else
    echo "Running devstack"
    sudo -H -u stack ./stack.sh

    echo "Removing sudo privileges for devstack user"
    sudo rm /etc/sudoers.d/50_stack_sh

    echo "Running devstack exercises"
    sudo -H -u stack ./exercise.sh
fi

if [ "$DEVSTACK_GATE_TEMPEST" -eq "1" ]; then
    if [ ! -f "$BASE/new/tempest/etc/tempest.conf" ]; then
        echo "Configuring tempest"
        cd $BASE/new/devstack
        sudo -H -u stack ./tools/configure_tempest.sh
    fi
    cd $BASE/new/tempest
    if [[ "$DEVSTACK_GATE_TEMPEST_COVERAGE" -eq "1" ]] ; then
        echo "Starting coverage data collection"
        sudo -H -u stack python -m tools/tempest_coverage -c start --combine
    fi
    if [[ "$DEVSTACK_GATE_TEMPEST_FULL" -eq "1" ]]; then
        echo "Running tempest full test suite"
        sudo -H -u stack NOSE_XUNIT_FILE=nosetests-full.xml nosetests --logging-format '%(asctime)-15s %(message)s' --with-xunit -sv tempest
        echo "Running tempest/cli test suite"
        sudo -H -u stack NOSE_XUNIT_FILE=nosetests-cli.xml nosetests --logging-format '%(asctime)-15s %(message)s' --with-xunit -sv cli
    else
        echo "Running tempest smoke tests"
        sudo -H -u stack NOSE_XUNIT_FILE=nosetests-smoke.xml nosetests --logging-format '%(asctime)-15s %(message)s' --with-xunit -sv --attr=type=smoke tempest
    fi
    if [[ "$DEVSTACK_GATE_TEMPEST_COVERAGE" -eq "1" ]] ; then
        echo "Generating coverage report"
        sudo -H -u stack python -m tools/tempest_coverage -c report --html -o $BASE/new/tempest/coverage-report
    fi
else
    # Jenkins expects at least one nosetests file.  If we're not running
    # tempest, then write a fake one that indicates the tests pass (since
    # we made it past exercise.sh.
    cat > $WORKSPACE/nosetests-fake.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?><testsuite name="nosetests" tests="0" errors="0" failures="0" skip="0"></testsuite>
EOF
fi
