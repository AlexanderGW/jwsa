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
echo " .d88P\"    Jenkins Web Scripts by Alex [1.1.3]"
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

# $4 = ENV_FILE
if ! [ -e "$4" ]
    then
        echo "Invalid ENV_FILE"
        exit 1
fi
ENV_FILE=$4

echo "--------------------------------------------------------------------------------"
echo "Deploy '$PROJECT_NAME' (build: $BUILD_ID)"
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

# Get destination database current name
echo -n "Locate current database... "
DEST_DATABASE_NAME_MATCH=0
if [ "$JOB_ENV" == "prod" ] && [ "$LAST_BUILD_ID" != "0" ]
    then
        DEST_DATABASE_CURRENT_NAME="${PROJECT_NAME}__${LAST_BUILD_ID}"
        RESULT=`$SSH_CONN "mysqlshow $DEST_DATABASE_CURRENT_NAME | grep -v Wildcard | grep -o $DEST_DATABASE_CURRENT_NAME"`
        if [ "$RESULT" == "$DEST_DATABASE_CURRENT_NAME" ]
            then
                echo "OK [$DEST_DATABASE_CURRENT_NAME]"
                DEST_DATABASE_NAME_MATCH=1
        fi
fi

if [ "$DEST_DATABASE_NAME_MATCH" == "0" ]
    then
        DEST_DATABASE_CURRENT_NAME=`$SSH_CONN "grep MYSQL_DATABASE $DEST_PATH/.env | cut -d '=' -f2"`
        RESULT=`$SSH_CONN "mysqlshow $DEST_DATABASE_CURRENT_NAME | grep -v Wildcard | grep -o $DEST_DATABASE_CURRENT_NAME"`
        if [ "$RESULT" == "$DEST_DATABASE_CURRENT_NAME" ]
            then
                echo "OK [$DEST_DATABASE_CURRENT_NAME]"
                DEST_DATABASE_NAME_MATCH=1
        fi
fi

if [ -z ${DEST_DATABASE_CURRENT_NAME+x} ];
    then
        DEST_DATABASE_CURRENT_NAME="${PROJECT_NAME}"
        DEST_DATABASE_NAME_MATCH=1
fi

if [ "$DEST_DATABASE_NAME_MATCH" == "0" ]
    then
        echo "--------------------------------------------------------------------------------"
        echo "FAILED: Cannot locate active destination database"
        echo "--------------------------------------------------------------------------------"
        exit 1
fi

# Database locations
SRC_DUMP_PATH="$DIR/project/$PROJECT_NAME/backup"
SRC_DUMP_FILE="$SRC_DUMP_PATH/$PROJECT_NAME-predeploy-$BUILD_ID.sql"
DEST_DUMP_FILE="$DEST_DUMP_PATH/$PROJECT_NAME-predeploy-$BUILD_ID.sql"

DESTINATION_DATABASE_DUMPED=0

# Test SSH connect
echo -n "Test SSH connection... "
$SSH_CONN exit

if [ "$?" -eq "0" ]
	then
		echo "OK"
	else

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

# Establish destination database credentials
if [ -z ${USE_MYSQL_HOST_WILDCARD+x} ];
    then
		DEST_DATABASE_HOSTNAME=`$SSH_CONN "grep MYSQL_HOSTNAME $DEST_PATH/.env | cut -d '=' -f2"`
		if [ -z ${DEST_DATABASE_HOSTNAME+x} ];
			then
				DEST_DATABASE_HOSTNAME="localhost"
		fi
	else
		DEST_DATABASE_HOSTNAME="%"
fi

DEST_DATABASE_USER=`$SSH_CONN "grep MYSQL_USER $DEST_PATH/.env | cut -d '=' -f2"`
if [ -z ${DEST_DATABASE_USER+x} ];
    then
        DEST_DATABASE_USER=`date +%s | sha256sum | base64 | head -c 16`
fi

DEST_DATABASE_PASSWORD=`$SSH_CONN "grep MYSQL_PASSWORD $DEST_PATH/.env | cut -d '=' -f2"`
if [ -z ${DEST_DATABASE_PASSWORD+x} ];
    then
        DEST_DATABASE_PASSWORD=`date +%s | sha256sum | base64 | head -c 32`
fi

