#!/bin/bash

# Date string for database dump suffix
DATE=`date +%Y%m%d-%H%M%S`

# Environment we are building (dev, stage, prod, etc.)
# First arg is always the job name
JOB_ENV=`echo $1 | cut -d'-' -f2`