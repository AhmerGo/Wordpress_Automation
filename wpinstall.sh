#!/bin/bash
usage() {
  echo "Usage: $0 subdomain.domain [--type=all]"
  exit 1
}

# Check if the script is run as root or with sudo
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

# Check the number of arguments passed to the script
if [ "$#" -lt 1 ]; then
    usage
fi

# Process command-line arguments
full_domain=$1
type="default"

if [ "$#" -eq 3 ]; then
    if [ "$2" = "--type" ]; then
        type=$3
    else
        usage
    fi
fi





# Define variables

prefix=$(echo "$full_domain" | cut -d'.' -f1)
aws_profile="sa_dns_user"
base_domain=$(echo "$full_domain" | sed 's/^[^.]*\.//')  # Extract base domain
db_name="${prefix}_db"
db_user="${prefix}_user"
wp_title="Your WordPress Site for ${prefix}"
wp_admin_user="${prefix}"
wp_admin_password="${prefix}"
certbot_email="gondal.ahmer@yahoo.com"

echo "Please enter the database password:"
read -s db_password
echo "Please confirm the database password:"
read -s db_password_confirm

if [ "$db_password" != "$db_password_confirm" ]; then
    echo "Passwords do not match."
    exit 1
fi





# Step 1: Update and install prerequisites
apt-get update

# List of packages to install
#packages=("apache2" "php" "php-mysql" "certbot" "python3-certbot-apache" "jq"))

# Function to check if a package is installed
#is_package_installed() {
 #   dpkg -l | grep -q $1
#}

# Iterate through the packages and install them if not already installed
#for package in "${packages[@]}"; do
 #   if ! is_package_installed "$package"; then
  #      sudo apt-get install -y "$package"
   # else
    #    echo "$package is already installed."
 #   fi
#done

# Step 2: Create a MySQL database and user in one statement with modified password policy
mysql -e "CREATE DATABASE $db_name;" -e "SET GLOBAL validate_password_policy=LOW;" -e "SET GLOBAL validate_password_length = 2;" -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_password';" -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';" -e "FLUSH PRIVILEGES;" -p

# Step 3: Install WordPress
mkdir -p /var/www/sites/$full_domain
cd /var/www/sites/$full_domain
mkdir logs
mkdir html
cd logs
touch error.log
touch access.log
cd ..
cd html
wget https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz
rm latest.tar.gz
mv wordpress/* .
rmdir wordpress
cp wp-config-sample.php wp-config.php
chown -R www-data:www-data /var/www/sites/$full_domain/html
find /var/www/sites/$full_domain/html -type d -exec chmod 755 {} \;
find /var/www/sites/$full_domain/html -type f -exec chmod 644 {} \;



# Geneate random salts and keys and update wp-config.php
wget -qO- https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config.php

# Configure wp-config.php with database details
sed -i "s/database_name_here/$db_name/" wp-config.php
sed -i "s/username_here/$db_user/" wp-config.php
sed -i "s/password_here/$db_password/" wp-config.php

# Step 4: Create Apache Virtual Host configuration
cat <<EOF > /etc/apache2/sites-available/$full_domain.conf
<VirtualHost *:80>
    ServerAdmin admin@$base_domain
    ServerName $full_domain
    DocumentRoot /var/www/sites/$full_domain/html
    ErrorLog /var/www/sites/$full_domain/logs/error.log
    CustomLog /var/www/sites/$full_domain/logs/access.log combined
</VirtualHost>

<Directory "/var/www/sites/$full_domain/html">
    Options FollowSymLinks
    AllowOverride None
    Order allow,deny
    Allow from all
</Directory>
EOF

# Step 5: Enable the Virtual Host
a2ensite $full_domain

# Step 6: Reload Apache
systemctl reload apache2

certbot --apache -d $full_domain -m gondal.ahmer@yahoo.com --agree-tos

systemctl reload apache2

# Step 7: Create WordPress admin user
wp --allow-root core install --url="https://$full_domain" --title="$wp_title" --admin_user="$wp_admin_user" --admin_password="$wp_admin_password" --admin_email="$certbot_email"

# Step 8: Get the hosted zone ID for your base domain
hosted_zone_info=$(aws route53 list-hosted-zones --profile "$aws_profile")

hosted_zone_id=$(echo "$hosted_zone_info" | jq -r ".HostedZones[] | select(.Name == \"$base_domain.\") | .Id")
extracted_id="${hosted_zone_id##*/}"



# Check if the hosted_zone_id is empty (domain not found)
if [ -z "$hosted_zone_id" ]; then
  echo "Error: Hosted zone ID not found for domain $base_domain."
  exit 1
fi

# Step 9: Create dns.json file
dns_json='{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "'"$full_domain"'",
        "Type": "A",
        "TTL": 3600,
        "ResourceRecords": [
          {
            "Value": "'$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)'"
          }
        ]
      }
    }
  ]
}'
echo "$dns_json" > /root/dns.json  # Change the path as needed

# Step 10: Change DNS record using the dns.json file
aws route53 change-resource-record-sets --hosted-zone-id="$extracted_id" --profile sa_dns_user --change-batch file:///root/dns.json

