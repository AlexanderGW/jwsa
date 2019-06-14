#! /bin/bash

REVERT=0

# Create storage directory
EXISTS=`$SSH_CONN \
	"if test -d $DEST_STORAGE_PATH; then echo \"1\"; else echo \"0\"; fi"`

if [ "$EXISTS" != "1" ]
	then
		$SSH_CONN \
			"echo -n \"Creating storage path '$DEST_STORAGE_PATH'... \" \
			&& sudo install -d -m 0775 -o $DEST_WEB_USER -g $DEST_WEB_USER $DEST_STORAGE_PATH"

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
		$SSH_CONN \
			"echo -n \"Creating private path '$DEST_PRIVATE_PATH'... \" \
			&& sudo install -d -m 0775 -o $DEST_WEB_USER -g $DEST_WEB_USER $DEST_PRIVATE_PATH"

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
	"cd $DEST_WEBROOT_PATH && $CLI_PHAR status bootstrap | grep -q Successful"
BOOTSTRAP=$?

if [ "$BOOTSTRAP" -eq "0" ]
    then
        echo "OK"

        # Make a copy of current build into the new build on dest, to ease diff sync
		if [ "$LAST_BUILD_ID" != "0" ]
			then
				echo "COPY $DEST_BUILDS_PATH/$LAST_BUILD_ID"
				echo "--> $DEST_BUILD_PATH"
				$SSH_CONN \
					"cp -R $DEST_BUILDS_PATH/$LAST_BUILD_ID/* $DEST_BUILD_PATH"
		fi
	else
		echo "FAILED"
fi

