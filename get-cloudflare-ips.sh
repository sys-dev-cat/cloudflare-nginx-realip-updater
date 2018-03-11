#!/bin/bash

###############################################################
# cloudflare ip/network update for nginx real ip module
###############################################################
#
# This script auto-updates the list of ip/networks from cloudflare
# and reloads nginx in case of any change.
#
# First of all create an empty file wherever NGINX_CFG is pointing, and
# launch the script. Don't forget to add a line including the config in
# your nginx config: include /etc/nginx/cloudflare.conf;
#
# Sources:
# https://support.cloudflare.com/hc/en-us/articles/200170706-How-do-I-restore-original-visitor-IP-with-Nginx-
# https://www.cloudflare.com/ips/
# 
###############################################################


URL="https://www.cloudflare.com"
IPS="ips-v4 ips-v6"
TMP_CFG="/tmp/cloudflare.conf"
NGINX_CFG="/etc/nginx/cloudflare.conf"
USE_X_FORWARDED_FOR="true"

check_nginx(){
	2>&1 nginx -V | xargs -n1 | grep with-http_realip_module >/dev/null || abort "Please recompile nginx with realip module support"
}

abort() {
        echo "$1";
        exit 1;
}

get() {
	rm -f "$2"
	/usr/bin/wget "$1" -O "$2" >/dev/null 2>&1 || abort "Error downloading $2"
}

replace(){
	cp -f "$1" "$2"
	nginx -t >/dev/null 2>&1 || abort "Something went wrong, please review nginx -t output"
	systemctl reload nginx
}

# Check if nginx has realip module support
check_nginx

# Get the ip lists from cloudflare, fail if something goes wrong
for x in $IPS
do
	get "$URL/$x" "/tmp/$x"
done

# remove the previous tmp file if exists
rm -f "$TMP_CFG"

# Recreate the file starting with this comment
echo "#Cloudflare Stuff:" >> "$TMP_CFG"

# For each ip/network in each file create a line for the real ip module.
for x in $IPS
do
	for y in `cat "/tmp/$x"`
	do
		echo "set_real_ip_from $y;" >> "$TMP_CFG"
	done
done

# Use the X-Forwarded-For: header, alternatively you can use:
# real_ip_header CF-Connecting-IP;
# use just one.
if [ "$USE_X_FORWARDED_FOR" == "true" ]
then 
	echo "real_ip_header X-Forwarded-For;" >> "$TMP_CFG"
else
	echo "real_ip_header CF-Connecting-IP;" >> "$TMP_CFG"
fi

# Compare the generated file with the previous file, if needed replace it and reload nginx.
/usr/bin/diff "$NGINX_CFG" "$TMP_CFG" >/dev/null 2>&1 || replace "$TMP_CFG" "$NGINX_CFG"

# Remove the new temporal file
rm -f "$TMP_CFG"
