#!/bin/bash

if [ $# -lt 1 ]
  then
    echo "Required arguments; PROJECT_NAME"
    exit 1
fi

# $1 = PROJECT_NAME
if ! [[ "$1" =~ ^[a-zA-Z0-9_\-]+$ ]]
    then
        echo "Invalid PROJECT_NAME"
        exit 1
fi
PROJECT_NAME=$1

echo "--------------------------------------------------------------------------------"
echo "NOT IMPLEMENTED"
echo "--------------------------------------------------------------------------------"
echo ""
exit 0