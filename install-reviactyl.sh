#!/usr/bin/env bash
# Direct uitvoerbaar: Pterodactyl Panel + Reviactyl
# Domein panel: panel.fivem-node.nl
# Node: node01.fivem-node.nl (token later)
# Admin account: Server Server / Admin / Lu12ca!!

set -euo pipefail
IFS=$'\n\t'

# CONFIGURATIE
PANEL_DOMAIN="panel.fivem-node.nl"
NODE_DOMAIN="node01.fivem-node.nl"
WEBROOT="/var/www/pterodactyl"
DB_NAME="pterodactyl"
DB_USER="ptero"
DB_PASS="Lu12ca!!"
ADMIN_EMAIL="admin@admin.com"  # vul hier je echte email in

echo "[INFO] Start installatie Reviactyl + Panel..."

# 1️⃣ Systeem update & dependencies
apt update -y
apt install -y curl wget git unzip software-properties-common ca-certificates apt-transport-https lsb-release gnupg ufw

# 2️⃣ PHP & MySQL & Redis
add-apt-repository ppa:ondrej/php -y
apt update -y
apt install -y php8.2 php8.2-{cli,common,gd,mysql,mbstring,bcmath,xml,curl,zip,fpm}
apt install -y mysql-server redis-server

mysql -u root <<EOF
CREATE DATABASE ${DB_NAME};
CREATE USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

# 3️⃣ Panel downloaden
mkdir -p ${WEBROOT}
cd ${WEBROOT}
curl -sLo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
rm panel.tar.gz

cp .env.example .env
sed -i "s|APP_URL=.*|APP_URL=https://${PANEL_DOMAIN}|" .env
sed -i "s/DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=${DB_USER}/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env

curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
composer install --no-dev --optimize-autoloader
php artisan key:generate --force
php artisan migrate --seed --force

# 4️⃣ Admin account aanmaken
php artisan p:user:make \
    --email="${ADMIN_EMAIL}" \
    --username="Admin" \
    --name-first="Server" \
    --name-last="Server" \
    --password="${DB_PASS}" \
    --admin=1

chown -R www-data:www-data ${WEBROOT}
chmod -R 755 ${WEBROOT}/storage ${WEBROOT}/bootstrap/cache

# 5️⃣ Nginx configuratie
apt install -y nginx
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/sites-available/reviactyl.conf <<NGINX
server {
    listen 80;
    server_name ${PANEL_DOMAIN};
    root ${WEBROOT}/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
NGINX

ln -s /etc/nginx/sites-available/reviactyl.conf /etc/nginx/sites-enabled/
systemctl restart nginx

# 6️⃣ SSL via Certbot
apt install -y certbot python3-certbot-nginx
certbot --nginx -d ${PANEL_DOMAIN} -m ${ADMIN_EMAIL} --agree-tos --redirect --non-interactive

# 7️⃣ Reviactyl installeren vanuit GitHub
echo "[INFO] Reviactyl installeren vanuit GitHub..."
git clone https://github.com/Luca918-spotters/vps.git /tmp/reviactyl
bash /tmp/reviactyl/reviactyl
rm -rf /tmp/reviactyl

# 8️⃣ Wings node installeren (token later)
ssh root@${NODE_DOMAIN} bash -s <<'EOF'
apt update -y
apt install -y curl wget
curl -sSL https://get.docker.com/ | bash
systemctl enable --now docker
mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
chmod +x /usr/local/bin/wings
echo "⚠️ Node Token + config.yml moet later handmatig worden toegevoegd via panel"
EOF

# 9️⃣ Firewall
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "[DONE] Reviactyl + Panel + Wings klaar!"
echo "Panel: https://${PANEL_DOMAIN}"
echo "Admin: Admin / Lu12ca!!"
echo "Wings node token moet nog via panel worden toegevoegd"