# Setup database & user for new build
if [ "$JOB_ENV" == "prod" ]
    then
        DEST_DATABASE_NAME="${PROJECT_NAME}__${BUILD_ID}"
    else
        DEST_DATABASE_NAME=`$SSH_CONN "grep MYSQL_DATABASE $DEST_PATH/.env | cut -d '=' -f2"`
fi

if [ -z ${DEST_DATABASE_NAME+x} ];
    then
        DEST_DATABASE_NAME="${PROJECT_NAME}"
fi

# Database user creation query
Q1="CREATE USER \\\`$DEST_DATABASE_USER\\\`@\\\`$DEST_DATABASE_HOSTNAME\\\` IDENTIFIED BY '$DEST_DATABASE_PASSWORD';"

echo -n "Setup destination database user '$DEST_DATABASE_USER' to '$DEST_DATABASE_HOSTNAME' for build... "
$SSH_CONN \
    "mysql -e \"$Q1\""

if [ "$?" -eq "0" ]
    then
        echo "OK"
    else
        echo "FAILED"
fi

# Database & user permission creation queries
Q1="CREATE DATABASE IF NOT EXISTS \\\`$DEST_DATABASE_NAME\\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
Q2="GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES ON \\\`$DEST_DATABASE_NAME\\\`.* TO \\\`$DEST_DATABASE_USER\\\`@\\\`$DEST_DATABASE_HOSTNAME\\\` IDENTIFIED BY '$DEST_DATABASE_PASSWORD';"
Q3="FLUSH PRIVILEGES;"

echo -n "Setup destination database '$DEST_DATABASE_NAME' on '$DEST_DATABASE_HOSTNAME' for build... "
$SSH_CONN \
    "mysql -e \"$Q1$Q2$Q3\""

if [ "$?" -eq "0" ]
    then
        echo "OK"
    else
        echo "FAILED"
        exit 1
fi

# Ignored database table data
IGNORED_TABLES_STRING=''
for TABLE in "${DATABASE_TABLE_NO_DATA[@]}"
do
   IGNORED_TABLES_STRING+=" --ignore-table=${DEST_DATABASE_NAME}.${TABLE}"
done

# Create assets directory
EXISTS=`$SSH_CONN \
	"if test -d $DEST_ASSET_PATH; then echo \"1\"; else echo \"0\"; fi"`

if [ "$EXISTS" != "1" ]
	then
	  	echo -n "Creating asset path '$DEST_ASSET_PATH'... "
		$SSH_CONN \
			"sudo install -d -m 0770 -o $DEST_WEB_USER -g $DEST_WEB_USER $DEST_ASSET_PATH"

		if [ "$?" -eq "0" ]
			then
				echo "OK"
			else
				echo "FAILED"
		fi
fi

# Create backup directory
EXISTS=`$SSH_CONN \
	"if test -d $DEST_DUMP_PATH; then echo \"1\"; else echo \"0\"; fi"`

if [ "$EXISTS" != "1" ]
	then
	  	echo -n "Creating backup path '$DEST_DUMP_PATH'... "
		$SSH_CONN \
			"sudo install -d -m 0770 -o $DEST_SSH_USER -g $DEST_SSH_USER $DEST_DUMP_PATH"

		if [ "$?" -eq "0" ]
			then
				echo "OK"
			else
				echo "FAILED"
		fi
fi

# Make build path
echo -n "Creating build path '$DEST_BUILD_PATH'... "
$SSH_CONN \
	"sudo install -d -m 0770 -o $DEST_SSH_USER -g $DEST_SSH_USER $DEST_BUILD_PATH"

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

# Get hash salt from .env
HASH_SALT=$(grep HASH_SALT $ENV_FILE | cut -d '=' -f2)

# Source the deploy script (drupal7, drupal8, wordpress, etc...)
echo "Sourcing deploy script '$TYPE'"
. "$DIR/deploy/$TYPE.sh"

# Update deployment information
$SSH_CONN \
    "echo $BUILD_ID > $DEST_PATH/.active-build"

# Reduce settings file permissions
if [ "$BOOTSTRAP" -eq "0" ]
    then
        $SSH_CONN \
            "sudo chmod 640 $DEST_BUILD_SETTINGS_PATH"
fi

