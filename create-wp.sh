#!/bin/bash
## Author: cyber01
## E-mail: sergey@brovko.pro

# NGINX / Binaries
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
FPM_SOCKET="/run/php/php7.0-fpm.sock"
WWW_DIR_MAIN_DIR="/var/www"
WWW_DIR_SITES_DIR="/var/www/main"
WP_CLI="/usr/bin/wp-cli"
OWNER="www-data"
GROUP="www-data"
DOMAIN=$1

# DB
MYSQL_ROOT_PASS=""
DB_NAME_REPLACE=${1//./_}
DB_NAME=${DB_NAME_REPLACE//-/_}
DB_LOGIN=$DB_NAME
DB_PASS=`pwgen -cnBv1 20`

# Wordpress
ADMIN_LOGIN=$2
ADMIN_PASS=`pwgen -cnBv1 20`
ADMIN_EMAIL=""
PLUGIN_LIST="wordpress-seo rustolat redirection autooptimize wp-smushit really-simple-ssl"

if [ "$(id -u)" != "0" ] 
then
   echo "This script must be run as root"
   exit 1
fi

if [ ! $# == 2 ]; then
  echo "Usage: $0 domain admin_login"
  exit 1
fi

function db_manager(){
	echo "Create DB"
	if [ -z $MYSQL_ROOT_PASS ]
	then
		mysql -uroot --execute="create database ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci;"
	    mysql -uroot --execute="GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_LOGIN}'@'localhost' IDENTIFIED by '${DB_PASS}'  WITH GRANT OPTION;"
	    echo "User and database created"
	else
		mysql -uroot -p${MYSQL_ROOT_PASS} --execute="create database ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci;"
	    mysql -uroot -p${MYSQL_ROOT_PASS} --execute="GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_LOGIN}'@'localhost' IDENTIFIED by '${DB_PASS}'  WITH GRANT OPTION;"
	    echo "User and database created"
	fi
}

function dir_manager(){
	echo "Create directory structure"
	if ! [ -d ${WWW_DIR_MAIN_DIR}/tmp ]; then
		mkdir ${WWW_DIR_MAIN_DIR}/tmp
		chown -R ${OWNER}:${GROUP} ${WWW_DIR_MAIN_DIR}/tmp
	fi	
	if ! [ -d ${WWW_DIR_SITES_DIR} ]; then
		mkdir -p ${WWW_DIR_SITES_DIR}
		chown -R ${OWNER}:${GROUP} ${WWW_DIR_SITES_DIR}
	fi
	mkdir -p ${WWW_DIR_SITES_DIR}/${DOMAIN}/{public_html,logs}
	chown -R ${OWNER}:${GROUP} ${WWW_DIR_SITES_DIR}/${DOMAIN}
	chmod 0750 ${WWW_DIR_SITES_DIR}/${DOMAIN}
	echo "Directory structure created"
}

function nginx_manager(){
	echo "Create nginx config"
	nginxconf="server {
    listen 80;
    listen [::]:80;

    root $WWW_DIR_SITES_DIR/$DOMAIN/public_html;
    index index.php index.html index.htm;

    server_name $DOMAIN www.$DOMAIN;
    access_log  $WWW_DIR_SITES_DIR/$DOMAIN/logs/access.log;
    error_log   $WWW_DIR_SITES_DIR/$DOMAIN/logs/error.log;

    include snippets/wp_security.conf;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
        expires max;
        log_not_found off;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(.*)\$;
        fastcgi_pass unix:$FPM_SOCKET;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_ignore_client_abort on;
        fastcgi_param  SERVER_NAME \$http_host;
    }
	}"
	touch ${NGINX_AVAILABLE}/${DOMAIN}.conf
	echo "$nginxconf" >> ${NGINX_AVAILABLE}/${DOMAIN}.conf
	ln -s ${NGINX_AVAILABLE}/${DOMAIN}.conf ${NGINX_ENABLED}/${DOMAIN}.conf
	echo "Config generated"
	echo "Check config and restart nginx"
	nginx -t && systemctl restart nginx
}

function wp_manager(){
	echo "Self update"
	${WP_CLI} cli update --allow-root
	echo "Download wordpress Core"
	${WP_CLI} core download --path=${WWW_DIR_SITES_DIR}/${DOMAIN}/public_html --locale=ru_RU --allow-root
	echo "Create config for wordpress"
	${WP_CLI} config create --path=${WWW_DIR_SITES_DIR}/${DOMAIN}/public_html --dbname=${DB_NAME} --dbuser=${DB_LOGIN} --dbpass=${DB_PASS} --dbhost=localhost --dbcharset=utf8mb4 --locale=ru_RU --allow-root
	echo "Install wordpress"
	${WP_CLI} core install --path=${WWW_DIR_SITES_DIR}/${DOMAIN}/public_html --url=${DOMAIN} --title="Example site" --admin_user=${ADMIN_LOGIN} --admin_password=${ADMIN_PASS} --admin_email=${ADMIN_EMAIL} --allow-root
	echo "Install additional plugins: $PLUGIN_LIST"
	${WP_CLI} plugin install ${PLUGIN_LIST} --activate --path=${WWW_DIR_SITES_DIR}/${DOMAIN}/public_html --allow-root
	chown -R ${OWNER}:${GROUP} ${WWW_DIR_SITES_DIR}/${DOMAIN}

}

function results(){
	echo "**************************************"
	echo "***************[DOMAIN]***************"
	echo "Installed Wordpress: `${WP_CLI} core version --path=${WWW_DIR_SITES_DIR}/${DOMAIN}/public_html`"
	echo "DOMAIN: $DOMAIN"
	echo "ADMIN LOGIN: $ADMIN_LOGIN"
	echo "ADMIN PASS: $ADMIN_PASS"
	echo ""
	echo "**************[DATABASE]**************"
	echo "DB NAME: $DB_NAME"
	echo "DB LOGIN: $DB_LOGIN"
	echo "DB PASS: $DB_PASS"
	echo "**************************************"
}

db_manager
dir_manager
nginx_manager
wp_manager
results
