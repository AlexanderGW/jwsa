#!/bin/bash

# ----------------------------------------
# JENKINS DEPLOYMENT SCRIPT FOR PANLOGIC
# WRITTEN BY: ALEXANDER GAILEY-WHITE
# ----------------------------------------

if [ $# -lt 3 ]
  then
    echo "Required arguments; PROJECT_NAME, WORKSPACE_PATH, BUILD_ID"
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
        echo "Invalid WORKSPACE_PATH"
        exit 1
fi
WORKSPACE_PATH=$2

# $3 = BUILD_ID
if ! [[ "$3" =~ ^[0-9]+$ ]]
    then
        echo "Invalid BUILD_ID"
        exit 1
fi
BUILD_ID=$3

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
. "$DIR/project/$PROJECT_NAME/variables.sh"

if [ -z ${TYPE+x} ];
	then
		echo "FAIL"
		exit 1;
	else
		echo "OK"
fi

JOB_ENV=`echo $1 | cut -d'-' -f2`

echo "Deploy '$PROJECT_NAME' (build: $BUILD_ID)"
echo "-----------------------------------------------"

declare -a WEBSERVERS=("apache" "nginx")
declare -a WEBSERVER_CONF_DIRS=("sites-available" "conf.d")

# Get last successful build ID for the project
LAST_BUILD_ID=`curl --user vagrant:vagrant http://jenkins.test:8080/job/$1/lastSuccessfulBuild/buildNumber`
#LAST_BUILD_ID=`wget -qO- http://jenkins.test:8080/job/$1/lastSuccessfulBuild/buildNumber --user=\\\"vagrant:vagrant\\\"`

# Database locations
SRC_DUMP_FILE="$WORKSPACE_PATH/$PROJECT_NAME-predeploy-$BUILD_ID.sql"
DEST_DUMP_FILE="$DEST_DUMP_PATH/$PROJECT_NAME-predeploy-$BUILD_ID.sql"

# Test SSH connect
echo -n "Test SSH connection..."
$SSH_CONN exit

if [ "$?" -eq "0" ]
	then
		echo "OK"
	else

		if [ ! -e "$DEST_IDENTITY" ];
			then
				HOSTNAME='alexgw@gmail.com'
				ssh-keygen -t rsa -C "$HOSTNAME" -f "$DEST_IDENTITY" -P ""
				echo "-------------------------------------------------------------------------------------------"
				cat $DEST_IDENTITY.pub
				echo "-------------------------------------------------------------------------------------------"
				echo "sudo su jenkins -c \"ssh-copy-id -i $DEST_IDENTITY $DEST_SSH_USER@$DEST_HOST\""
				echo "-------------------------------------------------------------------------------------------"
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

# Create dump directory
EXISTS=`$SSH_CONN \
	"if test -d $DEST_DUMP_PATH; then echo \"1\"; fi"`

if [ "$EXISTS" != "1" ]
	then
		$SSH_CONN \
			"echo -n \"Creating dump path '$DEST_DUMP_PATH'... \" \
			&& mkdir -m 755 -p $DEST_DUMP_PATH"

		if [ "$?" -eq "0" ]
			then
				echo "OK"
			else
				echo "FAILED"
		fi
fi

# Create assets directory
EXISTS=`$SSH_CONN \
	"if test -d $DEST_ASSET_PATH; then echo \"1\"; fi"`

if [ "$EXISTS" != "1" ]
	then
		$SSH_CONN \
			"echo -n \"Creating asset path '$DEST_ASSET_PATH'... \" \
			&& install -d -m 0775 -o $DEST_WEB_USER -g $DEST_WEB_USER $DEST_ASSET_PATH"

		if [ "$?" -eq "0" ]
			then
				echo "OK"
			else
				echo "FAILED"
		fi
fi

# Make build path
$SSH_CONN \
	"echo -n \"Creating build path '$DEST_BUILD_PATH'... \" \
	&& mkdir -m 775 -p $DEST_BUILD_PATH"

if [ "$?" -eq "0" ]
	then
		echo "OK"
	else
		echo "FAILED"
fi

# Copy conf file(s)
UPDATED=0
echo "RSYNC web configuration... "
for SERVICE_NAME in "${WEBSERVERS[@]}"
	do
		EXISTS=`$SSH_CONN \
			"if test -d /etc/$SERVICE_NAME; then echo \"1\"; fi"`

		if [ "$EXISTS" == "1" ]
			then
				for DIR_NAME in ${WEBSERVER_CONF_DIRS[@]}
					do
						$SSH_CONN \
							"sudo ls -l /etc/$SERVICE_NAME/$DIR_NAME"

						if [ "$?" -eq "0" ]
							then
								echo "RSYNC $DIR/project/$PROJECT_NAME/$SERVICE_NAME --> /etc/$SERVICE_NAME/$DIR_NAME"
								rsync $RSYNC_FLAGS "ssh -i $DEST_IDENTITY" \
									$DIR/project/$PROJECT_NAME/$SERVICE_NAME/* \
									$DEST_SSH_USER@$DEST_HOST:/etc/$SERVICE_NAME/$DIR_NAME

								if [ "$?" -eq "0" ]
									then
										echo "OK"
										UPDATED=1

										if [ "$DIR_NAME" == "sites-available" ]
											then
												$SSH_CONN \
													"sudo ln -sfn /etc/$SERVICE_NAME/$DIR_NAME/$PROJECT_NAME.conf /etc/$SERVICE_NAME/sites-enabled/$PROJECT_NAME.conf"

												if [ "$?" -eq "0" ]
													then
														break 2
												fi
										fi
									else
										echo "FAILED"
								fi

								echo ""
						fi
					done
		fi
	done

echo "OK"
echo ""

# Restart specified services
if [ "$UPDATED" == "1" ];
	then
		for SERVICE in ${DEST_SERVICES[@]}
		do
			$SSH_CONN \
				"echo \"Restart service '$SERVICE'...\" \
				&& sudo service $SERVICE restart"

			if [ "$?" -eq "0" ]
				then
					echo "OK"
				else
					echo "FAILED"
			fi
		done
fi

echo ""

# Source the deploy script (drupal7, drupal8, wordpress, etc...)
echo "Sourcing deploy script '$TYPE'"
. "$DIR/deploy/$TYPE.sh"

echo "-----------------------------------------------"
echo "FAILED";
exit 1;