#!/bin/bash

echo ""
echo "  888888 888       888  .d8888b.         d8888"
echo "    \"88b 888   o   888 d88P  Y88b       d88888"
echo "     888 888  d8b  888 Y88b.           d88P888"
echo "     888 888 d888b 888  \"Y888b.       d88P 888"
echo "     888 888d88888b888     \"Y88b.    d88P  888"
echo "     888 88888P Y88888       \"888   d88P   888"
echo "     88P 8888P   Y8888 Y88b  d88P  d8888888888"
echo "     888 888P     Y888  \"Y8888P\"  d88P     888"
echo "   .d88P"
echo " .d88P\"    Jenkins Web Scripts by Alex [1.1.5]"
echo "888P\"      https://github.com/AlexanderGW/jwsa"
echo ""

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

echo "--------------------------------------------------------------------------------"
echo "Package '$PROJECT_NAME' (build: $BUILD_ID)"
echo "--------------------------------------------------------------------------------"
echo ""

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
		echo "FAILED"
		exit 1;
	else
		echo "OK"
fi

JOB_ENV=`echo $1 | cut -d'-' -f2`

# Load .env file
. "$DIR/.env"

declare -a WEBSERVERS=("apache" "httpd" "nginx")
declare -a WEBSERVER_CONF_DIRS=("sites-available" "conf.d")

# Package name and paths
SRC_PACKAGE_PATH="/tmp/$PROJECT_NAME-$DATE.tar";
DEST_PACKAGE_PATH="$DEST_PATH/$PROJECT_NAME.tar";

# Test SSH connect
echo -n "Test SSH connection... "
$SSH_CONN exit

if [ "$?" -eq "0" ]
	then
		echo "OK"
	else

		if [ ! -e "$DEST_IDENTITY" ];
			then
				echo "FAILED"
        exit 1
		fi
fi

# Make deployment path
echo -n "Creating path '$DEST_PATH'... "
$SSH_CONN \
	"sudo install -d -m 0775 -o $DEST_SSH_USER -g $DEST_SSH_USER $DEST_PATH"

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
			"if test -d /etc/$SERVICE_NAME; then echo \"1\"; else echo \"0\"; fi"`

		if [ "$EXISTS" == "1" ]
			then
				for DIR_NAME in ${WEBSERVER_CONF_DIRS[@]}
					do
						$SSH_CONN \
							"sudo ls -l /etc/$SERVICE_NAME/$DIR_NAME > /dev/null"

						if [ "$?" -eq "0" ]
							then

								# Rsync project etc configs (apache, nginx, etc)
								echo "RSYNC $DIR/project/$PROJECT_NAME/$SERVICE_NAME"
								echo "--> /etc/$SERVICE_NAME/$DIR_NAME"
								rsync $RSYNC_FLAGS "ssh -i $DEST_IDENTITY" --rsync-path="sudo rsync" \
									$DIR/project/$PROJECT_NAME/$SERVICE_NAME/* \
									$DEST_SSH_USER@$DEST_HOST:/etc/$SERVICE_NAME/$DIR_NAME

								if [ "$?" -eq "0" ]
									then
#										echo "OK"
										UPDATED=1

										# Create enabled site symlink if required
										if [ "$DIR_NAME" == "sites-available" ]
											then
												$SSH_CONN \
													"sudo ln -sfn /etc/$SERVICE_NAME/$DIR_NAME/$PROJECT_NAME.conf /etc/$SERVICE_NAME/sites-enabled/$PROJECT_NAME.conf"

												if [ "$?" -eq "0" ]
													then
														break
												fi
										fi
#									else
#										echo "FAILED"
								fi

								echo ""
						fi
					done
		fi
	done

echo "OK"
echo ""

# Reload specified services
if [ "$UPDATED" == "1" ];
	then
		for SERVICE in ${DEST_SERVICES_RELOAD[@]}
		do
		  	echo "Reload service '$SERVICE'... "
			$SSH_CONN \
				"sudo service $SERVICE reload"

			if [ "$?" -eq "0" ]
				then
					echo "OK"
				else
					echo "FAILED"
			fi
		done
fi

echo ""

# Paths to exclude from the package
EXCLUDED_ITEM_STRING=''
for NAME in "${WORKSPACE_PACKAGE_EXCLUDE[@]}"
  do
    EXCLUDED_ITEM_STRING+=" --exclude ${NAME}"
done

# Package the workspace
echo -n "Creating package '$SRC_PACKAGE_PATH'... "
cd $WORKSPACE_PATH
tar$EXCLUDED_ITEM_STRING -cf $SRC_PACKAGE_PATH .

if [ "$?" -eq "0" ]
  then
    echo "OK"
  else
    echo "FAILED"
    exit 1
fi

# Rsync package to destination
echo "RSYNC $SRC_PACKAGE_PATH"
echo "--> $DEST_PACKAGE_PATH"
rsync $RSYNC_FLAGS "ssh -i $DEST_IDENTITY" --rsync-path="sudo rsync" \
  $SRC_PACKAGE_PATH \
  $DEST_SSH_USER@$DEST_HOST:$DEST_PACKAGE_PATH

if [ "$?" -eq "0" ]
  then
    echo "OK"
  else
    echo "FAILED"
    exit 1
fi

#Set permissions on destination
echo -n "Set ownership & permissions for package... "
$SSH_CONN \
    "sudo chown $DEST_SSH_USER:$DEST_SSH_USER -R $DEST_PATH \
    && sudo chmod 664 $DEST_PACKAGE_PATH"

if [ "$?" -eq "0" ]
	then
		echo "OK"
	else
		echo "FAILED"
fi

echo ""
echo "--------------------------------------------------------------------------------"
echo "Package: SUCCESS"
echo "--------------------------------------------------------------------------------"
echo ""
exit 0