# Sync new build to destination
echo "RSYNC $WORKSPACE_PATH"
echo "--> $DEST_BUILD_PATH"
rsync $RSYNC_FLAGS "ssh -i $DEST_IDENTITY" \
    $WORKSPACE_PATH/* \
    $DEST_SSH_USER@$DEST_HOST:$DEST_BUILD_PATH

if [ "$?" -eq "0" ]
    then
		echo ""

        # If environment is bootstrapped...
        if [ "$BOOTSTRAP" -eq "0" ]
        	then
        		if [ "$JOB_ENV" == "prod" ]
        			then

        				# Set read-only mode
        				$SSH_CONN \
							"echo -n \"Enable read-only mode... \" \
							&& cd $DEST_WEBROOT_PATH && $CLI_PHAR vset site_readonly 1"

						if [ "$?" -eq "0" ]
							then
								echo "OK"
							else
								echo "FAILED"
								exit 1
						fi
					else

						# Set maintenance mode, and dump a copy of the database.
						$SSH_CONN \
							"echo \"Enable maintenance mode...\" \
							&& cd $DEST_WEBROOT_PATH && $CLI_PHAR sset system.maintenance_mode TRUE \
							&& echo \"OK\" \
							&& echo -n \"Dump database... \" \
							&& mysqldump $DEST_DATABASE_NAME > $DEST_DUMP_FILE"

						if [ "$?" -eq "0" ]
							then
								echo "OK"
							else
								echo "FAILED"
								exit 1
						fi
				fi
			else

				# SCP local dump to destination
                echo "SCP $SRC_DUMP_FILE"
                echo "--> $DEST_DUMP_FILE "
                scp -i $DEST_IDENTITY \
                    $DEST_SSH_USER@$DEST_HOST:$DEST_DUMP_FILE \
                    $SRC_DUMP_FILE

                if [ "$?" -eq "0" ]
                    then

                        # Import the copied dump
                        $SSH_CONN \
                        	"echo -n \"Import dump to destination $DEST_DUMP_FILE ... \" \
                            && mysql $DEST_DATABASE_NAME < $DEST_DUMP_FILE"

                        if [ "$?" -eq "0" ]
                            then
                                echo "OK"

                                # Delete the dump
                                echo -n "Clean up ... " \
                                    && rm -rf $DEST_DUMP_FILE

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
		fi

		if [ "$JOB_ENV" == "prod" ]
			then

				# Copy .env to new build. It will be updated with new database details and copied back, and linked.
				$SSH_CONN \
					"echo -n \"Copy .env to build... \" \
					&& cp $DEST_PATH/.env $DEST_BUILD_PATH/.env"

				if [ "$?" -eq "0" ]
					then
						echo "OK"
					else
						echo "FAILED"
						exit 1
				fi
			else

				# Link .env to build
				$SSH_CONN \
					"echo -n \"Link .env to build... \" \
					&& sudo ln -snf $DEST_PATH/.env $DEST_BUILD_PATH/.env"

				if [ "$?" -eq "0" ]
					then
						echo "OK"
					else
						echo "FAILED"
						exit 1
				fi
		fi





		# Set ownership on build
		$SSH_CONN \
			"echo -n \"Set ownership & permissions for build... \" \
			&& sudo chown $DEST_WEB_USER:$DEST_WEB_USER -R $DEST_BUILD_PATH \
			&& sudo chmod 664 $DEST_DEST_WEBROOT_PATH_SETTINGS_PATH"

		if [ "$?" -eq "0" ]
			then
				echo "OK"

				# Restart specified services
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

				echo ""

				# Rebuild cache
				$SSH_CONN \
					"echo \"Rebuild Drupal cache...\" \
					&& cd $DEST_BUILD_PATH && $CLI_PHAR -y cache-rebuild > /dev/null"

				# Drupal bootstrapped?
				if [ "$BOOTSTRAP" -eq "0" ]
					then
						echo "OK"
						echo ""

						# Update database
						$SSH_CONN \
							"echo \"Apply Drupal database updates...\" \
							&& cd $DEST_BUILD_PATH && $CLI_PHAR -y updatedb"

						if [ "$?" -eq "0" ]
							then
								echo "OK"
								echo ""

								# Update configuration
								$SSH_CONN \
									"echo \"Import Drupal configuration...\" \
									&& cd $DEST_BUILD_PATH && $CLI_PHAR -y config-import"

								if [ "$?" -eq "0" ]
									then
										echo "OK"
										echo ""

										# Switch webroot symlinks to the new build
										$SSH_CONN \
											"echo -n \"Set links for build... \" \
											&& sudo ln -sfn $DEST_BUILD_PATH $DEST_WEBROOT_PATH \
											&& sudo ln -sfn $DEST_ASSET_PATH $DEST_DEST_WEBROOT_PATH_ASSET_PATH"

										if [ "$?" -eq "0" ]
											then
												echo "OK"
											else
												echo "FAILED"
												exit 1
										fi

										if [ "$JOB_ENV" == "prod" ]
											then

												# Disable read-only mode, and rebuild cache.
												$SSH_CONN \
													"echo -n \"Disable read-only mode... \" \
													&& cd $DEST_BUILD_PATH && $CLI_PHAR vset site_readonly 0 \
													&& echo \"OK\" \
													&& echo \"Rebuild Drupal cache... \" \
													&& cd $DEST_BUILD_PATH && $CLI_PHAR -y cache-rebuild > /dev/null"

												if [ "$?" -eq "0" ]
													then
														echo "OK"
													else
														echo "FAILED"

														if [ "$BOOTSTRAP" -eq "0" ]
															then
																REVERT=1
														fi
												fi
											else

												# Disable maintenance mode, and rebuild cache.
												$SSH_CONN \
													"echo \"Disable maintenance mode... OK\" \
													&& cd $DEST_BUILD_PATH && $CLI_PHAR sset system.maintenance_mode FALSE \
													&& echo \"Rebuild Drupal cache... \" \
													&& cd $DEST_BUILD_PATH && $CLI_PHAR -y cache-rebuild > /dev/null"

												if [ "$?" -eq "0" ]
													then
														echo "OK"
													else
														echo "FAILED"

														if [ "$BOOTSTRAP" -eq "0" ]
															then
																REVERT=1
														fi
												fi
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
				$SSH_CONN \
					"echo -n \"Restoring database: $DEST_DUMP_FILE ... \" \
					&& mysql $DEST_DATABASE_NAME < $DEST_DUMP_FILE"

				if [ "$?" -eq "0" ]
					then
						echo "OK"
					else
						echo "FAILED"
				fi

				echo ""

				# Set webroot symlink to last successful build
				$SSH_CONN \
					"echo -n \"Set symlinks for previous build... \" \
					&& sudo ln -sfn $DEST_BUILDS_PATH/$LAST_BUILD_ID $DEST_WEBROOT_PATH"

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
						$SSH_CONN \
							"echo -n \"Disable read-only mode... \" \
							&& cd $DEST_BUILDS_PATH/$LAST_BUILD_ID && $CLI_PHAR vset site_readonly 0"

						if [ "$?" -eq "0" ]
							then
								echo "OK"
							else
								echo "FAILED"
						fi
					else

						# Disable maintenance mode.
						$SSH_CONN \
							"echo -n \"Disable maintenance mode... \" \
							&& cd $DEST_BUILDS_PATH/$LAST_BUILD_ID && $CLI_PHAR sset system.maintenance_mode FALSE > /dev/null"

						if [ "$?" -eq "0" ]
							then
								echo "OK"
							else
								echo "FAILED"
						fi
				fi

				echo ""

				# Restart specified services
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

				echo ""

				# Rebuild cache
				$SSH_CONN \
					"echo -n \"Rebuild Drupal cache... \" \
					&& cd $DEST_BUILDS_PATH/$LAST_BUILD_ID && $CLI_PHAR -y cache-rebuild > /dev/null"

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
fi