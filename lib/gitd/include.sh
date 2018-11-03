#!/usr/bin/env bash

checkvar GIT_SERVER
checkvar GIT_SERVER_DATA_DIR

if [ "$GIT_SERVER" == "$PRIMARY_IP" ]; then
    export GIT_SERVER_DATA_DIR
    APPLICABLE_SERVICES+=("gitd")
fi

setup_gitd() {
    apt-get -y update --fix-missing
    apt-get -y install git
}

install_gitd() {
    id -u git > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        useradd --no-create-home --shell /bin/false git
    fi
    mkdir -p "$GIT_SERVER_DATA_DIR"
    continue $? "could not create git data root directory: $GIT_SERVER_DATA_DIR"
    chown -R git:git $GIT_SERVER_DATA_DIR
}

start_gitd() {
    systemctl start git-daemon
    wait_for_ports localhost:9418
    function create_gitd_repo() {
        name="$1"
        dir="$GIT_SERVER_DATA_DIR/$name.git"
        if [ ! -d $dir ]; then
            echo "initializing git repository: $dir"
            mkdir -p $dir
            cd $dir
            git init --bare --shared
            chown -R git:git $dir
        fi
    }
    create_gitd_repo bash-cd
}

function stop_gitd() {
    systemctl stop git-daemon
}

