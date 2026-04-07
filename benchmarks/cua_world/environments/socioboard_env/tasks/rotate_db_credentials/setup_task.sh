#!/bin/bash
echo "=== Setting up rotate_db_credentials task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_time.txt

# Ensure services are running
systemctl start mariadb 2>/dev/null || true
systemctl start mongod 2>/dev/null || true
sleep 3

# Make sure PM2 services are running as the default user (root)
cd /opt/socioboard/socioboard-api/user && pm2 start user.js --name "user-service" 2>/dev/null || true
cd /opt/socioboard/socioboard-api/feeds && pm2 start feeds.js --name "feeds-service" 2>/dev/null || true
cd /opt/socioboard/socioboard-api/publish && pm2 start publish.js --name "publish-service" 2>/dev/null || true
cd /opt/socioboard/socioboard-api/notification && pm2 start notification.js --name "notification-service" 2>/dev/null || true
pm2 save 2>/dev/null || true

# Give services time to spin up
sleep 3

# Ensure we start with the old password (in case of a previous interrupted run)
mysql -u root -e "ALTER USER 'socioboard'@'localhost' IDENTIFIED BY 'SocioPass2024!';" 2>/dev/null || true
mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true

# Make sure all configuration files have the old password set
python3 << 'PYEOF'
import os

files_to_check = [
    "/opt/socioboard/socioboard-api/library/sequelize-cli/config/config.json",
    "/opt/socioboard/socioboard-api/user/config/development.json",
    "/opt/socioboard/socioboard-api/feeds/config/development.json",
    "/opt/socioboard/socioboard-api/publish/config/development.json",
    "/opt/socioboard/socioboard-api/notification/config/development.json",
    "/opt/socioboard/socioboard-web-php/.env",
    "/opt/socioboard/socioboard-web-php/environmentfile.env"
]

for f in files_to_check:
    if os.path.exists(f):
        with open(f, 'r') as file:
            content = file.read()
        if "SecureS0cial2026#" in content:
            content = content.replace("SecureS0cial2026#", "SocioPass2024!")
            with open(f, 'w') as file:
                file.write(content)
PYEOF

# Restart to pick up the confirmed old passwords
pm2 restart all 2>/dev/null || true

take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="