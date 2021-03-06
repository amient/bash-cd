#!/usr/bin/env bash

checkvar PROMETHEUS_SERVERS
checkvar PROMETHEUS_DATA_DIR
checkvar PROMETHEUS_RETENTION_DAYS
export PROMETHEUS_RETENTION="${PROMETHEUS_RETENTION_DAYS}d"
checkvar ENV

for prom_server in "${PROMETHEUS_SERVERS[@]}"
do
   export PROMETHEUS_URL="http://$prom_server:9090"
   if [ "$prom_server" == "$PRIMARY_IP" ]; then
    apply "prometheus"
    if [ ! -z "$KAFKA_SERVERS" ]; then
        export KAFKA_PROMETHEUS_TARGETS=""
        for kafka_host in ${KAFKA_SERVERS[@]}
        do
           KAFKA_PROMETHEUS_TARGETS="${KAFKA_PROMETHEUS_TARGETS} ${kafka_host}:7071,"
        done
    fi
    export SOME_APP_TARGETS=""
    for some_app_host in ${SOME_APP_SERVERS[@]}
    do
       SOME_APP_TARGETS="${SOME_APP_TARGETS} ${some_app_host}:7081,"
    done
   fi

#   export PROMETHEUS_NODE_TARGETS=""
#   for h in ${ALL_HOSTS[@]}; do
#    PROMETHEUS_NODE_TARGETS="${PROMETHEUS_NODE_TARGETS} ${h}:9100,"
#   done
done

build_prometheus() {
    export ENV
    VERSION=2.4.3
    DOWNLOAD="prometheus-$VERSION.linux-amd64"
    download "https://github.com/prometheus/prometheus/releases/download/v$VERSION/$DOWNLOAD.tar.gz" $BUILD_DIR/opt/
    continue $? "failed to download prometheus"
    SHA256="$(sha256sum "$BUILD_DIR/opt/$DOWNLOAD.tar.gz")"
    if [[ "$SHA256"  != 3aa063498ab3b4d1bee103d80098ba33d02b3fed63cb46e47e1d16290356db8a* ]]; then
     rm "$BUILD_DIR/opt/$DOWNLOAD.tar.gz"
     fail "prometheus checksum failed"
    fi
    cat > $BUILD_DIR/etc/prometheus/$ENV.yml <<- EOM
- job_name: '$ENV-some-app'
  scrape_interval: 15s
  static_configs:
  - targets: [$SOME_APP_TARGETS]
    labels:
      env: $ENV
EOM
  systemctl is-active --quiet prometheus
}

install_prometheus() {
    cat > /etc/prometheus/prometheus.yml <<- EOM
global:
  scrape_interval: 5s

scrape_configs:
EOM
    cat /etc/prometheus/prod1.yml >> /etc/prometheus/prometheus.yml
    cat /etc/prometheus/stag.yml >> /etc/prometheus/prometheus.yml
    cd /opt
    if [ ! -d "/opt/$DOWNLOAD" ]; then
            tar xvf "/opt/$DOWNLOAD.tar.gz"
            continue $? "could not untar prometheus download"
    fi
    ln -sf /opt/$DOWNLOAD prometheus

    id -u prometheus > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        useradd --no-create-home --shell /bin/false prometheus
        useradd --no-create-home --shell /bin/false node_exporter
    fi
    mkdir -p $PROMETHEUS_DATA_DIR
    chown -R prometheus:prometheus $PROMETHEUS_DATA_DIR
    continue $? "failed to create prometheus user"
    chown prometheus:prometheus /opt/prometheus/prometheus
    chown prometheus:prometheus /opt/prometheus/promtool
    cp -r /opt/prometheus/consoles /etc/prometheus
    cp -r /opt/prometheus/console_libraries /etc/prometheus
    chown -R prometheus:prometheus /etc/prometheus
    systemctl daemon-reload
    systemctl enable prometheus
}

start_prometheus() {
    systemctl start prometheus
    wait_for_endpoint http://localhost:9090 302 15
}

stop_prometheus() {
    systemctl stop prometheus
}