# Dump a copy of the database.
if [ "$DESTINATION_DATABASE_DUMPED" -eq "0" ]
    then
        echo -n "Dump destination database '$DEST_DATABASE_CURRENT_NAME' structure... "
        $SSH_CONN \
            "mysqldump $DEST_DATABASE_CURRENT_NAME --single-transaction --no-data --routines > $DEST_DUMP_FILE"

        if [ "$?" -eq "0" ]
            then
                echo "OK"

                echo -n "Dump destination database '$DEST_DATABASE_CURRENT_NAME' data... "
				$SSH_CONN \
					"mysqldump $DEST_DATABASE_CURRENT_NAME --single-transaction --force --no-create-info --skip-triggers $IGNORED_TABLES_STRING >> $DEST_DUMP_FILE"

				if [ "$?" -eq "0" ]
					then
						echo "OK"
						DESTINATION_DATABASE_DUMPED=1
					else
						echo "FAILED"
				fi
            else
                echo "FAILED"
        fi
fi

# SCP dump from destination
if [ "$DESTINATION_DATABASE_DUMPED" -eq "1" ]
    then
        echo "SCP destination database to local '$SRC_DUMP_FILE'"
        echo "<-- $DEST_DUMP_FILE "
        scp -i $DEST_IDENTITY \
            $DEST_SSH_USER@$DEST_HOST:$DEST_DUMP_FILE \
            $SRC_DUMP_FILE

        if [ "$?" -eq "0" ]
            then
                echo "OK"
            else
                echo "FAILED"
        fi
fi

# Trim old destination databases
if [ "$LAST_BUILD_ID" != "0" ]
    then
        RESULT=`$SSH_CONN \
            "ls $DEST_BUILDS_PATH | grep -v -e \"$PROJECT_NAME\" -e \"$BUILD_ID\" -e \"$LAST_BUILD_ID\" | cut -f2 -d:"`
    else
        RESULT=`$SSH_CONN \
            "ls $DEST_BUILDS_PATH | grep -v -e \"$PROJECT_NAME\" -e \"$BUILD_ID\"  | cut -f2 -d:"`
fi

# TODO: ADD DB DELETE EXCEPTION FOR $PROJECT_NAME AND $DEST_DATABASE_NAME

for ID in ${RESULT[@]}
    do
        ID_CLEAN="${ID%/}"
        NAME="${PROJECT_NAME}__${ID_CLEAN}"

        # Do not delete the current database
        if [ ! "$NAME" == "$PROJECT_NAME" ] && [ ! "$NAME" == "$DEST_DATABASE_CURRENT_NAME" ]
            then
                Q1="DROP DATABASE \\\`$NAME\\\`;"

                echo -n "Remove old destination database '$NAME'... "
                $SSH_CONN \
                    "mysql -e \"$Q1\""

                if [ "$?" == "0" ]
                    then
                        echo "OK"
                    else
                        echo "FAILED"
                fi
        fi
done

# Trim old builds, leaving current and previous successful build
echo -n "Trim deployed builds... "
if [ "$LAST_BUILD_ID" != "0" ]
    then
        $SSH_CONN \
            "cd $DEST_BUILDS_PATH && ls $DEST_BUILDS_PATH | grep -v -e \"$BUILD_ID\" -e \"$LAST_BUILD_ID\" | cut -f2 -d: | xargs sudo rm -rf"
    else
        $SSH_CONN \
            "cd $DEST_BUILDS_PATH && ls $DEST_BUILDS_PATH | grep -v -e \"$BUILD_ID\" | cut -f2 -d: | xargs sudo rm -rf"
fi

echo "OK"

# Trim old local backups, keep last two
echo -n "Trim local backups... "
SRC_DUMP_PATH="$DIR/project/$PROJECT_NAME/backup"
SRC_LAST_DUMP_NAME=`ls -t $SRC_DUMP_PATH | head -1`
cd $SRC_DUMP_PATH && ls $SRC_DUMP_PATH | grep -v -e "$SRC_LAST_DUMP_NAME" | head -2 | cut -f2 -d: | xargs rm -rf

echo "OK"

# Trim old remote backups, keep last five
echo -n "Trim remote backups... "
DEST_LAST_DUMP_NAME=`$SSH_CONN "ls -t $DEST_DUMP_PATH | head -1"`
$SSH_CONN \
    "cd $DEST_DUMP_PATH && ls $DEST_DUMP_PATH | grep -v -e \"$DEST_LAST_DUMP_NAME\" | head -2 | cut -f2 -d: | xargs rm -rf"

echo "OK"
echo ""
echo "--------------------------------------------------------------------------------"
echo "Deploy: SUCCESS"
echo "--------------------------------------------------------------------------------"
echo ""
exit 0