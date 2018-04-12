#!/usr/bin/env bash

fail() {
    message="$1"
    red='\033[0;31m'
    nc='\033[0m'
    echo -e "${red}$message $nc"
    echo ""
    exit 1;
}

warn() {
    message="$1"
    blue='\033[93m'
    nc='\033[0m'
    echo -e "${blue}$message $nc"
}

info() {
    message="$1"
    blue='\033[96m'
    nc='\033[0m'
    echo -e "${blue}$message $nc"
}

success() {
    message="$1"
    green='\033[92m'
    nc='\033[0m'
    echo -e "${green}$message $nc"
}

highlight() {
    message="$1"
    bold='\033[01m'
    nc='\033[0m'
    echo -e "${bold}$message $nc"
}

continue() {
    result="$1"
    message="$2"
    if [ $result -ne 0 ]; then
        fail "$message"
    fi
}

checkvar() {
    expr="echo \$$1"
    value="$(eval $expr)"
    if [ -z "$value" ]; then fail "$1 variable not specified"; fi
}

required() {
    module="$1"
    if [ ! -z "$2" ]; then
        expr="echo \$$2"
        value="$(eval $expr)"
        if [ ! -z "$value" ]; then module=""; fi
    fi
    if [ ! -z "$module" ]; then
        source "$( dirname "${BASH_SOURCE[0]}" )/$module/include.sh"
    fi
}

checksum() {
    if [ -d "$1" ]; then
        if [ "$1" == ".git" ]; then
            echo "0"
        elif [ -z "$(command -v md5sum)" ]; then
            find $1 -type f -exec md5 {} \; | sort -k 2 | md5
        else
            find $1 -type f -exec md5sum {} \; | sort -k 2 | md5sum
        fi
    elif [ -f "$1" ]; then
        #TODO add file permissions to the hash (and use it recursively for directory)
        if [ -z "$(command -v md5sum)" ]; then cat $1 | md5; else cat $1 | md5sum; fi
    fi
}

func_modified() {
    checkvar BUILD_DIR
    func_name="$1"
    clear_flag="$2"
    if [ "$(type -t $func_name)" == "function" ]; then
        if [ -z "$(command -v md5sum)" ]; then
            def_hash=$(type $func_name | md5)
        else
            def_hash=$(type $func_name | md5sum)
        fi
        def_hash_file="$BUILD_DIR/_$func_name"
        if [ -f "$def_hash_file" ]; then
            prev_hash=$(cat "$def_hash_file")
        fi
        if [ ! -z "$clear_flag" ]; then
            echo "$def_hash" > "$def_hash_file"
        elif [ "$def_hash" != "$prev_hash" ]; then
            return 0
        fi
    fi
    return 1
}

download() {
    url=$1
    file_name="$(basename $1)"
    dest_dir=$2
    local_tarball="$dest_dir/$(basename $url)"
    local="$dest_dir/$file_name"
    if [ ! -f "$local" ]; then
        info "Downloading $(basename $url)..."
        mkdir -p $(dirname $local)
        curl -s "$url" > "${local}.tmp"
        mv "${local}.tmp" "$local"
    fi
}

clone() {
    url=$1
    dest_dir=$2
    branch=$3
    if [ ! -d "$dest_dir" ]; then
        git clone "$url" $dest_dir
    fi
    cd "$dest_dir"
    git checkout "$branch"

}

expand() {
    leadsymbol="$1"
    env=`printenv | cut -d= -f1 | paste -sd "," -`
    params=$(echo $env | tr "," "\n")
    declare line
    expand_line() {
        for varname in ${params[@]}; do
            if [[ $line = *"$varname"* ]]; then
                value="${!varname//\\/_=|=_}" #backslashes in variables need to be masked before the replacement
                line="$( echo "$line" | sed -e "s^$leadsymbol$varname^$value^g" | sed "s/_=|=_n/\\`echo -e '\n\r'`/g" | sed "s/_=|=_/\\`echo -e '\\'`/g")"
            fi
        done
        printf "%s\n" "$line"
    }
    while IFS= read -r line; do expand_line; done; expand_line
}

