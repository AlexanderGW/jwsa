# Jenkins Web Scripts by Alex

BASH scripts to running important Drush/WP-CLI commands for build, and deployment tasks.

Call these scripts from Declarative Pipelines steps, or as an executed shell script (if using the execute script method, the environment variables that you pass to the shell would be `${JOB_NAME}` instead of `${env.JOB_NAME}` used in Groovy pipelines)

The `deploy-test` project template is based on a Composer Drupal <https://github.com/drupal-composer/drupal-project> PuPHPet <https://puphpet.com> Vagrant environment

<https://gailey-white.com/jenkins-web-scripts-by-alex>

### Script limitations
These scripts expect a partial pre-exisiting environment setup (databases, and populated `.env` files).

### Caveat
Completely removing a Composer CMS dependency (such as a Drupal module) will require an initial deployment 
to disable and remove the module in config, before removing the dependency codebase. Otherwise you remove the code, before formally uninstalling it within Drupal.

A solution to this, would be to create a module to handle 'releases'.

```
function HOOK_update_8001(&$sandbox) {
  // Perform data handling and uninstall tasks here...
  \Drupal::service('module_installer')->uninstall(['mymodule']);
}
```

### Pipeline example
Example of the build and deploy scripts, used in Jenkins pipeline steps.

```
stage('Build') {
	steps {
		sh "~/jwsa/build.sh ${env.JOB_NAME} ${env.WORKSPACE} /path/to/project/envs/${env.JOB_NAME}/.env"
	}
}

stage("Deploy") {
	steps {
		sh "~/jwsa/deploy.sh ${env.JOB_NAME} ${env.WORKSPACE} ${env.BUILD_ID}"
	}
}
```

### To build the workspace.

`/path/to/build.sh ${env.JOB_NAME} ${env.WORKSPACE} /path/to/env-files/${env.JOB_NAME}/.env`

- SSH connection test
- Bootstrap test
- Import database from remote
- Run database routines

### To deploy the workspace, to the environment.

`/path/to/deploy.sh ${env.JOB_NAME} ${env.WORKSPACE} ${env.JOB_ID}`

- SSH connection test
- Directory structure test
- Bootstrap test
- Rsync build (Make a copy of previous build if bootstrap successful, to ease transfer time)
- Enable maintenance mode
- Backup database
- Switch build symlinks
- Run database routines
- Disable maintenance
- Clean up old builds
- NOTE: Build will be reverted if any of the routines fail.

### Setting up a project

The `~/project` directory is where `$PROJECT_NAME` directories are kept, holding variables, and optional web configs (named `$PROJECT_NAME`.conf, within their respective `$SERVICE` directories) for the build and deploy tasks.

### The .env template

```
MYSQL_DATABASE="dbname"
MYSQL_HOSTNAME="localhost"
MYSQL_PASSWORD="123"
MYSQL_PORT=3306
MYSQL_USER="dbuser"
HASH_SALT="your-salt-here"
APP_ENV="dev"
```

### Maria/MySQL credentials

All of these commands run without credentials. Setup a `~/.my.cnf` for the `$DEST_SSH_USER` using a similar template as below.

```
[mysql]
 user = myuser
 password = secret
 
[mysqldump]
 user = myuser
 password = secret
```

### Can I display this information within the CMS?

#### Drupal 7 module
Comming soon...

#### Drupal 8 module
<https://github.com/AlexanderGW/jwsa_build_info_drupal>

#### WordPress module
Comming soon...

### Rsync
The rsync command for webserver configs, requires `sudo` access. Add the following to `sudo visudo` to allow this.

```
<username> ALL=NOPASSWD:<path to rsync>
```