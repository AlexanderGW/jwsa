#!/bin/bash

if [ $# -lt 2 ]
  then
    echo "Required arguments; PROJECT_NAME, WORKSPACE, ENV_FILE"
    exit 1
fi

# $1 = PROJECT_NAME
if ! [[ "$1" =~ ^[a-zA-Z0-9_\-]+$ ]]
    then
        echo "Invalid PROJECT_NAME"
        exit 1
fi
PROJECT_NAME=$1

# $2 = WORKSPACE
if ! [ -d "$2" ]
    then
        echo "Invalid WORKSPACE"
        exit 1
fi
WORKSPACE_PATH=$2

# $3 = ENV_FILE
if ! [ -e "$3" ]
    then
        echo "Invalid ENV_FILE"
        exit 1
fi
ENV_FILE=$3

# ------------------------------------------------------------------------

# Current directory for sourcing
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]];
	then
		DIR="$PWD";
fi

# Source JWSA variables and functions
echo "Sourcing JWSA variables"
. "$DIR/jwsa/variables.sh"
echo "Sourcing JWSA functions"
. "$DIR/jwsa/functions.sh"

# ------------------------------------------------------------------------

# Source the projects deployment variables
echo -n "Sourcing project script '$PROJECT_NAME'... "
echo $DIR/project/$PROJECT_NAME/variables.sh
. "$DIR/project/$PROJECT_NAME/variables.sh"

if [ -z ${TYPE+x} ];
	then
		echo "FAILED"
		exit 1;
	else
		echo "OK"
fi

# Override the webroot with the Jenkins workspace
WEBROOT=$WORKSPACE_PATH

echo "Build '$PROJECT_NAME'"
echo "------------------------------------------------------------------------"

IMPORT=0

# Database locations
SRC_DUMP_PATH="$DIR/project/$PROJECT_NAME/backup"
SRC_DUMP_FILE="$SRC_DUMP_PATH/$PROJECT_NAME-backup-$DATE.sql"
DEST_DUMP_FILE="$DEST_DUMP_PATH/$PROJECT_NAME-backup-$DATE.sql"

SRC_LAST_DUMP_NAME=`ls -t $SRC_DUMP_PATH | head -1`
DEST_LAST_DUMP_NAME=`$SSH_CONN "ls -t $DEST_DUMP_PATH | head -1"`

# Test remote SSH connection
remote_test_connect

if [ "$?" -eq "0" ]
    then
        echo "OK"
    else
        echo "FAILED"


        if [ ! -e "$DEST_IDENTITY" ];
            then
                HOSTNAME='example.com'
                ssh-keygen -t rsa -C "$HOSTNAME" -f "$DEST_IDENTITY" -P ""
                echo "------------------------------------------------------------------------"
                cat $DEST_IDENTITY.pub
                echo "------------------------------------------------------------------------"
                echo "sudo su jenkins -c \"ssh-copy-id -i $DEST_IDENTITY $DEST_SSH_USER@$DEST_HOST\""
                echo "------------------------------------------------------------------------"
                eval $(ssh-agent -s)
                ssh-add ~/.ssh/$PROJECT_NAME
                ssh-copy-id -i $DEST_IDENTITY $DEST_SSH_USER@$DEST_HOST

                remote_test_connect

                if [ ! "$?" -eq "0" ]
                    then
                        echo "FAILED"
                        exit 1
                fi
        fi
fi

# Create local dump path
create_local_path_if_not_exists $SRC_DUMP_PATH 750

# Create destination database dump path
create_remote_path_if_not_exists $DEST_DUMP_PATH 750

# Link .env to new build
set_local_link_in_workspace .env $ENV_FILE

if [ "$?" -eq "0" ]
	then
		echo "OK"

		# Sync database from the destination env, to the workspace env
		$SSH_CONN \
			"echo -n \"Dump environment database... \" \
			&& mysqldump $DEST_DATABASE_NAME > $DEST_DUMP_FILE"

		if [ "$?" -eq "0" ]
			then
				echo "OK"

				echo "Compare dump... "
                create_local_path_if_not_exists $SRC_DUMP_PATH 750
                LAST_DUMP_NAME=`ls -t $SRC_DUMP_PATH | head -1`
				IMPORT=0

				# Compare the new dump size, with the most recent project backup
				# We are checking the file size, rather than the checksum.
				# Due to the dump containing a creation timestamp
				if [ ! -z $SRC_LAST_DUMP_NAME ] && [ -f "$SRC_DUMP_PATH/$SRC_LAST_DUMP_NAME" ];
					then
						A=`wc -c $SRC_DUMP_PATH/$SRC_LAST_DUMP_NAME | cut -d' ' -f1`
						B=`remote_cmd "wc -c $DEST_DUMP_PATH/$DEST_LAST_DUMP_NAME | cut -d' ' -f1"`

						if [ "$A" == "$B" ]
							then
								echo "NO CHANGE"
							else
								echo "CHANGED"
								IMPORT=1
						fi
					else
						echo "NONE"
						IMPORT=1
				fi

				# Download the dump, and import it.
                if [ "$IMPORT" == "1" ]
                	then

                	# Copy remote dump to local dump path
					copy_from_remote $DEST_DUMP_FILE $SRC_DUMP_FILE

					if [ "$?" -eq "0" ]
						then

							# Import the copied dump
                            mysql_database_local_import $SRC_DATABASE_NAME $SRC_DUMP_FILE

							if [ "$?" -eq "0" ]
								then
									echo "OK"

									# Delete the dump
									echo -n "Clean up ... " \
										&& rm $SRC_DUMP_FILE

									if [ "$?" -eq "0" ]
										then
											echo "OK"
										else
											echo "FAILED"
									fi
								else
									echo "FAILED"
									exit 1
							fi
						else
							echo "FAILED"
							exit 1
					fi
				fi

                # Source the deploy script (drupal7, drupal8, wordpress, etc...)
                echo "Sourcing build script '$TYPE'"
                . "$DIR/build/$TYPE.sh"
			else
				echo "FAILED"
		fi
	else
		echo "FAILED"
fi

echo "------------------------------------------------------------------------"
echo "FAILED";
exit 1;