expand_dir() {
    shells=(".sh" ".bat" ".bash" ".zsh")
    artifacts=(".jar" ".tar" ".war" ".so" ".exe" ".gz"  ".tgz" ".7z" ".bz2" ".rar" ".zip" ".zipx")
    for file in $1/$2/*; do
        filename=$(basename "$file")
        if [ -f "$file" ] && [ ! -z "$2" ]; then
            mkdir -p "$BUILD_DIR/$2"
            is_artifact=0
            for a in "${artifacts[@]}"; do if [[ $filename == *"$a" ]]; then is_artifact=1; break; fi; done
            is_shell=0
            for a in "${shells[@]}"; do if [[ $filename == *"$a" ]]; then is_shell=1; break; fi; done
            if [[ is_artifact -eq 1 ]]; then
                echo "[ARCHIVE ] $2/$filename"
                cat "$file" > "$BUILD_DIR/$2/$filename"
            elif [[ is_shell -eq 1 ]]; then
                echo "[ SCRIPT ] $2/$filename"
                cat "$file" | expand '\$\$' > "$BUILD_DIR/$2/$filename"
            else
                echo "[TEMPLATE] $2/$filename"
                cat "$file" | expand '\$' > "$BUILD_DIR/$2/$filename"
            fi
            continue $? "Could process file $FILE"
            #the chmod with reference file works only in POSIX so muting for OSX
            chmod --reference="$file" "$BUILD_DIR/$2/$filename" > /dev/null 2>&1
        elif [ -d "$file" ]; then
            expand_dir "$1" "$2/$filename"
        fi
    done
}


diff_cp() {
    for src_file in $1/*; do
        filename=$(basename "$src_file")
        dest_file="$2/$filename"
        if [ -d "$src_file" ]; then
            if [ "$src_file" != ".git" ]; then
                mkdir -p "$dest_file"
                diff_cp "$src_file" "$dest_file" "$3"
            fi
        elif [ -f "$src_file" ]; then
            #TODO if [ -L "$src_file" ]; then create ln and calculate the target path instead cp; fi
            if [ ! -f "$dest_file" ] || [ "$(checksum $src_file)" != "$(checksum $dest_file)" ]; then
                if [ "$3" == "info" ]; then info "$dest_file"; fi
                if [ "$3" == "warn" ]; then warn "$dest_file"; fi
                mkdir -p "$(dirname "$dest_file")"
                cp -f "$src_file" "$dest_file"
            fi
        fi
    done
}

git_local_revision() {
    branch=$(git rev-parse --abbrev-ref HEAD)
    git rev-parse $branch
}

git_remote_revision() {
    git remote update &> /dev/null
    branch=$(git rev-parse --abbrev-ref HEAD)
    git rev-parse origin/$branch
}


git_clone_or_update() {
    GIT_URL="$1"
    LOCAL_DIR="$2"
    BRANCH="$3"
    checkvar BRANCH
    checkbranch() {
        cd "$LOCAL_DIR"
        if [ $BRANCH != "$(git rev-parse --abbrev-ref HEAD)" ]; then
            git checkout $BRANCH
            continue $? "COULD NOT EXECUTE: git checkout \"$BRANCH\""
        fi
    }
    if [ ! -d "$LOCAL_DIR/.git" ]; then
        mkdir -p "$LOCAL_DIR"
        git clone "$GIT_URL" "$LOCAL_DIR"
        continue $? "COULD NOT EXECUTE: git clone \"$GIT_URL\"  \"$LOCAL_DIR\""
        checkbranch
        return 1
    else
        checkbranch
        echo "CHECKING FOR UPDATES IN: $LOCAL_DIR"
        if [ "$(git_local_revision)" != "$(git_remote_revision)" ]; then
            git pull
            continue $? "COULD NOT PULL LATEST CHANGES FROM $GIT_URL INTO $LOCAL_DIR"
            return 2
        else
            return 0
        fi
    fi
}