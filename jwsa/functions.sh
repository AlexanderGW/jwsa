#!/bin/bash

function remote_cmd() {
    $SSH_CONN $1
}

# ------------------------------------------------------------------------

function remote_test_connect() {
    echo -n "Test SSH connection... "
    remote_cmd exit
}

# ------------------------------------------------------------------------

function create_local_path_if_not_exists() {
    if [ $2 -eq 0 ]
      then
        local PERMS="750"
    else
        local PERMS=$2
    fi

    local EXISTS=`if test -d $1; then echo \"1\"; else echo \"0\"; fi`

    if [ "$EXISTS" != "1" ]
        then
            mkdir -m $PERMS -p $1
            if [ "$?" -eq "0" ]
                then
                    echo "OK"
                    return 0
                else
                    echo "FAILED"
                    return 1
            fi
    fi
}

function create_remote_path_if_not_exists() {
    if [ $2 -eq 0 ]
      then
        local PERMS="750"
    else
        local PERMS=$2
    fi

    local EXISTS=`if test -d $1; then echo \"1\"; else echo \"0\"; fi`

    if [ "$EXISTS" != "1" ]
        then
            remote_cmd \
                "echo -n \"Creating remote path '$1'... \" \
                && mkdir -m $PERMS -p $1"

            if [ "$?" -eq "0" ]
                then
                    echo "OK"
                    return 0
                else
                    echo "FAILED"
                    return 1
            fi
    fi
}

# ------------------------------------------------------------------------

function set_local_link_from_relative() {
    echo "LINK $1"
    echo "--> $2 "
    cd $3 && ln -snf $2 $1
}

function set_local_link_in_workspace() {
    set_local_link_from_relative $1 $2 $WORKSPACE_PATH
}

function set_local_link() {
    echo "LINK $1"
    echo "--> $2 "
    ln -snf $2 $1
}

# ------------------------------------------------------------------------

function set_remote_link_from_relative() {
    echo "LINK $1"
    echo "--> $2 "
    cd $3 && ln -snf $2 $1
}

function set_remote_link_in_workspace() {
    set_local_link_from_relative $1 $2 $WORKSPACE_PATH
}

function set_remote_link() {
    echo "LINK $1"
    echo "--> $2 "
    ln -snf $2 $1
}

# ------------------------------------------------------------------------

function copy_to_remote() {
    echo "SCP $1"
    echo "--> $2 "
    scp -i $DEST_IDENTITY \
        $1 \
        $DEST_SSH_USER@$DEST_HOST:$2
}

function copy_from_remote() {
    echo "SCP $1"
    echo "<-- $2 "
    scp -i $DEST_IDENTITY \
        $DEST_SSH_USER@$DEST_HOST:$1 \
        $2
}

# ------------------------------------------------------------------------

function sync_to_remote() {
    echo "RSYNC $1"
    echo "--> $2 "
    rsync $RSYNC_FLAGS "ssh -i $DEST_IDENTITY" \
        $1 \
        $DEST_SSH_USER@$DEST_HOST:$2
}

function sync_to_remote_sudo() {
    echo "RSYNC $1"
    echo "--> $2 "
    rsync $RSYNC_FLAGS "ssh -i $DEST_IDENTITY" --rsync-path="sudo rsync" \
        $1 \
        $DEST_SSH_USER@$DEST_HOST:$2
}

function sync_from_remote() {
    echo "RSYNC $1"
    echo "<-- $2 "
    scp -i $DEST_IDENTITY \
        $DEST_SSH_USER@$DEST_HOST:$1 \
        $2
}

# ------------------------------------------------------------------------

function mysql_database_local_import() {
    echo "Import dump (local)"
    echo "$2"
    echo "-->"
    echo "'$1'"
	mysql $1 < $2
}

function mysql_database_local_export() {
    echo "Exporting database (local)"
    echo "'$1'"
    echo "-->"
    echo "$2"
	mysqldump $1 > $2
}

function mysql_database_remote_import() {
    echo "Import dump (remote)"
    echo "$2"
    echo "-->"
    echo "'$1'"
	remote_cmd mysql $1 < $2
}

function mysql_database_remote_export() {
    echo "Exporting database (remote)"
    echo "'$1'"
    echo "-->"
    echo "$2"
	remote_cmd mysqldump $1 > $2
}

# ------------------------------------------------------------------------

function local_cli_cmd() {
    cd $WORKSPACE_PATH && $CLI_PHAR $1
}

function remote_cli_cmd() {
    remote_cmd cd $WORKSPACE_PATH && $CLI_PHAR $1
}

# ------------------------------------------------------------------------

function restart_remote_service() {
    $SSH_CONN \
        "echo \"Restart service '$1'...\" \
        && sudo service $1 restart"
}