#!/bin/bash

if [ -z "$1" ]
then
  echo "Usage $0 <RUDDER_SERVER_NAME>"
  exit 1
fi
RUDDER_WEB="$1"

# add repository
./add_repo 3.1

. detect_os.sh

# This is copied from http://www.rudder-project.org/rudder-doc-2.11/rudder-doc.html#relay-servers
if [ "${OS}" = "RHEL" ] ; then
  ${PM_COMMAND} rudder-agent httpd rsyslog
elif [ "${OS}" = "UBUNTU" -o "${OS}" = "DEBIAN" ] ; then
  ${PM_COMMAND} rudder-agent apache2 apache2-utils rsyslog
  A2_VERSION=`apachectl -v | head -n1  | sed -s 's/Server version: Apache\/\([0-9]\+\.[0-9]\+\)\..*/\1/'`
  a2enmod dav dav_fs
  if [ "${A2_VERSION}" = "2.4" ] ; then
    a2dissite 000-default
  else
    a2dissite default
  fi
elif [ "${OS}" = "SLES" ] ; then
  ${PM_COMMAND} install apache2 rsyslog
  a2enmod dav dav_fs
fi
A2_VERSION=`apachectl -v | head -n1  | sed -s 's/Server version: Apache\/\([0-9]\+\.[0-9]\+\)\..*/\1/'`

# Declare server role manually, no packages for this role yet
mkdir -p /opt/rudder/etc/server-roles.d
touch /opt/rudder/etc/server-roles.d/rudder-relay-top

# prepare apache
mkdir -p /opt/rudder/etc /var/log/rudder/apache2 /var/rudder/share
for i in /var/rudder/inventories/incoming /var/rudder/inventories/accepted-nodes-updates
do
  mkdir -p ${i}
  chmod -R 1770 ${i}
  for group in apache www-data www; do
    if getent group ${group} > /dev/null; then chown -R root:${group} ${i}; break; fi
  done
done

for i in /opt/rudder/etc/htpasswd-webdav-initial /opt/rudder/etc/htpasswd-webdav
do
  /usr/bin/htpasswd -bc ${i} rudder rudder
done

touch /opt/rudder/etc/rudder-networks.conf

if [ "${OS}" = "RHEL" ] ; then
  vhost_file=/etc/httpd/conf.d/rudder-default.conf
elif [ "${OS}" = "UBUNTU" -o "${OS}" = "DEBIAN" ] ; then
  if [ "${A2_VERSION}" = "2.4" ] ; then
    vhost_file=/etc/apache2/sites-enabled/rudder-default.conf
  else
    vhost_file=/etc/apache2/sites-enabled/rudder-default
  fi
elif [ "${OS}" = "SLES" ] ; then
  vhost_file=/etc/apache2/vhosts.d/rudder-default.conf
fi

cat > "${vhost_file}" << EOF
<VirtualHost *:80>
        ServerAdmin webmaster@localhost
        # Expose the server UUID through http
        Alias /uuid /opt/rudder/etc/uuid.hive
        <Directory /opt/rudder/etc>
                Order deny,allow
                Allow from all
        </Directory>
        # WebDAV share to receive inventories
        Alias /inventories /var/rudder/inventories/incoming
        <Directory /var/rudder/inventories/incoming>
                DAV on
                AuthName "WebDAV Storage" 
                AuthType Basic
                AuthUserFile /opt/rudder/etc/htpasswd-webdav-initial
                Require valid-user
                Order deny,allow
                # This file is automatically generated according to
                # the hosts allowed by rudder.
                Include /opt/rudder/etc/rudder-networks.conf
                <LimitExcept PUT>
                        Order allow,deny
                        Deny from all
                </LimitExcept>
        </Directory>
        # WebDAV share to receive inventories
        Alias /inventory-updates /var/rudder/inventories/accepted-nodes-updates
        <Directory /var/rudder/inventories/accepted-nodes-updates>
                DAV on
                AuthName "WebDAV Storage" 
                AuthType Basic
                AuthUserFile /opt/rudder/etc/htpasswd-webdav
                Require valid-user
                Order deny,allow
                # This file is automatically generated according to
                # the hosts allowed by rudder.
                Include /opt/rudder/etc/rudder-networks.conf
                <LimitExcept PUT>
                        Order allow,deny
                        Deny from all
                </LimitExcept>
        </Directory>
        # Logs
        ErrorLog /var/log/rudder/apache2/error.log
        LogLevel warn
        CustomLog /var/log/rudder/apache2/access.log combined

</VirtualHost>
EOF

if [ "${OS}" = "RHEL" ] ; then
  service httpd restart
elif [ "${OS}" = "UBUNTU" -o "${OS}" = "DEBIAN" ] ; then
  a2ensite rudder-default
  service apache2 restart
elif [ "${OS}" = "SLES" ] ; then
  service apache2 restart
fi

# Set the policy server to be server 4 (rudder-web)
echo "${RUDDER_WEB}" > /var/rudder/cfengine-community/policy_server.dat
service rudder-agent restart

# Store the UUID of this node for later user
FRONT_UUID=$(cat /opt/rudder/etc/uuid.hive)
echo "FRONT_UUID=${FRONT_UUID}" 

# If you're using a firewall, allow the following incoming connections to this server:
# - TCP port 80: all managed nodes
# - TCP port 5309: all managed nodes
# - UDP and TCP port 514: all managed nodes  
