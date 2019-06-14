#!/bin/bash

# ----------------------------------------
# JENKINS DEPLOYMENT SCRIPT FOR PANLOGIC
# WRITTEN BY: ALEXANDER GAILEY-WHITE
# ----------------------------------------

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

# Date string for database dump suffix
DATE=`date +%Y%m%d-%H%M%S`

# Current directory for sourcing
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]];
	then
		DIR="$PWD";
fi

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

# Override the DEST_WEBROOT_PATH with the Jenkins workspace
DEST_WEBROOT_PATH=$WORKSPACE_PATH

# Environment we are building (dev, stage, prod, etc.)
JOB_ENV=`echo $1 | cut -d'-' -f2`

echo "Build '$PROJECT_NAME'"
echo "--------------------------------------------------------------------------------"

IMPORT=0

# Database locations
SRC_DUMP_PATH="$DIR/project/$PROJECT_NAME/backup"
SRC_DUMP_FILE="$SRC_DUMP_PATH/$PROJECT_NAME-backup-$DATE.sql"
DEST_DUMP_FILE="$DEST_DUMP_PATH/$PROJECT_NAME-backup-$DATE.sql"

SRC_LAST_DUMP_NAME=`ls -t $SRC_DUMP_PATH | head -1`
DEST_LAST_DUMP_NAME=`$SSH_CONN "ls -t $DEST_DUMP_PATH | head -1"`

echo -n "Test SSH connection... "
$SSH_CONN exit

if [ "$?" -eq "0" ]
	then
		echo "OK"
	else
        echo "FAILED"

		if [ ! -e "$DEST_IDENTITY" ];
			then
				HOSTNAME='alexgw@gmail.com'
				ssh-keygen -t rsa -C "$HOSTNAME" -f "$DEST_IDENTITY" -P ""
				echo "--------------------------------------------------------------------------------"
				cat $DEST_IDENTITY.pub
				echo "--------------------------------------------------------------------------------"
				echo "sudo su jenkins -c \"ssh-copy-id -i $DEST_IDENTITY $DEST_SSH_USER@$DEST_HOST\""
				echo "--------------------------------------------------------------------------------"
				eval $(ssh-agent -s)
				ssh-add ~/.ssh/$PROJECT_NAME
				ssh-copy-id -i $DEST_IDENTITY $DEST_SSH_USER@$DEST_HOST

				$SSH_CONN exit
				if [ ! "$?" -eq "0" ]
					then
						echo "FAILED"
						exit 1
				fi
		fi
fi

# Create source dump directory
EXISTS=`if test -d $SRC_DUMP_PATH; then echo \"1\"; else echo \"0\"; fi`

if [ "$EXISTS" != "1" ]
	then
		echo -n "Creating source dump path '$SRC_DUMP_PATH'... " \
			&& mkdir -m 770 -p $SRC_DUMP_PATH

		if [ "$?" -eq "0" ]
			then
				echo "OK"
			else
				echo "FAILED"
		fi
fi

# Create destination dump directory
EXISTS=`$SSH_CONN \
	"if test -d $DEST_DUMP_PATH; then echo \"1\"; else echo \"0\"; fi"`

if [ "$EXISTS" != "1" ]
	then
		$SSH_CONN \
			"echo -n \"Creating destination dump path '$DEST_DUMP_PATH'... \" \
			&& mkdir -m 750 -p $DEST_DUMP_PATH"

		if [ "$?" -eq "0" ]
			then
				echo "OK"
			else
				echo "FAILED"
		fi
fi

# Link .env to new build
echo -n "Set .env for build... "
cd $WORKSPACE_PATH && ln -snf $ENV_FILE .env

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

				echo -n "Compare dump... "
                #mkdir -m 750 -p $SRC_DUMP_PATH
                LAST_DUMP_NAME=`ls -t $SRC_DUMP_PATH | head -1`
				IMPORT=0

				# Compare the new dump size, with the most recent project backup
				# We are checking the file size, rather than the checksum.
				# Due to the dump containing a creation timestamp
				if [ ! -z $SRC_LAST_DUMP_NAME ] && [ -f "$SRC_DUMP_PATH/$SRC_LAST_DUMP_NAME" ];
					then
						A=`wc -c $SRC_DUMP_PATH/$SRC_LAST_DUMP_NAME | cut -d' ' -f1`
						B=`$SSH_CONN "wc -c $DEST_DUMP_PATH/$DEST_LAST_DUMP_NAME | cut -d' ' -f1"`

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

                	# SCP dump from destination
					echo "SCP $SRC_DUMP_FILE"
					echo "<-- $DEST_DUMP_FILE "
					scp -i $DEST_IDENTITY \
						$DEST_SSH_USER@$DEST_HOST:$DEST_DUMP_FILE \
						$SRC_DUMP_FILE

					if [ "$?" -eq "0" ]
						then

							# Import the copied dump
							echo -n "Import dump to workspace $SRC_DUMP_FILE ... " \
								&& mysql $SRC_DATABASE_NAME < $SRC_DUMP_FILE

							if [ "$?" -eq "0" ]
								then
									echo "OK"

									# Delete the dump
									echo -n "Clean up ... " \
										&& rm -rf $SRC_DUMP_FILE

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

echo "--------------------------------------------------------------------------------"
echo "FAILED";
exit 1;