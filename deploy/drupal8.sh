#! /bin/bash

REVERT=0

# Create storage directory
EXISTS=$SSH_CONN \
	"if test -d $DEST_STORAGE_PATH; then echo \"1\"; fi"

if [ "$EXISTS" != "1" ]
	then
		$SSH_CONN \
			"echo -n \"Creating storage path '$DEST_STORAGE_PATH'... \" \
			&& install -d -m 0775 -o $DEST_WEB_USER -g $DEST_WEB_USER $DEST_STORAGE_PATH"

		if [ "$?" -eq "0" ]
			then
				echo "OK"
			else
				echo "FAILED"
		fi
fi

# Create private directory
EXISTS=$SSH_CONN \
	"if test -d $DEST_PRIVATE_PATH; then echo \"1\"; fi"

if [ "$EXISTS" != "1" ]
	then
		$SSH_CONN \
			"echo -n \"Creating private path '$DEST_PRIVATE_PATH'... \" \
			&& install -d -m 0775 -o $DEST_WEB_USER -g $DEST_WEB_USER $DEST_PRIVATE_PATH"

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
				echo "COPY $DEST_BUILDS_PATH/$LAST_BUILD_ID --> $DEST_BUILD_PATH"
				$SSH_CONN \
					"cp -R $DEST_BUILDS_PATH/$LAST_BUILD_ID/* $DEST_BUILD_PATH"
		fi
	else
		echo "FAILED"
fi

# Sync new build to destination
echo "RSYNC $WORKSPACE_PATH --> $DEST_BUILD_PATH"
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
				# TODO: COPY LOCAL DB TO DEST?
				echo ""
		fi

		# Create .env template
		EXISTS=$SSH_CONN \
			"if test -d $DEST_PATH/.env; then echo \"1\"; fi"

		if [ "$EXISTS" != "1" ]
			then
				$SSH_CONN \
					"echo -n \"Creating .env template... \" \
					&& echo -e \"MYSQL_DATABASE=\\\"$DEST_DATABASE_NAME\\\"\\n\
MYSQL_HOSTNAME=\\\"localhost\\\"\\n\
MYSQL_PASSWORD=\\\"123\\\"\\n\
MYSQL_PORT=3306\\n\
MYSQL_USER=\\\"dbuser\\\"\\n\
\\n\
HASH_SALT=\\\"\\\"\\n\
\\n\
APP_ENV=\\\"$JOB_ENV\\\"\\n\" > $DEST_PATH/.env"

				if [ "$?" -eq "0" ]
					then
						echo "OK"
					else
						echo "FAILED"
				fi
		fi

        # Set .env to new build
		$SSH_CONN \
			"echo -n \"Set .env for build... \" \
			&& sudo touch $DEST_PATH/.env \
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

								# Remove old builds, leaving current and previous
								if [ "$LAST_BUILD_ID" != "0" ]
									then
										$SSH_CONN \
											"echo -n \"Clean up... \" \
											&& sudo su $DEST_WEB_USER -c \"ls $DEST_BUILDS_PATH | grep -v -e \"$BUILD_ID\" -e \"$LAST_BUILD_ID\" | cut -f2 -d: | xargs rm -rf\""
									else
										$SSH_CONN \
											"echo -n \"Clean up... \" \
											&& sudo su $DEST_WEB_USER -c \"ls $DEST_BUILDS_PATH | grep -v -e \"$BUILD_ID\" | cut -f2 -d: | xargs rm -rf\""
								fi

								echo "OK"

								echo "sudo su $DEST_WEB_USER -c \"ls $DEST_BUILDS_PATH | grep -v -e \\\"$BUILD_ID\\\" | cut -f2 -d: | xargs rm -rf\""

								# Update deployment information
								$SSH_CONN \
									"echo $BUILD_ID > $DEST_PATH/.active-build"

								# Reduce settings file permissions
								if [ "$BOOTSTRAP" -eq "0" ]
									then
										$SSH_CONN \
											"sudo chmod 644 $WEBROOT_SETTINGS"
								fi

								# SCP dump from destination
								echo "SCP $SRC_DUMP_FILE <-- $DEST_DUMP_FILE "
								scp -i $DEST_IDENTITY \
									$DEST_SSH_USER@$DEST_HOST:$DEST_DUMP_FILE \
									$SRC_DUMP_FILE

								if [ "$?" -eq "0" ]
									then
										echo "OK"
									else
										echo "FAILED"
								fi

								echo "-----------------------------------------------"
								echo "SUCCESS"
								exit 0
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
				echo "Restoring environment..."

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