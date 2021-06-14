#! /bin/bash

echo ""
echo "--------------------------------------------------------------------------------"
echo "Build '$PROJECT_NAME' - Platform 'Drupal 8'"
echo "--------------------------------------------------------------------------------"
echo ""

# Check current Drupal environment status
echo "Drupal bootstrap... "
cd $WORKSPACE_PATH && $CLI_PHAR status bootstrap | grep -q Successful
BOOTSTRAP=$?

if [ "$?" -eq "0" ]
	then

		# Rebuild cache
		echo "Rebuild Drupal cache..."
		cd $WORKSPACE_PATH && $CLI_PHAR -y cache-rebuild > /dev/null

		# Drupal bootstrapped?
		if [ "$BOOTSTRAP" -eq "0" ]
			then
				echo "OK"
				echo ""

				# Update database
        echo "Apply Drupal database updates..."
        cd $WORKSPACE_PATH && $CLI_PHAR -y updatedb --no-cache-clear

				if [ "$?" -eq "0" ]
					then
						echo "OK"
						echo ""

						# Rebuild cache.
            echo "Rebuild Drupal cache... "
            cd $WORKSPACE_PATH && $CLI_PHAR -y cache-rebuild > /dev/null

            if [ "$?" -eq "0" ]
              then
                echo "OK"
						    echo ""
              else
                echo "FAILED"
                exit 1
            fi

						# Update configuration
            echo "Import Drupal configuration..."
            cd $WORKSPACE_PATH && $CLI_PHAR -y config-import

						if [ "$?" -eq "0" ]
							then
								echo "OK"
								echo ""

                # Custom commands to run after core Drupal commands
                echo "Running custom build commands..."
                for (( i = 0; i < ${#BUILD_CMDS_CUSTOM_PLATFORM[@]} ; i++ ));
                  do
                    INDEX=$(($i + 1))
                    echo "Command [${INDEX}/${#BUILD_CMDS_CUSTOM_PLATFORM[@]}] ... "
                    eval "${BUILD_CMDS_CUSTOM_PLATFORM[$i]}"

                    if [ "$?" -eq "0" ]
                      then
                        echo "DONE"
                        echo ""
                      else
                        echo "FAILED"
										    exit 1
                    fi
                  done
                echo "OK"
								echo ""

								# Rebuild cache.
								echo "Rebuild Drupal cache... "
								cd $WORKSPACE_PATH && $CLI_PHAR -y cache-rebuild > /dev/null

								if [ "$?" -eq "0" ]
									then
										echo "OK"
								    echo ""
									else
										echo "FAILED"
										exit 1
								fi

                # Drupal deploy hooks
                # NOTE: Supported in Drush 10+ - so to avoid breaking deployments, will fail silently. Any reliance on this will not be tested
                echo "Run Drupal deploy hooks... "
                cd $WORKSPACE_PATH && $CLI_PHAR -v -y deploy:hook

                if [ "$?" -eq "0" ]
                  then
                    echo "OK"
                    echo ""
                  else
                    echo "FAILED"
                    # Fails silently, in cases of old Drush with no 'deploy' command
                fi
							else
								echo "FAILED"
								exit 1
						fi

						echo ""
					else
						echo "FAILED"
						exit 1
				fi
		fi

		echo "--------------------------------------------------------------------------------"
		echo "Build: SUCCESS"
		echo "--------------------------------------------------------------------------------"
		echo ""
		exit 0
	else
		echo "FAILED"
fi