#!/usr/bin/env bash

PHASE="$1"; shift
VAR="var"
function usage() {
    fail "Usage: (setup|build|install) [--rebuild] [--primary-ip <ip-address> ][--host <host>] [--module <module>] [--var <env-file>]"
}
if [ -z "$PHASE" ] ; then usage; fi

while [ ! -z "$1" ]; do
    cmd="$1"; shift
    case $cmd in
        --rebuild*) REBUILD="true";;
        --host*) HOST=$1; shift;;
        --service*) SERVICE=$1; shift;;
        --var*) VAR=$1; shift;;
        *) usage;;
    esac
done

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/lib/tools.sh
source $DIR/env/${VAR}.sh
BRANCH="$(cd $DIR && git rev-parse --abbrev-ref HEAD)"
if [ ! -z "$SERVICE" ]; then
    SERVICES=($SERVICE)
fi

export PRIMARY_IP
if [ -z "$HOST" ]; then
    PRIMARY_IP="$(hostname --ip-address)"
elif [ -z "$PRIMARY_IP" ]; then
    PRIMARY_IP="${!HOST}"
fi

checkvar PRIMARY_IP
highlight "APPLYING BRANCH $BRANCH TO HOST $PRIMARY_IP: $PHASE"

checkvar SERVICES
for service in "${SERVICES[@]}"
do
    if [ -f "$DIR/lib/$service/include.sh" ]; then
     source "$DIR/lib/$service/include.sh"
    fi
done

if [ -z "$APPLICABLE_SERVICES" ]; then
    warn "NO SERVICES APPLICABLE"
    exit 0;
fi

DEDUPLICATED_APPLICABLE_SERVICES=$( for i in "${!APPLICABLE_SERVICES[@]}"; do printf "%s\t%s\n" "$i" "${APPLICABLE_SERVICES[$i]}"; done  | sort -k2 -k1n | uniq -f1 | sort -nk1,1 | cut -f2-  | paste -sd " " - )
APPLICABLE_SERVICES=($DEDUPLICATED_APPLICABLE_SERVICES)


echo "GOING TO APPLY IN ORDER: ${APPLICABLE_SERVICES[@]}"

declare BUILD_DIR="$DIR/build"
mkdir -p $BUILD_DIR
continue $? "COULD NOT CREATE BUILD DIR: $BUILD_DIR"

case $PHASE in
    setup*)
        mkdir -p $BUILD_DIR
        for service in "${APPLICABLE_SERVICES[@]}"
        do
            if (func_modified "setup_$service") || [ "$REBUILD" == "true" ]; then
                warn "[$(date)] SERVICE SETUP MODIFIED: $service"
                setup_$service
                continue $? "[$(date)] SETUP FAILED, SERVICE: $service"
                func_modified "setup_$service" "clear"
            fi
        done
    ;;
    build*)
        if [ "$REBUILD" == "true" ] && [ "$BUILD_DIR" != "/" ]; then
            echo "--REBUILD PURGING $BUILD_DIR"
            rm -rf $BUILD_DIR/**
        fi
        for service in "${APPLICABLE_SERVICES[@]}"
        do
            info "BUILDING SERVICE $service INTO $BUILD_DIR"

            if [ "$(type -t build_$service)" == "function" ]; then "build_$service"; fi
            func_modified "build_$service" "clear"

            if [ -d "$DIR/lib/$service" ]; then expand_dir "$DIR/lib/$service"; fi

        done
        highlight "APPLIED IN $BUILD_DIR"
    ;;
    install*)
        let num_services_affected=0
        for service in "${APPLICABLE_SERVICES[@]}"
        do
            should_restart=0
            should_install=0

            #build and determine the whether the service was affected
            info "BUILDING SERVICE: $service"
            chk1=$(checksum $BUILD_DIR)

            if [ "$(type -t build_$service)" == "function" ]; then "build_$service"; fi
            continue $? "[$(date)] FAILED TO BUILD SERVICE $servie"

            func_modified "build_$service" "clear"


            if [ -d "$DIR/lib/$service" ]; then expand_dir "$DIR/lib/$service"; fi
            continue $? "[$(date)] FAILED TO EXPAND SERVICE $servie"

            chk2=$(checksum $BUILD_DIR)
            if [ "$chk1" == "$chk2" ]; then
                info "- no diff in build: $chk2"
                if [ "$(type -t stop_$service)" == "function" ]; then
                    if (func_modified "stop_$service") ; then should_restart=1; fi
                fi
                if [ "$(type -t start_$service)" == "function" ]; then
                    if (func_modified "start_$service") ; then should_restart=1; fi
                fi
                if [ "$(type -t install_$service)" == "function" ]; then
                    if (func_modified "install_$service") ; then should_restart=1; should_install=1; fi
                fi
            else
                should_restart=1
                should_install=1
            fi

            if [ $should_restart -eq 1 ]; then
                let num_services_affected=(num_services_affected+1)

                #service must be stopped before the real build into / becuase jars or other runtime artifact may be modified
                if [ "$(type -t stop_$service)" == "function" ]; then
                    warn "[$(date)] STOPPING $service"
                    "stop_$service"
                    func_modified "stop_$service" "clear"
                fi

                #now apply the build result to the root of the filesystem and call install_
                if [ $should_install -eq 1 ]; then
                    diff_cp "$BUILD_DIR" "/" "warn"
                    warn "[$(date)] INSTALLING SERVICE $service ($chk1 -> $chk2)"
                    if [ "$(type -t install_$service)" == "function" ]; then "install_$service"; fi
                    continue $? "[$(date)] FAILED TO INSTALL SERVICE $service"
                    func_modified "install_$service" "clear"
                fi

                #finally start the services
                if [ "$(type -t start_$service)" == "function" ]; then
                    warn "[$(date)] STARTING $service"
                    "start_$service"
                    continue $? "[$(date)] FAILED TO START $service"
                    func_modified "start_$service" "clear"
                fi
            fi


        done
        if [ "$num_services_affected" == "0" ]; then
            success "[$(date)] NO SERVICES ON THIS HOST WERE AFFECTED"
        else
            success "[$(date)] APPLIED IN /"
        fi
    ;;
    *)
        fail "POSSIBLE PHASES: build, install"
    ;;
esac

