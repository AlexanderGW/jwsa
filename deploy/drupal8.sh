#! /bin/bash

echo ""
echo "--------------------------------------------------------------------------------"
echo "Deploy '$PROJECT_NAME' (build: $BUILD_ID) - Platform 'Drupal 8'"
echo "--------------------------------------------------------------------------------"
echo ""

REVERT=0

# Create storage directory
EXISTS=`$SSH_CONN \
	"if test -d $DEST_STORAGE_PATH; then echo \"1\"; else echo \"0\"; fi"`

if [ "$EXISTS" != "1" ]
	then
	  	echo -n "Creating storage path '$DEST_STORAGE_PATH'... "
		$SSH_CONN \
			"sudo install -d -m 0775 -o $DEST_WEB_USER -g $DEST_WEB_USER $DEST_STORAGE_PATH"

		if [ "$?" -eq "0" ]
			then
				echo "OK"
			else
				echo "FAILED"
		fi
fi

# Create private directory
EXISTS=`$SSH_CONN \
	"if test -d $DEST_PRIVATE_PATH; then echo \"1\"; else echo \"0\"; fi"`

if [ "$EXISTS" != "1" ]
	then
	  	echo -n "Creating private path '$DEST_PRIVATE_PATH'... "
		$SSH_CONN \
			"sudo install -d -m 0775 -o $DEST_WEB_USER -g $DEST_WEB_USER $DEST_PRIVATE_PATH"

		if [ "$?" -eq "0" ]
			then
				echo "OK"
			else
				echo "FAILED"
		fi
fi

# Check current Drupal environment status
echo -n "Drupal bootstrap... "
$SSH_CONN \
	"cd $DEST_WEBROOT_PATH && $CLI_PHAR status bootstrap | grep -q Successful > /dev/null"
BOOTSTRAP=$?


