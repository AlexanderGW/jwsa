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
	"cd $WEBROOT && $CLI_PHAR status bootstrap | grep -q Successful"
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

        # Set maintenance mode, and dump a copy of the database.
        if [ "$BOOTSTRAP" -eq "0" ]
        	then
        		$SSH_CONN \
					"echo \"Enable maintenance mode... OK\" \
					&& cd $WEBROOT && $CLI_PHAR sset system.maintenance_mode TRUE \
					&& echo -n \"Dump database... \" \
					&& mysqldump $DEST_DATABASE_NAME > $DEST_DUMP_FILE"

				if [ "$?" -eq "0" ]
					then
						echo "OK"
					else
						echo "FAILED"
						exit 1
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
                        echo -n "Import dump to destination $DEST_DUMP_FILE ... " \
                            && mysql $DEST_DATABASE_NAME < $DEST_DUMP_FILE

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

        # Set .env to new build
		$SSH_CONN \
			"echo -n \"Set .env for build... \" \
			&& sudo ln -snf $DEST_PATH/.env $DEST_BUILD_PATH/.env"

		if [ "$?" -eq "0" ]
			then
				echo "OK"

				# Set webroot symlinks
				$SSH_CONN \
					"echo -n \"Set links for build... \" \
					&& sudo ln -sfn $DEST_BUILD_PATH $WEBROOT \
					&& sudo ln -sfn $DEST_ASSET_PATH $WEBROOT_ASSETS"

				if [ "$?" -eq "0" ]
					then
						echo "OK"

						# Set ownership on build
						$SSH_CONN \
							"echo -n \"Set ownership & permissions for build... \" \
							&& sudo chown $DEST_WEB_USER:$DEST_WEB_USER -R $DEST_BUILD_PATH \
							&& sudo chmod 664 $WEBROOT_SETTINGS"

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
									&& cd $WEBROOT && $CLI_PHAR -y cache-rebuild > /dev/null"

								# Drupal bootstrapped?
								if [ "$BOOTSTRAP" -eq "0" ]
									then
										echo "OK"
										echo ""

										# Update database
										$SSH_CONN \
											"echo \"Apply Drupal database updates...\" \
											&& cd $WEBROOT && $CLI_PHAR -y updatedb"

										if [ "$?" -eq "0" ]
											then
												echo "OK"
												echo ""

												# Update configuration
												$SSH_CONN \
													"echo \"Import Drupal configuration...\" \
													&& cd $WEBROOT && $CLI_PHAR -y config-import"

												if [ "$?" -eq "0" ]
													then
														echo "OK"
														echo ""

														# Disable maintenance mode, and rebuild cache.
														$SSH_CONN \
															"echo \"Disable maintenance mode... OK\" \
															&& cd $WEBROOT && $CLI_PHAR sset system.maintenance_mode FALSE \
															&& echo \"Rebuild Drupal cache... \" \
															&& cd $WEBROOT && $CLI_PHAR -y cache-rebuild > /dev/null"

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
					else
						echo "FAILED"
						exit 1
				fi
			else
				echo "FAILED"
				exit 1
		fi

		# Revert environment to previous build
		if [ "$REVERT" -eq "1" ]
			then
				echo ""
				echo "***********************************************"
				echo "***********************************************"
				echo "* R E V E R T I N G  -  E N V I R O N M E N T *"
				echo "***********************************************"
				echo "***********************************************"

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

				# Create project webroot symlink to last successful job build
				$SSH_CONN \
					"echo -n \"Set symlinks for previous build... \" \
					&& sudo ln -sfn $DEST_BUILDS_PATH/$LAST_BUILD_ID $WEBROOT"

				if [ "$?" -eq "0" ]
					then
						echo "OK"
					else
						echo "FAILED"
				fi

				echo ""

				# Disable maintenance mode
				$SSH_CONN \
					"echo -n \"Disable maintenance mode... \" \
					&& cd $WEBROOT && $CLI_PHAR sset system.maintenance_mode FALSE > /dev/null"

				if [ "$?" -eq "0" ]
					then
						echo "OK"
					else
						echo "FAILED"
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
					&& cd $WEBROOT && $CLI_PHAR -y cache-rebuild > /dev/null"

				if [ "$?" -eq "0" ]
					then
						echo "OK"
					else
						echo "FAILED"
				fi
		fi
fi