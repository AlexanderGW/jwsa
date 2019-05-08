#! /bin/bash

REVERT=0

# Check current Drupal environment status
echo "Drupal bootstrap..."
$SSH_CONN \
	"$CLI_PHAR --root=$WEBROOT status bootstrap | grep -q Successful"
BOOTSTRAP=$?

if [ "$BOOTSTRAP" -eq "0" ]
    then
        echo "OK"

        # Make a copy of current build into the new build on dest, to ease diff sync
		if [ "$LAST_BUILD_ID" -gt "0" ]
			then
				echo ""
				echo "Copy $DEST_BUILDS_PATH/$LAST_BUILD_ID >> $DEST_BUILD_PATH"
				$SSH_CONN \
					"cp -R $DEST_BUILDS_PATH/$LAST_BUILD_ID/* $DEST_BUILD_PATH"
		fi
	else
		echo "FAILED"
fi