if [ "$BOOTSTRAP" -eq "0" ] && [ "$LAST_BUILD_ID" != "0" ]
    then
        echo "OK"

        # Make a copy of current build into the new build on dest, to ease diff sync
		    echo "COPY last successful build $DEST_BUILDS_PATH/$LAST_BUILD_ID"
        echo "--> $DEST_BUILD_PATH"
        $SSH_CONN \
            "cp -R $DEST_BUILDS_PATH/$LAST_BUILD_ID/* $DEST_BUILD_PATH"

        echo "RSYNC new build difference $WORKSPACE_PATH"
        echo "--> $DEST_BUILD_PATH"
        rsync $RSYNC_FLAGS "ssh -i $DEST_IDENTITY" \
            $WORKSPACE_PATH/* \
            $DEST_SSH_USER@$DEST_HOST:$DEST_BUILD_PATH
    else
        # Send build to destination
#        echo "SCP build $WORKSPACE_PATH"
#        echo "--> $DEST_BUILD_PATH"
#        scp -ri $DEST_IDENTITY \
#            $WORKSPACE_PATH/* \
#            $DEST_SSH_USER@$DEST_HOST:$DEST_BUILD_PATH
        echo "RSYNC build $WORKSPACE_PATH"
        echo "--> $DEST_BUILD_PATH"
        rsync $RSYNC_FLAGS "ssh -i $DEST_IDENTITY" \
            $WORKSPACE_PATH/* \
            $DEST_SSH_USER@$DEST_HOST:$DEST_BUILD_PATH
fi

# If environment is bootstrapped...
if [ "$BOOTSTRAP" -eq "0" ]
    then
        if [ "$JOB_ENV" == "prod" ]
            then

                # Set read-only mode, and copy the database.
                echo -n "Enable read-only mode... "
                $SSH_CONN \
                    "cd $DEST_WEBROOT_PATH && $CLI_PHAR sset site_readonly 1"

                if [ "$?" -eq "0" ]
                    then
                        echo "OK"

                        # Set read-only mode, and copy the database.
                        echo -n "Copy database '$DEST_DATABASE_CURRENT_NAME' to '$DEST_DATABASE_NAME'... "
                        $SSH_CONN \
                            "mysqldump $DEST_DATABASE_CURRENT_NAME --single-transaction --routines | mysql $DEST_DATABASE_NAME"

                        if [ "$?" -eq "0" ]
                            then
                                echo "OK"
                            else
                                echo "FAILED"
                                exit 1
                        fi
                    else
                        echo "FAILED"
                        exit 1
                fi
            else

                # Set maintenance mode
                echo -n "Enable maintenance mode... "
                $SSH_CONN \
                    "cd $DEST_WEBROOT_PATH && $CLI_PHAR sset system.maintenance_mode TRUE"

                if [ "$?" -eq "0" ]
                    then
                        echo "OK"
                fi

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
    else
        RESULT=`$SSH_CONN "mysqlshow $DEST_DATABASE_NAME | grep -v Wildcard | grep -o $DEST_DATABASE_NAME"`
        if [ "$RESULT" != "$DEST_DATABASE_NAME" ]
            then
                LOCAL_DATABASE_NAME=$(grep MYSQL_DATABASE $ENV_FILE | cut -d '=' -f2)

                # Dump local database
                echo -n "Dump local database '$LOCAL_DATABASE_NAME'... "
                mysqldump $LOCAL_DATABASE_NAME --single-transaction > $SRC_DUMP_FILE

                if [ "$?" -eq "0" ]
                    then
                        echo "OK"

                        # SCP local dump to destination
                        echo "SCP local database to destination $SRC_DUMP_FILE"
                        echo "--> $DEST_DUMP_FILE "
                        scp -i $DEST_IDENTITY \
                            $SRC_DUMP_FILE \
                            $DEST_SSH_USER@$DEST_HOST:$DEST_DUMP_FILE

                        if [ "$?" -eq "0" ]
                            then

                                # Import the copied dump
                                echo -n "Import dump on destination $DEST_DUMP_FILE ... "
                                $SSH_CONN \
                                    "mysql $DEST_DATABASE_NAME < $DEST_DUMP_FILE"

                                if [ "$?" -eq "0" ]
                                    then
                                        echo "OK"

                                        # Delete the dump
                                        echo -n "Clean up ... "
                                        rm -rf $DEST_DUMP_FILE

                                        if [ "$?" -eq "0" ]
                                            then
                                                echo "OK"
                                            else
                                                echo "FAILED"
                                        fi
                                    else
                                        echo "FAILED"
                                fi
                            else
                                echo "FAILED"
                        fi
                    else
                        echo "FAILED"
                        exit 1
                fi
        fi
fi

if [ "$LAST_BUILD_ID" != "0" ]
    then
        echo -n "Copy .env from previous build... "
        $SSH_CONN \
            "cp $DEST_BUILDS_PATH/$LAST_BUILD_ID/.env $DEST_BUILD_PATH/.env"

        if [ "$?" -eq "0" ]
            then
                echo "OK"

                echo -n "Update .env MYSQL_DATABASE for new build..."

                # Replace destination database name
                $SSH_CONN \
                    "sed -i \"s,^MYSQL_DATABASE=.*\\\$,MYSQL_DATABASE=\${DEST_DATABASE_NAME},\" $DEST_BUILD_PATH/.env"

                if [ "$?" -eq "0" ]
                    then
                        echo "OK"
                    else
                        echo "FAILED"

                        if [ "$JOB_ENV" == "prod" ]
                            then
                                echo "OK"
                            else
                                echo "FAILED"
                                echo "Production deployments implement incrementing database name suffixes, continuing would break the build"
                                exit 1
                        fi
                fi
            else
                echo "FAILED"
        fi
fi

if [ ! -f "$DEST_BUILD_PATH/.env" ];
    then
        # Write new build .env
        echo "WARNING! Existing .env not found, a new one will be created."

        echo -n "Write .env for build... "
        $SSH_CONN \
            "echo -e \"MYSQL_DATABASE=$DEST_DATABASE_NAME\\n\
        MYSQL_HOSTNAME=$DEST_DATABASE_HOSTNAME\\n\
        MYSQL_PASSWORD=$DEST_DATABASE_PASSWORD\\n\
        MYSQL_PORT=3306\\n\
        MYSQL_USER=$DEST_DATABASE_USER\\n\
        \\n\
        HASH_SALT=$HASH_SALT\\n\
        \\n\
        APP_ENV=$JOB_ENV\\n\
        \\n\
        PRIVATE_PATH=$DEST_PRIVATE_PATH\\n\
        TWIG_PHP_STORAGE_PATH=$DEST_STORAGE_PATH/php\" > $DEST_BUILD_PATH/.env"

        if [ "$?" -eq "0" ]
            then
                echo "OK"
            else
                echo "FAILED"
                echo "Check permissions for .env writing"
                exit 1
        fi
fi

# Set ownership on build
echo -n "Set ownership & permissions for build... "
$SSH_CONN \
    "sudo chown $DEST_WEB_USER:$DEST_WEB_USER -R $DEST_BUILD_PATH \
    && sudo chmod 664 $DEST_BUILD_SETTINGS_PATH"

if [ "$?" -eq "0" ]
    then
        echo "OK"

        # Restart specified services
        for SERVICE in ${DEST_SERVICES_RESTART[@]}
        do
            echo "Restart service '$SERVICE'... "
            $SSH_CONN \
                "sudo service $SERVICE restart"

            if [ "$?" -eq "0" ]
                then
                    echo "OK"
                else
                    echo "FAILED"
            fi
        done

        # Reload specified services
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

        echo ""

        # Rebuild cache
        echo "Rebuild Drupal cache... "
        $SSH_CONN \
            "cd $DEST_BUILD_PATH && $CLI_PHAR -y cache-rebuild > /dev/null"

        # Drupal bootstrapped?
        if [ "$BOOTSTRAP" -eq "0" ]
            then
                echo "OK"
                echo ""

                # Update configuration
                echo "Import Drupal configuration... "
                $SSH_CONN \
                    "cd $DEST_BUILD_PATH && $CLI_PHAR -y config-import"

                if [ "$?" -eq "0" ]
                    then
                        echo "OK"
                        echo ""

                        # Update database
                        echo "Apply Drupal database updates... "
                        $SSH_CONN \
                            "cd $DEST_BUILD_PATH && $CLI_PHAR -y updatedb"

                        if [ "$?" -eq "0" ]
                            then
                                echo "OK"
                                echo ""

                                # Custom commands to run after core Drupal commands
                                echo "Running custom deploy commands..."
                                for (( i = 0; i < ${#DEPLOY_CMDS_CUSTOM_PLATFORM[@]} ; i++ ));
                                    do
                                        INDEX=$(($i + 1))
                                        echo "Command [${INDEX}/${#DEPLOY_CMDS_CUSTOM_PLATFORM[@]}] ... "
                                        $SSH_CONN "${DEPLOY_CMDS_CUSTOM_PLATFORM[$i]}"

                                        if [ "$?" -eq "0" ]
                                            then
                                                echo "DONE"
                                            else
                                                echo "FAILED"
                                        fi
                                    done
                                echo "OK"

                                # Set webroot symlinks
                                echo -n "Set '$PROJECT_NAME' webroot to build ... "
                                $SSH_CONN \
                                    "sudo ln -sfn $DEST_BUILD_PATH $DEST_WEBROOT_PATH \
                                    && sudo ln -sfn $DEST_ASSET_PATH $DEST_BUILD_ASSETS_PATH"

                                if [ "$?" -eq "0" ]
                                    then
                                        echo "OK"

                                        # Restart specified services
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

                                        if [ "$JOB_ENV" == "prod" ]
                                            then

                                                # Disable read-only mode, and rebuild cache.
                                                echo -n "Disable read-only mode... "
                                                $SSH_CONN \
                                                    "cd $DEST_BUILD_PATH && $CLI_PHAR sset site_readonly 0"

                                                if [ "$?" -eq "0" ]
                                                    then
                                                        echo "OK"

                                                        # Disable read-only mode, and rebuild cache.
                                                        echo "Rebuild Drupal cache... "
                                                        $SSH_CONN \
                                                            "cd $DEST_BUILD_PATH && $CLI_PHAR -y cache-rebuild > /dev/null"

                                                        if [ "$?" -eq "0" ]
                                                            then
                                                                echo "OK"
                                                            else
                                                                echo "FAILED"
                                                        fi
                                                    else
                                                        echo "FAILED"
                                                fi
                                            else

                                                # Disable maintenance mode, and rebuild cache.
                                                echo -n "Disable maintenance mode... "
                                                $SSH_CONN \
                                                    "cd $DEST_BUILD_PATH && $CLI_PHAR sset system.maintenance_mode FALSE"

                                                if [ "$?" -eq "0" ]
                                                    then
                                                        echo "OK"

                                                        # Disable maintenance mode, and rebuild cache.
                                                        echo -n "Rebuild Drupal cache... "
                                                        $SSH_CONN \
                                                            "cd $DEST_BUILD_PATH && $CLI_PHAR -y cache-rebuild > /dev/null"

                                                        if [ "$?" -eq "0" ]
                                                            then
                                                                echo "OK"
                                                            else
                                                                echo "FAILED"
                                                        fi
                                                    else
                                                        echo "FAILED"
                                                fi
                                        fi

                                        echo ""
                                        echo "--------------------------------------------------------------------------------"
                                        echo "Deploy: NEW BUILD IS ACTIVE"
                                        echo "--------------------------------------------------------------------------------"
                                        echo ""

                                        # Link project .env to new build
                                        echo -n "Link project .env to build... "
                                        $SSH_CONN \
                                            "rm -rf $DEST_PATH/.env \
                                            && sudo ln -snf $DEST_BUILD_PATH/.env $DEST_PATH/.env"

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

                                if [ "$BOOTSTRAP" -eq "0" ]
                                    then
                                        REVERT=1
                                fi
                        fi

                        echo ""
                    else
                        echo "FAILED"

                        if [ "$BOOTSTRAP" -eq "0" ]
                            then
                                REVERT=1
                        fi
                fi
            else

                # Set webroot symlinks
                echo -n "Set '$PROJECT_NAME' webroot to build... "
                $SSH_CONN \
                    "sudo ln -sfn $DEST_BUILD_PATH $DEST_WEBROOT_PATH \
                    && sudo ln -sfn $DEST_ASSET_PATH $DEST_BUILD_ASSETS_PATH"

                if [ "$?" -eq "0" ]
                    then
                        echo "OK"

                        # Restart specified services
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

                        echo ""
                        echo "--------------------------------------------------------------------------------"
                        echo "Deploy: NEW BUILD IS ACTIVE"
                        echo "--------------------------------------------------------------------------------"
                        echo ""

                        # Link project .env to new build
                        echo -n "Link project .env to build... "
                        $SSH_CONN \
                            "rm -rf $DEST_PATH/.env \
                            && sudo ln -snf $DEST_BUILD_PATH/.env $DEST_PATH/.env"

                        if [ "$?" -eq "0" ]
                            then
                                echo "OK"
                            else
                                echo "FAILED"
                        fi
                    else
                        echo "FAILED"
                fi
        fi
    else
        echo "FAILED"

        if [ "$BOOTSTRAP" -eq "0" ]
            then
                REVERT=1
        fi
fi

# Revert environment to previous build
if [ "$REVERT" -eq "1" ]
    then
        echo ""
        echo "********************************************************************************"
        echo "********************************************************************************"
        echo "***                R E V E R T I N G    E N V I R O N M E N T                ***"
        echo "********************************************************************************"
        echo "********************************************************************************"

        # Restore dumped database
        echo -n "Restoring database: $DEST_DUMP_FILE ... "
        $SSH_CONN \
            "mysql --force $DEST_DATABASE_NAME < $DEST_DUMP_FILE"

        if [ "$?" -eq "0" ]
            then
                echo "OK"
            else echo "FAILED"
        fi

        echo ""

        # Create project webroot symlink to last successful job build
        echo -n "Set '$PROJECT_NAME' webroot to previous build... "
        $SSH_CONN \
            "sudo ln -sfn $DEST_BUILDS_PATH/$LAST_BUILD_ID $DEST_WEBROOT_PATH"

        if [ "$?" -eq "0" ]
            then
                echo "OK"
            else
                echo "FAILED"
        fi

        echo ""

        if [ "$JOB_ENV" == "prod" ]
            then

                # Disable read-only mode.
                echo -n "Disable read-only mode... "
                $SSH_CONN \
                    "cd $DEST_BUILDS_PATH/$LAST_BUILD_ID && $CLI_PHAR sset site_readonly 0"

                if [ "$?" -eq "0" ]
                    then
                        echo "OK"
                    else
                        echo "FAILED"
                fi
            else

                # Disable maintenance mode.
                echo -n "Disable maintenance mode... "
                $SSH_CONN \
                    "cd $DEST_BUILDS_PATH/$LAST_BUILD_ID && $CLI_PHAR sset system.maintenance_mode FALSE > /dev/null"

                if [ "$?" -eq "0" ]
                    then
                        echo "OK"
                    else
                        echo "FAILED"
                fi
        fi

        echo ""

        # Restart specified services
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

        echo ""

        # Rebuild cache
        echo -n "Rebuild Drupal cache... "
        $SSH_CONN \
            "cd $DEST_BUILDS_PATH/$LAST_BUILD_ID && $CLI_PHAR -y cache-rebuild > /dev/null"

        if [ "$?" -eq "0" ]
            then
                echo "OK"
            else
                echo "FAILED"
        fi

        echo ""
        echo "SUCCESS"
        echo "********************************************************************************"
        echo "********************************************************************************"
        exit 1
fi