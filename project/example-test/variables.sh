#! /bin/bash

# CMS type (drupal7, drupal8, wordpress)
TYPE='drupal8'

# Webserver environment (apache, nginx)
WEBSERVER='nginx'

# Destination host
DEST_HOST='deploy.test';

# REMEMBER: SSH keys need to be manually installed on the Jenkins deployment server.
DEST_IDENTITY='/var/lib/jenkins/.ssh/deploy-test';

# Base deployment path
DEST_PATH="/var/deploy/$PROJECT_NAME"

# Product database dump location for reversion
DEST_DUMP_PATH="$DEST_PATH/backup"

# Site assets
DEST_ASSET_PATH="$DEST_PATH/files"

# Location of all deployed builds
DEST_BUILDS_PATH="$DEST_PATH/build"

# Location of this build
DEST_BUILD_PATH="$DEST_BUILDS_PATH/$BUILD_ID"

# Site Twig storage
DEST_STORAGE_PATH="$DEST_PATH/storage"

# Location of this build
DEST_PRIVATE_PATH="$DEST_PATH/private"

# Users
DEST_SSH_USER='root';
DEST_WEB_USER='www-data';

# Databases
SRC_DATABASE_NAME=$PROJECT_NAME;
DEST_DATABASE_NAME=$PROJECT_NAME;

# Webroot locations for build symlinks
DEST_WEBROOT_PATH="/var/www/$PROJECT_NAME"
DEST_BUILD_ASSETS_PATH="$DEST_BUILD_PATH/web/sites/default/files"

# Settings location
DEST_BUILD_SETTINGS_PATH="$DEST_BUILD_PATH/web/sites/default/settings.php"

# CLI tool (Drush, WP-CLI)
CLI_PHAR="vendor/bin/drush"

# Services to restart
declare -a DEST_SERVICES=("php-fpm" "nginx")
declare -a DEST_SERVICES_RESTART=("php-fpm")
declare -a DEST_SERVICES_RELOAD=("nginx")

# Database table data to ignore
declare -a DATABASE_TABLE_NO_DATA=(
"cache",
"cache_bootstrap"
"cache_block"
"cache_config"
"cache_field"
"cache_menu"
"cache_tags"
"cache_toolbar"
"cache_views_info"
"watchdog"
)

# Run commands prior to the platform stage of the build
declare -a BUILD_CMDS_PRE_PLATFORM=(
"echo \"foobar\""
)

# Use MySQL wildcard '%' for host
#USE_MYSQL_HOST_WILDCARD=1

# Rsync flags and parameters
# REMEMBER: Exclude .env, assets, cache, test, and tool directories to speed up transfers
# MUST: Suffix with the with "-e" flag, to allow succeeding text to be executed remotely.
RSYNC_FLAGS="-al --stats --delete-before --exclude=.env --exclude=.git --exclude=.sass-cache --exclude=node_modules --exclude=simpletest --exclude=tests --exclude=/storage --exclude=/private --exclude=/web/sites/default/files -e"

# SSH connection string
SSH_CONN="ssh -i $DEST_IDENTITY $DEST_SSH_USER@$DEST_HOST"