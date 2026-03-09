#!/bin/bash
# Socioboard 4.0 Setup Script (post_start hook)
# Waits for npm/composer install, configures databases, sets up app, starts services, launches Firefox.

set -e

echo "=== Setting up Socioboard 4.0 ==="

SOCRDIR="/opt/socioboard"
SOCR_URL="http://localhost"
DB_NAME="socioboard"
DB_USER="socioboard"
DB_PASS="SocioPass2024!"
MONGO_DB="socioboard"
ADMIN_EMAIL="admin@socioboard.local"
ADMIN_PASS="Admin2024!"
ADMIN_USER="admin"

# ============================================================
# Wait for background npm/composer install to finish
# ============================================================
echo "Waiting for background npm/composer install to complete..."
TIMEOUT=1800  # 30 minutes
ELAPSED=0
while [ ! -f /tmp/socioboard_install_complete.marker ]; do
  sleep 15
  ELAPSED=$((ELAPSED + 15))
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: Background install timed out after ${TIMEOUT}s"
    echo "--- Last 50 lines of background install log ---"
    tail -50 /tmp/socioboard_bg_install.log 2>/dev/null || true
    exit 1
  fi
  echo "  Still waiting for install... ${ELAPSED}s elapsed"
done
echo "Background install completed! (${ELAPSED}s)"

# ============================================================
# Start MariaDB and MongoDB
# ============================================================
echo "Starting MariaDB..."
systemctl start mariadb
sleep 3

# Wait for MariaDB readiness
for i in $(seq 1 30); do
  if mysqladmin ping -h localhost --silent 2>/dev/null; then
    echo "MariaDB ready after ${i} attempts"
    break
  fi
  sleep 2
done

echo "Starting MongoDB..."
systemctl start mongod
sleep 3

# Wait for MongoDB readiness
# Note: mongosh outputs { ok: 1 } (no quotes), not "ok": 1
for i in $(seq 1 30); do
  if mongosh --quiet --eval "db.runCommand({ping: 1})" --norc 2>/dev/null | grep -qE 'ok.*1|"ok".*1'; then
    echo "MongoDB ready (mongosh)"
    break
  fi
  # fallback for older mongo shell
  if mongo --quiet --eval "db.runCommand({ping: 1})" 2>/dev/null | grep -qE 'ok.*1|"ok".*1'; then
    echo "MongoDB ready (legacy shell)"
    break
  fi
  # Direct check via netcat
  if nc -z localhost 27017 2>/dev/null; then
    echo "MongoDB port 27017 open - assuming ready"
    break
  fi
  sleep 2
done

# ============================================================
# Configure MariaDB: Create database and user
# ============================================================
echo "Configuring MariaDB database..."
mysql -u root << EOSQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO 'root'@'localhost';
FLUSH PRIVILEGES;
EOSQL

echo "MariaDB database '${DB_NAME}' configured"

# ============================================================
# Configure MongoDB: Initialize database (no auth mode)
# MongoDB runs WITHOUT authentication to keep setup simple
# ============================================================
echo "Configuring MongoDB (no-auth mode)..."
MONGO_SHELL=""
if command -v mongosh >/dev/null 2>&1; then
  MONGO_SHELL="mongosh"
elif command -v mongo >/dev/null 2>&1; then
  MONGO_SHELL="mongo"
fi

if [ -n "$MONGO_SHELL" ]; then
  $MONGO_SHELL --quiet --eval "
    use ${MONGO_DB};
    db.init_collection.insertOne({ setup: true, ts: new Date() });
  " --norc 2>/dev/null || true
  echo "MongoDB '${MONGO_DB}' database initialized"
fi

# ============================================================
# Configure Sequelize (MariaDB) connection
# ============================================================
echo "Configuring Sequelize database connection..."
SEQ_CONFIG="$SOCRDIR/socioboard-api/library/sequelize-cli/config/config.json"
if [ -f "$SEQ_CONFIG" ]; then
  python3 << PYEOF
import json, sys

config_file = "$SEQ_CONFIG"
try:
    with open(config_file, 'r') as f:
        config = json.load(f)

    for env in ['development', 'apidevelopment', 'test', 'production', 'staging', 'phpdev', 'apistaging']:
        if env in config:
            config[env]['username'] = '$DB_USER'
            config[env]['password'] = '$DB_PASS'
            config[env]['database'] = '$DB_NAME'
            config[env]['host'] = '127.0.0.1'
            config[env]['dialect'] = 'mysql'

    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
    print("Sequelize config updated successfully")
except Exception as e:
    print(f"WARNING: Could not update sequelize config: {e}", file=sys.stderr)
PYEOF
else
  echo "WARNING: Sequelize config not found at $SEQ_CONFIG"
fi

# ============================================================
# Run database migrations and seed
# ============================================================
echo "Running Sequelize migrations..."
SEQ_CLI_DIR="$SOCRDIR/socioboard-api/library/sequelize-cli"
if [ -d "$SEQ_CLI_DIR" ]; then
  cd "$SEQ_CLI_DIR"
  # Install mysql2 driver locally if needed
  npm install mysql2 --save 2>/dev/null || true
  NODE_ENV=development npx sequelize-cli db:migrate 2>&1 | tail -20 || \
    NODE_ENV=development sequelize db:migrate 2>&1 | tail -20 || \
    echo "WARNING: Migrations may have failed"

  echo "Running database seed..."
  NODE_ENV=development npx sequelize-cli db:seed --seed 20190213051930-initialize_application_info.js 2>&1 | tail -10 || \
    NODE_ENV=development sequelize db:seed --seed 20190213051930-initialize_application_info.js 2>&1 | tail -10 || \
    echo "WARNING: Seeding may have failed"
fi

# ============================================================
# CRITICAL FIX: Sequelize isUrl validator rejects localhost URLs
# The user_details model uses isUrl: { args: true } for profile_picture
# which calls validator.js isURL() with require_tld: true by default.
# http://localhost/... fails because "localhost" has no TLD.
# Fix: set require_tld: false to allow localhost URLs.
# ============================================================
echo "Applying Sequelize isUrl validator fix for localhost profile_picture..."
USER_DETAILS_MODEL="$SOCRDIR/socioboard-api/library/sequelize-cli/models/user_details.js"
if [ -f "$USER_DETAILS_MODEL" ]; then
  python3 << 'FIXEOF'
import re
model_path = "/opt/socioboard/socioboard-api/library/sequelize-cli/models/user_details.js"
with open(model_path, 'r') as f:
    content = f.read()
old = '        isUrl: {\n          args: true,\n          msg: "profile_picture is not in valid url."'
new = '        isUrl: {\n          args: { require_tld: false },\n          msg: "profile_picture is not in valid url."'
if old in content:
    content = content.replace(old, new)
    with open(model_path, 'w') as f:
        f.write(content)
    print("  isUrl fix applied: require_tld: false")
else:
    print("  WARNING: isUrl pattern not found in model (may already be fixed or changed)")
FIXEOF
else
  echo "WARNING: $USER_DETAILS_MODEL not found"
fi

# CRITICAL FIX 2: Sequelize v5 strips 'args' from isUrl/isURL/isEmail validators (instance-validator.js bug).
# The 'isUrl' wrapper in validator-extras.js calls this.isURL(str) without passing options.
# Fix: change isUrl wrapper to use require_tld: false by default.
VALIDATOR_EXTRAS="$SOCRDIR/socioboard-api/library/node_modules/sequelize/lib/utils/validator-extras.js"
if [ -f "$VALIDATOR_EXTRAS" ]; then
  python3 << 'FIXEOF2'
path = "/opt/socioboard/socioboard-api/library/node_modules/sequelize/lib/utils/validator-extras.js"
with open(path) as f:
    content = f.read()
old = '''  isUrl(str) {
    return this.isURL(str);
  },'''
new = '''  isUrl(str) {
    return this.isURL(str, { require_tld: false });
  },'''
if old in content:
    with open(path, 'w') as f:
        f.write(content.replace(old, new))
    print("  validator-extras.js fix applied: require_tld: false")
else:
    print("  WARNING: validator-extras.js pattern not found (may already be fixed)")
FIXEOF2
else
  echo "WARNING: $VALIDATOR_EXTRAS not found"
fi

# ============================================================
# Configure MongoDB connection in each microservice
# CRITICAL: MongoDB runs WITHOUT auth; clear all auth fields
# CRITICAL: Must set db_name (not dbname/database/db)
# ============================================================
echo "Configuring MongoDB connections for microservices..."
python3 << 'PYEOF'
import json, sys, os

SOCRDIR = "/opt/socioboard"
MONGO_DB = "socioboard"

for svc in ["user", "feeds", "notification", "publish"]:
    conf_file = f"{SOCRDIR}/socioboard-api/{svc}/config/development.json"
    if not os.path.exists(conf_file):
        print(f"WARNING: {conf_file} not found, skipping", file=sys.stderr)
        continue

    try:
        with open(conf_file, 'r') as f:
            data = json.load(f)

        def fix_mongo(obj):
            """Recursively find mongo config objects and fix them."""
            if isinstance(obj, dict):
                for k, v in obj.items():
                    if isinstance(v, dict) and ('mongo' in k.lower() or 'mongoose' in k.lower()):
                        # Fix db_name (actual key used by Socioboard 4.0)
                        for dk in ['db_name', 'dbname', 'database', 'db']:
                            if dk in v:
                                v[dk] = MONGO_DB
                        # Add db_name if missing
                        if 'db_name' not in v:
                            v['db_name'] = MONGO_DB
                        # Clear auth credentials (MongoDB runs without auth)
                        for auth_key in ['username', 'user', 'password', 'pwd', 'pass']:
                            if auth_key in v:
                                v[auth_key] = ""
                        # Ensure host/port are correct
                        if 'host' not in v:
                            v['host'] = 'localhost'
                        if 'port' not in v:
                            v['port'] = 27017
                    elif isinstance(v, (dict, list)):
                        fix_mongo(v)
            elif isinstance(obj, list):
                for item in obj:
                    fix_mongo(item)

        fix_mongo(data)

        with open(conf_file, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"Updated MongoDB config for {svc}")
    except Exception as e:
        print(f"WARNING: Could not update config for {svc}: {e}", file=sys.stderr)
PYEOF

# ============================================================
# Configure PHP Laravel frontend
# ============================================================
echo "Configuring PHP Laravel frontend..."
PHP_DIR="$SOCRDIR/socioboard-web-php"

if [ -d "$PHP_DIR" ]; then
  cd "$PHP_DIR"

  # Create .env file
  ENV_TEMPLATE=""
  [ -f environmentfile.env ] && ENV_TEMPLATE="environmentfile.env"
  [ -z "$ENV_TEMPLATE" ] && [ -f .env.example ] && ENV_TEMPLATE=".env.example"

  if [ -n "$ENV_TEMPLATE" ] && [ ! -f .env ]; then
    cp "$ENV_TEMPLATE" .env
  fi

  if [ ! -f .env ]; then
    echo "Creating minimal .env..."
    cat > .env << 'PHPENV'
APP_NAME=Socioboard
APP_ENV=local
APP_DEBUG=true
APP_LOG=daily
BROADCAST_DRIVER=log
CACHE_DRIVER=file
SESSION_DRIVER=file
QUEUE_DRIVER=sync
PHPENV
  fi

  # Set key configuration values
  python3 << PYEOF
import re, sys

env_file = "$PHP_DIR/.env"
try:
    with open(env_file, 'r') as f:
        content = f.read()

    updates = {
        # CRITICAL: APP_URL must have trailing slash - PHP controller concatenates:
        # env('APP_URL') . "assets/imgs/user-avatar.png" → needs trailing slash
        'APP_URL': 'http://localhost/',
        # CRITICAL: API_URL must NOT include /v1/ - PHP code appends VERSION+/ itself
        # PHP builds: env('API_URL') . env('VERSION') . '/' = "http://127.0.0.1:3000/" + "v1" + "/" = "http://127.0.0.1:3000/v1/"
        # If API_URL already has /v1/, the result is double: "http://127.0.0.1:3000/v1/v1/" -> 404
        'API_URL': 'http://127.0.0.1:3000/',
        'API_URL_PUBLISH': 'http://127.0.0.1:3001/',
        'API_URL_FEEDs': 'http://127.0.0.1:3002/',
        # CRITICAL: PHP helper uses env('API_URL_FEEDS') uppercase; Laravel env() is case-sensitive
        # .env has API_URL_FEEDs (lowercase) but PHP reads API_URL_FEEDS (uppercase)
        # Adding both to ensure the uppercase one is present
        'API_URL_FEEDS': 'http://127.0.0.1:3002/',
        'API_URL_NOTIFY': 'http://127.0.0.1:3003/',
        'VERSION': 'v1',
        'DB_CONNECTION': 'mysql',
        'DB_HOST': '127.0.0.1',
        'DB_PORT': '3306',
        'DB_DATABASE': '$DB_NAME',
        'DB_USERNAME': '$DB_USER',
        'DB_PASSWORD': '$DB_PASS',
    }

    for key, value in updates.items():
        pattern = rf'^({re.escape(key)}\s*=).*$'
        replacement = rf'\g<1>{value}'
        if re.search(pattern, content, re.MULTILINE):
            content = re.sub(pattern, replacement, content, flags=re.MULTILINE)
        else:
            content += f'\n{key}={value}'

    with open(env_file, 'w') as f:
        f.write(content)
    print("PHP .env updated successfully")
except Exception as e:
    print(f"WARNING: Could not update PHP .env: {e}", file=sys.stderr)
PYEOF

  # CRITICAL: Patch PackageManifest.php for Composer v2 compatibility
  # MUST be done BEFORE php artisan commands (including key:generate)
  # Laravel 5.x PackageManifest::build() reads installed.json and iterates it
  # as a flat array, but Composer v2 wraps packages in {"packages":[...]}
  # This causes "Class view does not exist" ReflectionException (HTTP 500)
  PKG_MANIFEST="$PHP_DIR/vendor/laravel/framework/src/Illuminate/Foundation/PackageManifest.php"
  if [ -f "$PKG_MANIFEST" ]; then
    # Check if already patched
    if ! grep -q 'isset.*packages.*packages' "$PKG_MANIFEST" 2>/dev/null; then
      # Patch: after json_decode, unwrap Composer v2 packages key
      # Line pattern: $packages = json_decode(...);
      python3 << 'PATCHEOF'
import re

manifest_file = "/opt/socioboard/socioboard-web-php/vendor/laravel/framework/src/Illuminate/Foundation/PackageManifest.php"
try:
    with open(manifest_file, 'r') as f:
        content = f.read()

    # Find the line that does json_decode on installed.json and add Composer v2 handling after it
    # The pattern: $packages = json_decode($this->files->get($path), true);
    old_pattern = r'(\$packages\s*=\s*json_decode\s*\([^;]+\);)'
    new_code = r'''\1
        // Composer v2 wraps packages in {"packages":[...]} - unwrap for Laravel 5.x
        if (is_array($packages) && isset($packages['packages'])) {
            $packages = $packages['packages'];
        }'''

    if re.search(old_pattern, content):
        patched = re.sub(old_pattern, new_code, content, count=1)
        with open(manifest_file, 'w') as f:
            f.write(patched)
        print("PackageManifest.php patched for Composer v2 compatibility")
    else:
        print("WARNING: Could not find json_decode line in PackageManifest.php - may need manual patch")
except Exception as e:
    print(f"WARNING: Could not patch PackageManifest.php: {e}")
PATCHEOF
    else
      echo "PackageManifest.php already patched"
    fi
  else
    echo "WARNING: PackageManifest.php not found at $PKG_MANIFEST"
  fi

  # Generate app key AFTER PackageManifest patch so artisan can run
  COMPOSER_ALLOW_SUPERUSER=1 php7.4 artisan key:generate --force 2>/dev/null || true

  # Python fallback: generate APP_KEY if artisan failed
  if ! grep -q '^APP_KEY=base64:' "$PHP_DIR/.env" 2>/dev/null; then
    echo "Generating APP_KEY via Python (artisan failed)..."
    python3 << PYEOF
import base64, os, re
key = 'base64:' + base64.b64encode(os.urandom(32)).decode()
env_file = "$PHP_DIR/.env"
try:
    with open(env_file, 'r') as f:
        content = f.read()
    if re.search(r'^APP_KEY\s*=', content, re.MULTILINE):
        content = re.sub(r'^(APP_KEY\s*=).*$', f'APP_KEY={key}', content, flags=re.MULTILINE)
    else:
        content += f'\nAPP_KEY={key}'
    with open(env_file, 'w') as f:
        f.write(content)
    print(f"APP_KEY generated: {key[:20]}...")
except Exception as e:
    print(f"WARNING: Could not generate APP_KEY: {e}")
PYEOF
  fi

  # Clear Laravel cache after patching and key generation
  COMPOSER_ALLOW_SUPERUSER=1 php7.4 artisan config:clear 2>/dev/null || true
  COMPOSER_ALLOW_SUPERUSER=1 php7.4 artisan cache:clear 2>/dev/null || true

  # Set permissions
  chown -R www-data:www-data "$PHP_DIR"
  chmod -R 755 "$PHP_DIR"
  chmod -R 777 "$PHP_DIR/storage" 2>/dev/null || true
  chmod -R 777 "$PHP_DIR/bootstrap/cache" 2>/dev/null || true

  echo "PHP Laravel frontend configured"
fi

# ============================================================
# Configure Apache virtual host
# ============================================================
echo "Configuring Apache virtual host..."
cat > /etc/apache2/sites-available/socioboard.conf << 'APACHE_CONF'
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot /opt/socioboard/socioboard-web-php/public/

    <Directory /opt/socioboard/socioboard-web-php/public/>
        DirectoryIndex index.php
        Options +FollowSymLinks -MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/socioboard_error.log
    CustomLog ${APACHE_LOG_DIR}/socioboard_access.log combined
</VirtualHost>
APACHE_CONF

a2dissite 000-default.conf 2>/dev/null || true
a2ensite socioboard.conf
a2enmod rewrite php7.4
systemctl restart apache2
sleep 2
echo "Apache configured"

# ============================================================
# Create systemd services for Node.js microservices
# ============================================================
echo "Creating systemd services for Node.js microservices..."

create_node_service() {
  local SVC_NAME="$1"
  local SVC_DIR="$2"
  local SVC_PORT="$3"
  local MAIN_FILE="${4:-app.js}"

  # Find the main JS file
  ENTRY=""
  for f in "$MAIN_FILE" "index.js" "server.js" "app.js"; do
    if [ -f "$SVC_DIR/$f" ]; then
      ENTRY="$f"
      break
    fi
  done
  [ -z "$ENTRY" ] && ENTRY="app.js"

  cat > "/etc/systemd/system/${SVC_NAME}.service" << SVCEOF
[Unit]
Description=Socioboard ${SVC_NAME} Microservice (port ${SVC_PORT})
After=mariadb.service mongod.service

[Service]
Type=simple
User=ga
WorkingDirectory=${SVC_DIR}
Environment=NODE_ENV=development
Environment=PORT=${SVC_PORT}
ExecStart=/usr/bin/node ${ENTRY}
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF
}

for SVC_PORT_PAIR in "socioboard-user:user:3000" "socioboard-publish:publish:3001" "socioboard-feeds:feeds:3002" "socioboard-notification:notification:3003"; do
  SVC_SYSTEMD=$(echo "$SVC_PORT_PAIR" | cut -d: -f1)
  SVC_SUBDIR=$(echo "$SVC_PORT_PAIR" | cut -d: -f2)
  SVC_PORT=$(echo "$SVC_PORT_PAIR" | cut -d: -f3)
  SVC_DIR="$SOCRDIR/socioboard-api/$SVC_SUBDIR"

  if [ -d "$SVC_DIR" ]; then
    create_node_service "$SVC_SYSTEMD" "$SVC_DIR" "$SVC_PORT"
    echo "  Created service: $SVC_SYSTEMD"
  else
    echo "  WARNING: $SVC_DIR not found, skipping $SVC_SYSTEMD"
  fi
done

systemctl daemon-reload

# Start microservices
echo "Starting Socioboard microservices..."
for SVC in socioboard-user socioboard-publish socioboard-feeds socioboard-notification; do
  if [ -f "/etc/systemd/system/${SVC}.service" ]; then
    systemctl enable "$SVC" 2>/dev/null || true
    systemctl start "$SVC" 2>/dev/null || true
    sleep 1
    echo "  Started: $SVC"
  fi
done

# Give services time to initialize
sleep 10

echo "Microservice status:"
for SVC in socioboard-user socioboard-publish socioboard-feeds socioboard-notification; do
  STATUS=$(systemctl is-active "$SVC" 2>/dev/null || echo "unknown")
  echo "  $SVC: $STATUS"
done

# ============================================================
# Wait for user microservice to be ready
# ============================================================
echo "Waiting for user microservice (port 3000)..."
for i in $(seq 1 60); do
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null | grep -qE "^(200|302|404|400)"; then
    echo "User microservice ready after ${i}s"
    break
  fi
  sleep 2
  echo "  Waiting for user service... ${i}"
done

# ============================================================
# Wait for Apache/PHP frontend to be ready
# ============================================================
echo "Waiting for Apache/PHP frontend..."
for i in $(seq 1 60); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
  if [ "$CODE" = "200" ] || [ "$CODE" = "302" ] || [ "$CODE" = "301" ]; then
    echo "Apache frontend ready after ${i}s (HTTP $CODE)"
    break
  fi
  sleep 3
  echo "  Waiting for frontend... ${i} (HTTP $CODE)"
done

# ============================================================
# Create admin user account via Node.js API
# CRITICAL: Use PUT /v1/register (not POST /v1/socioboard/user/signup)
# ============================================================
echo "Creating Socioboard admin user account..."
USER_API_URL="http://127.0.0.1:3000/v1"

# Wait for user service to fully start (it needs MongoDB to connect)
sleep 5

# Try creating user via REST API
# CRITICAL: PUT /v1/register requires nested user object with specific fields
# - userName must be alphanumeric (no dots/dashes)
# - profilePicture must be a valid public URL (isUrl validator rejects localhost)
# - phoneCode must match /^[+0-9]+$/
# - phoneNo must be numeric
echo "Attempting to create admin user via API..."
python3 << PYEOF
import json, subprocess, sys

body = {
    "user": {
        "userName": "admin",
        "email": "$ADMIN_EMAIL",
        "password": "$ADMIN_PASS",
        "firstName": "Admin",
        "lastName": "User",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/admin",
        "dateOfBirth": "1990-01-01",
        "phoneCode": "+1",
        "phoneNo": "5550000001",
        "country": "US",
        "timeZone": "America/New_York",
        "aboutMe": "Admin user"
    }
}

import tempfile, os
with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(body, f)
    tmpfile = f.name

result = subprocess.run(
    ['curl', '-s', '-X', 'PUT', '-H', 'Content-Type: application/json', '-d', f'@{tmpfile}', 'http://127.0.0.1:3000/v1/register'],
    capture_output=True, text=True, timeout=30
)
os.unlink(tmpfile)
print(f"Admin register: {result.stdout[:200]}")
PYEOF

# Activate user account directly in the database (bypass email verification)
echo "Activating admin user account in database..."
mysql -u root << ACTIVATESQL 2>/dev/null || true
USE ${DB_NAME};
UPDATE user_activations SET activation_status = 1 WHERE activation_status = 0;
ACTIVATESQL

echo "Admin account activation complete"

# ============================================================
# Create a second user (for add_team_member task)
# ============================================================
echo "Creating second user for team tasks..."
sleep 2
python3 << PYEOF
import json, subprocess, os, tempfile

body = {
    "user": {
        "userName": "johnsmith",
        "email": "john.smith@socioboard.local",
        "password": "User2024!",
        "firstName": "John",
        "lastName": "Smith",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/johnsmith",
        "dateOfBirth": "1985-06-15",
        "phoneCode": "+1",
        "phoneNo": "5550000002",
        "country": "US",
        "timeZone": "America/New_York",
        "aboutMe": "Team member"
    }
}

with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(body, f)
    tmpfile = f.name

result = subprocess.run(
    ['curl', '-s', '-X', 'PUT', '-H', 'Content-Type: application/json', '-d', f'@{tmpfile}', 'http://127.0.0.1:3000/v1/register'],
    capture_output=True, text=True, timeout=30
)
os.unlink(tmpfile)
print(f"Second user register: {result.stdout[:200]}")
PYEOF

# Activate second user too
mysql -u root << ACTIVATESQL2 2>/dev/null || true
USE ${DB_NAME};
UPDATE user_activations SET activation_status = 1;
ACTIVATESQL2

# ============================================================
# CRITICAL: Create a default team for admin user
# The register endpoint does NOT create a team automatically.
# Without a team, getTeams() returns error and browser login fails
# with "Something went wrong" (getTeamNewSession() fails).
# POST /v1/team/create requires x-access-token (JWT from /v1/login)
# Body: {"TeamInfo": {"name": "...", "description": "..."}}
# ============================================================
echo "Creating default team for admin user (required for browser login)..."
sleep 3  # Give user service time to settle after registrations

python3 << PYEOF
import json, subprocess, os, tempfile, sys

# Step 1: Login to get JWT token
login_body = {"user": "$ADMIN_EMAIL", "password": "$ADMIN_PASS"}
with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(login_body, f)
    login_tmp = f.name

login_result = subprocess.run(
    ['curl', '-s', '-X', 'POST', '-H', 'Content-Type: application/json',
     '-d', f'@{login_tmp}', 'http://127.0.0.1:3000/v1/login'],
    capture_output=True, text=True, timeout=30
)
os.unlink(login_tmp)
print(f"Login response: {login_result.stdout[:300]}")

try:
    login_data = json.loads(login_result.stdout)
    access_token = (login_data.get('accessToken') or
                    login_data.get('token') or
                    login_data.get('data', {}).get('accessToken') or '')
except Exception as e:
    access_token = ''
    print(f"Could not parse login response: {e}", file=sys.stderr)

if not access_token:
    print("WARNING: Could not get access token for team creation", file=sys.stderr)
    sys.exit(0)

print(f"Got access token: {access_token[:30]}...")

# Step 2: Create default team
team_body = {
    "TeamInfo": {
        "name": "My Social Team",
        "description": "Default team for social media management"
    }
}
with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(team_body, f)
    team_tmp = f.name

team_result = subprocess.run(
    ['curl', '-s', '-X', 'POST',
     '-H', 'Content-Type: application/json',
     '-H', f'x-access-token: {access_token}',
     '-d', f'@{team_tmp}',
     'http://127.0.0.1:3000/v1/team/create'],
    capture_output=True, text=True, timeout=30
)
os.unlink(team_tmp)
print(f"Team creation response: {team_result.stdout[:300]}")
PYEOF

echo "Default team creation complete"

# ============================================================
# CRITICAL PATCH: Upgrade users to Premium plan
# RSS features (rss_feeds) gated by plan: Basic=0 (no RSS), Premium=1 (RSS enabled)
# Without this, the RSS/Content Feeds menu shows planCheck(0) instead of link
# ============================================================
echo "Upgrading users to Premium plan (enables RSS features)..."
mysql -u root << UPGRADESQL 2>/dev/null || true
USE ${DB_NAME};
UPDATE user_activations SET user_plan = 2;
UPGRADESQL
echo "User plan upgrade complete"

# ============================================================
# CRITICAL PATCHES: Fix PHP UserController and Blade templates
# These patches enable:
# 1. Timezone dropdown in settings (change_timezone task)
# 2. Phone field validation (allows empty phone in profile update)
# 3. RSS Feed Name field in rssfeeds page (add_rss_feed task)
# 4. Team view page for newly-created teams (add_team_member task)
# ============================================================
echo "Applying PHP/Blade patches..."
python3 << 'PHPATCH'
import os

# ---- Patch 1: UserController.php ----
# a) Make phone validation nullable (prevents "phone is invalid" on empty phone)
# b) Pass userDetails to account() view (needed for pre-populating settings form)
# c) Add timeZone to profile update call (change_timezone task)
ctrl_path = "/opt/socioboard/socioboard-web-php/app/Modules/User/Controllers/UserController.php"
with open(ctrl_path, 'r') as f:
    ctrl = f.read()

# Patch 1a: nullable phone validation
old_phone = '"phone" => \'regex:/[0-9]{10}/\''
new_phone = '"phone" => \'nullable|regex:/[0-9]{10}/\''
if old_phone in ctrl:
    ctrl = ctrl.replace(old_phone, new_phone)
    print("Patch 1a: phone validation nullable - applied")
elif "nullable|regex:/[0-9]{10}/" in ctrl:
    print("Patch 1a: phone validation nullable - already applied")
else:
    print("WARNING: Patch 1a: phone validation - pattern not found")

# Patch 1b: pass userDetails to account() view
old_account = '''    public function account(Request $request){
        if($request->isMethod('get')){
            return view('User::dashboard.settings');'''
new_account = '''    public function account(Request $request){
        if($request->isMethod('get')){
            $userDetails = Session::get('user') ? Session::get('user')['userDetails'] : null;
            return view('User::dashboard.settings', ['userDetails' => $userDetails]);'''
if old_account in ctrl:
    ctrl = ctrl.replace(old_account, new_account)
    print("Patch 1b: account() passes userDetails - applied")
elif "userDetails = Session::get('user') ? Session::get('user')['userDetails'] : null" in ctrl:
    print("Patch 1b: account() passes userDetails - already applied")
else:
    print("WARNING: Patch 1b: account() - pattern not found")

# Patch 1c: add timeZone to profile update call
old_tz = '                    "aboutMe"=>$request->bio\n                );'
new_tz = '                    "aboutMe"=>$request->bio,\n                    "timeZone"=>$request->timeZone\n                );'
if old_tz in ctrl:
    ctrl = ctrl.replace(old_tz, new_tz)
    print("Patch 1c: timeZone in profile update - applied")
elif '"timeZone"=>$request->timeZone' in ctrl:
    print("Patch 1c: timeZone in profile update - already applied")
else:
    print("WARNING: Patch 1c: timeZone - pattern not found")

with open(ctrl_path, 'w') as f:
    f.write(ctrl)
print("UserController.php patched")

# ---- Patch 2: settings.blade.php - Add timezone dropdown ----
settings_path = "/opt/socioboard/socioboard-web-php/app/Modules/User/Views/dashboard/settings.blade.php"
with open(settings_path, 'r') as f:
    settings = f.read()

# Check if already has timezone
if 'timeZone' in settings and 'time_zone_select' in settings:
    print("Patch 2: settings.blade.php timezone - already applied")
else:
    # Add timezone dropdown before the bio/aboutMe field
    # Find the bio row and insert timezone before it
    bio_marker = '<div class="form-group row">\n                                <label for="bio"'
    tz_block = '''<div class="form-group row">
                                <label for="timezone" class="col-sm-2 col-form-label"><b class="float-right">Time Zone</b></label>
                                <div class="col-sm-8">
                                    <select name="timeZone" class="form-control border border-light" id="time_zone_select">
                                        @php $currentTz = (isset($userDetails) && $userDetails && isset($userDetails->time_zone)) ? $userDetails->time_zone : \'\'; @endphp
                                        <option value="">-- Select Timezone --</option>
                                        <option value="America/Los_Angeles" {{ $currentTz == \'America/Los_Angeles\' ? \'selected\' : \'\' }}>America/Los_Angeles (UTC-08:00)</option>
                                        <option value="America/Denver" {{ $currentTz == \'America/Denver\' ? \'selected\' : \'\' }}>America/Denver (UTC-07:00)</option>
                                        <option value="America/Chicago" {{ $currentTz == \'America/Chicago\' ? \'selected\' : \'\' }}>America/Chicago (UTC-06:00)</option>
                                        <option value="America/New_York" {{ $currentTz == \'America/New_York\' ? \'selected\' : \'\' }}>America/New_York (UTC-05:00)</option>
                                        <option value="Europe/London" {{ $currentTz == \'Europe/London\' ? \'selected\' : \'\' }}>Europe/London (UTC+00:00)</option>
                                        <option value="Europe/Paris" {{ $currentTz == \'Europe/Paris\' ? \'selected\' : \'\' }}>Europe/Paris (UTC+01:00)</option>
                                        <option value="Asia/Kolkata" {{ $currentTz == \'Asia/Kolkata\' ? \'selected\' : \'\' }}>Asia/Kolkata (UTC+05:30)</option>
                                        <option value="Asia/Tokyo" {{ $currentTz == \'Asia/Tokyo\' ? \'selected\' : \'\' }}>Asia/Tokyo (UTC+09:00)</option>
                                        <option value="Australia/Sydney" {{ $currentTz == \'Australia/Sydney\' ? \'selected\' : \'\' }}>Australia/Sydney (UTC+10:00)</option>
                                        <option value="Pacific/Auckland" {{ $currentTz == \'Pacific/Auckland\' ? \'selected\' : \'\' }}>Pacific/Auckland (UTC+12:00)</option>
                                    </select>
                                </div>
                            </div>
                            ''' + bio_marker
    if bio_marker in settings:
        settings = settings.replace(bio_marker, tz_block)
        with open(settings_path, 'w') as f:
            f.write(settings)
        print("Patch 2: settings.blade.php timezone dropdown - applied")
    else:
        print("WARNING: Patch 2: settings.blade.php - bio marker not found")

# ---- Patch 3: rssfeeds.blade.php - Add Feed Name field ----
rss_path = "/opt/socioboard/socioboard-web-php/app/Modules/Discovery/Views/rssfeeds.blade.php"
with open(rss_path, 'r') as f:
    rss = f.read()

if 'feedName' in rss or 'Feed Name' in rss:
    print("Patch 3: rssfeeds.blade.php Feed Name - already applied")
else:
    old_form = '<form class="mb-2" id="rssForm">\n                            <div class="form-group row mb-2">\n                                <label class="col-sm-2 col-form-label" for="rss_search"><b>Feed URL</b></label>'
    new_form = '''<form class="mb-2" id="rssForm">
                            <div class="form-group row mb-2">
                                <label class="col-sm-2 col-form-label" for="rss_name"><b>Feed Name</b></label>
                                <div class="col-sm-10">
                                    <input type="text" class="form-control border-0 rounded-pill" id="rss_name"
                                           name="feedName" placeholder="Enter feed name (e.g. BBC Technology News)">
                                </div>
                            </div>
                            <div class="form-group row mb-2">
                                <label class="col-sm-2 col-form-label" for="rss_search"><b>Feed URL</b></label>'''
    if old_form in rss:
        rss = rss.replace(old_form, new_form)
        with open(rss_path, 'w') as f:
            f.write(rss)
        print("Patch 3: rssfeeds.blade.php Feed Name - applied")
    else:
        print("WARNING: Patch 3: rssfeeds.blade.php - form marker not found")
        idx = rss.find('rssForm')
        print("Context:", repr(rss[idx:idx+300]))

# ---- Patch 4: viewTeam.blade.php - Safe access to adminDetails ----
vt_path = "/opt/socioboard/socioboard-web-php/app/Modules/Team/Views/viewTeam.blade.php"
with open(vt_path, 'r') as f:
    vt = f.read()

old_admin_dl = """                    <dl>
                        <dt>Name :</dt>
                        <dd>{{$adminDetails['first_name']}}</dd>
                        <dt>Email Id :</dt>
                        <dd>{{$adminDetails['email']}}</dd>
                    </dl>"""
new_admin_dl = """                    <dl>
                        <dt>Name :</dt>
                        <dd>{{isset($adminDetails['first_name']) ? $adminDetails['first_name'] : 'Admin'}}</dd>
                        <dt>Email Id :</dt>
                        <dd>{{isset($adminDetails['email']) ? $adminDetails['email'] : ''}}</dd>
                    </dl>"""
if old_admin_dl in vt:
    vt = vt.replace(old_admin_dl, new_admin_dl)
    with open(vt_path, 'w') as f:
        f.write(vt)
    print("Patch 4: viewTeam.blade.php safe adminDetails - applied")
elif "isset($adminDetails['first_name'])" in vt:
    print("Patch 4: viewTeam.blade.php safe adminDetails - already applied")
else:
    print("WARNING: Patch 4: viewTeam.blade.php - pattern not found")

print("All PHP/Blade patches complete")
PHPATCH

# ---- Patch 5: TeamController.php - adminDetails fallback for new teams ----
echo "Applying TeamController.php adminDetails fallback patch..."
python3 << 'TCPATCH'
path = '/opt/socioboard/socioboard-web-php/app/Modules/Team/Controllers/TeamController.php'
with open(path, 'r') as f:
    content = f.read()

old = '''                        } else
                            break;
                    }
                }
                //Get all social acc'''

new = '''                        } else
                            break;
                    }
                }
                // Fallback: if adminDetails not set (newly created team not in session),
                // scan all session memberProfileDetails to find admin profile
                if (empty($adminDetails)) {
                    foreach ($value['memberProfileDetails'] as $profileGroup) {
                        foreach ($profileGroup as $profile) {
                            if ($profile->user_id == $teamDetails['team_admin_id'] && isset($profile->first_name)) {
                                $adminDetails = array(
                                    "id" => $profile->user_id,
                                    "email" => $profile->email,
                                    "first_name" => $profile->first_name
                                );
                                break 2;
                            }
                        }
                    }
                }
                // Use API response teamMembers for newly created teams not in session
                if (empty($teamMemberActivation) && isset($response->teamMembers)) {
                    $teamMemberActivation = (array)$response->teamMembers;
                    foreach ($teamMemberActivation as &$member) {
                        $member = (object)$member;
                        if (!isset($member->first_name)) {
                            foreach ($value['memberProfileDetails'] as $profileGroup) {
                                foreach ($profileGroup as $profile) {
                                    if ($profile->user_id == $member->user_id && isset($profile->first_name)) {
                                        $member->first_name = $profile->first_name;
                                        $member->profile = $profile->profile_picture;
                                        $member->email = $profile->email;
                                        break 2;
                                    }
                                }
                            }
                            if (!isset($member->first_name)) {
                                $member->first_name = 'Member';
                                $member->profile = '';
                                $member->email = '';
                            }
                        }
                    }
                    unset($member);
                }
                //Get all social acc'''

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print("TeamController.php adminDetails fallback - applied")
elif 'Fallback: if adminDetails not set' in content:
    print("TeamController.php adminDetails fallback - already applied")
else:
    print("WARNING: TeamController.php - pattern not found")
TCPATCH

# ---- Patch 6: authorizedlibs.js - fallback values + time_zone ----
echo "Applying Node.js authorizedlibs.js patches..."
python3 << 'AUTHPATCH'
path = "/opt/socioboard/socioboard-api/user/core/authorized/utils/authorizedlibs.js"
with open(path, 'r') as f:
    content = f.read()

# Patch 6a: Add fallback values to updateUserProfiles update() call
old_update = """                            return user.update({
                                first_name: profileDetails.firstName,
                                last_name: profileDetails.lastName,
                                date_of_birth: profileDetails.DateOfBirth,
                                profile_picture: profileDetails.profilePicture,
                                phone_code: profileDetails.phoneCode,
                                phone_no: profileDetails.phoneNumber,
                                about_me: profileDetails.aboutMe,
                            });"""
new_update = """                            return user.update({
                                first_name: profileDetails.firstName || user.first_name,
                                last_name: profileDetails.lastName || user.last_name,
                                date_of_birth: profileDetails.DateOfBirth || user.date_of_birth,
                                profile_picture: profileDetails.profilePicture || user.profile_picture,
                                phone_code: profileDetails.phoneCode || user.phone_code,
                                phone_no: profileDetails.phoneNumber || user.phone_no,
                                about_me: profileDetails.aboutMe || user.about_me,
                                time_zone: profileDetails.timeZone || user.time_zone,
                            });"""

if old_update in content:
    content = content.replace(old_update, new_update)
    print("Patch 6a: authorizedlibs.js update fallbacks + time_zone - applied")
elif 'time_zone: profileDetails.timeZone' in content:
    print("Patch 6a: authorizedlibs.js update - already applied")
else:
    print("WARNING: Patch 6a: authorizedlibs.js - update pattern not found")
    idx = content.find('first_name: profileDetails.firstName')
    print("Context:", repr(content[idx:idx+300]))

# Patch 6b: Add time_zone to findOne attributes
old_attrs = "attributes: ['user_id', 'email', 'first_name', 'last_name', 'date_of_birth', 'profile_picture', 'phone_code', 'phone_no', 'about_me'],"
new_attrs = "attributes: ['user_id', 'email', 'first_name', 'last_name', 'date_of_birth', 'profile_picture', 'phone_code', 'phone_no', 'about_me', 'time_zone'],"
if old_attrs in content:
    content = content.replace(old_attrs, new_attrs)
    print("Patch 6b: authorizedlibs.js findOne time_zone attr - applied")
elif "'about_me', 'time_zone']" in content:
    print("Patch 6b: authorizedlibs.js findOne time_zone attr - already applied")
else:
    print("WARNING: Patch 6b: authorizedlibs.js - attributes pattern not found")

with open(path, 'w') as f:
    f.write(content)
print("authorizedlibs.js patched")
AUTHPATCH

# ---- Patch 7: userlibs.js - Add time_zone to getUserDetails attributes ----
echo "Applying userlibs.js time_zone patch..."
python3 << 'ULPATCH'
path = "/opt/socioboard/socioboard-api/user/core/libraries/userlibs.js"
with open(path, 'r') as f:
    content = f.read()

old_attrs = "attributes: ['user_id', 'email', 'phone_no', 'first_name', 'last_name', 'profile_picture', 'is_account_locked', 'is_admin_user'],"
new_attrs = "attributes: ['user_id', 'email', 'phone_no', 'first_name', 'last_name', 'profile_picture', 'is_account_locked', 'is_admin_user', 'time_zone'],"
if old_attrs in content:
    content = content.replace(old_attrs, new_attrs)
    with open(path, 'w') as f:
        f.write(content)
    print("Patch 7: userlibs.js time_zone in getUserDetails - applied")
elif "'is_admin_user', 'time_zone']" in content:
    print("Patch 7: userlibs.js time_zone - already applied")
else:
    print("WARNING: Patch 7: userlibs.js - attributes pattern not found")
    idx = content.find('is_admin_user')
    print("Context:", repr(content[max(0,idx-50):idx+150]))
ULPATCH

# Clear Laravel view cache after blade patches
echo "Clearing Laravel view cache..."
cd "$PHP_DIR" && COMPOSER_ALLOW_SUPERUSER=1 php7.4 artisan view:clear 2>/dev/null || true
cd - > /dev/null

# Restart Node.js user service to pick up authorizedlibs.js and userlibs.js changes
echo "Restarting user microservice to pick up Node.js changes..."
systemctl restart socioboard-user 2>/dev/null || true
sleep 5
echo "  socioboard-user: $(systemctl is-active socioboard-user 2>/dev/null || echo unknown)"

echo "All patches applied"

# ============================================================
# Configure snap Firefox profile
# CRITICAL: Must chown snap dir to ga BEFORE profile setup
# ============================================================
echo "Setting up Firefox profile..."
SNAP_FF_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
STD_FF_BASE="/home/ga/.mozilla/firefox"

setup_firefox_profile() {
  local PROFILE_DIR="$1"
  local PROFILE_BASE=$(dirname "$PROFILE_DIR")

  mkdir -p "$PROFILE_DIR"

  cat > "$PROFILE_BASE/profiles.ini" << 'PROFILES_INI'
[Profile0]
Name=default
IsRelative=1
Path=socioboard.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
PROFILES_INI

  cat > "$PROFILE_DIR/user.js" << USERJS
// Disable first-run and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to Socioboard login
user_pref("browser.startup.homepage", "http://localhost/login");
user_pref("browser.startup.page", 1);

// Disable updates
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable extensions popups
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable sidebar
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
USERJS
}

# Set up for both snap and standard Firefox
mkdir -p "$SNAP_FF_BASE"
setup_firefox_profile "$SNAP_FF_BASE/socioboard.profile"

mkdir -p "$STD_FF_BASE"
setup_firefox_profile "$STD_FF_BASE/socioboard.profile"

# CRITICAL: chown all snap and mozilla dirs AFTER creation (root creates them)
chown -R ga:ga /home/ga/snap 2>/dev/null || true
chown -R ga:ga "$SNAP_FF_BASE" 2>/dev/null || true
chown -R ga:ga "$STD_FF_BASE" 2>/dev/null || true

echo "Firefox profile configured"

# ============================================================
# Launch Firefox to Socioboard login page
# ============================================================
echo "Launching Firefox to Socioboard..."

# Kill any existing Firefox instances
pkill -9 -f firefox 2>/dev/null || true
sleep 2
# Extra kill pass for snap firefox chains
pkill -9 -f firefox 2>/dev/null || true
sleep 1

# Remove lock files
rm -f "$SNAP_FF_BASE/socioboard.profile/.parentlock" 2>/dev/null || true
rm -f "$SNAP_FF_BASE/socioboard.profile/lock" 2>/dev/null || true
rm -f "$STD_FF_BASE/socioboard.profile/.parentlock" 2>/dev/null || true
rm -f "$STD_FF_BASE/socioboard.profile/lock" 2>/dev/null || true

# Launch Firefox via script file to avoid SSH session interference
# CRITICAL: su - ga -c causes SSH exit 255; use nohup + script file instead
cat > /tmp/ff_launch.sh << 'FFSCRIPT'
#!/bin/bash
export DISPLAY=:1
export XAUTHORITY=/run/user/1000/gdm/Xauthority
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

# Remove lock files (must run as ga to access snap dir)
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/socioboard.profile/.parentlock 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/socioboard.profile/lock 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/socioboard.profile/.parentlock 2>/dev/null || true

# Try snap Firefox first, then standard
if [ -f /snap/bin/firefox ] || which firefox 2>/dev/null | grep -q snap; then
  exec firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/socioboard.profile \
    http://localhost/login
else
  exec firefox \
    -profile /home/ga/.mozilla/firefox/socioboard.profile \
    http://localhost/login
fi
FFSCRIPT

chmod +x /tmp/ff_launch.sh
chown ga:ga /tmp/ff_launch.sh

sudo -H -u ga nohup bash /tmp/ff_launch.sh > /tmp/firefox_launch.log 2>&1 & disown || true

sleep 5

# Wait for Firefox window
for i in $(seq 1 30); do
  if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
    echo "Firefox window detected after ${i}s"
    break
  fi
  sleep 1
done

# Maximize Firefox
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo ""
echo "=== Socioboard setup complete ==="
echo "URL: http://localhost/login"
echo "Admin email: ${ADMIN_EMAIL}"
echo "Admin password: ${ADMIN_PASS}"
echo "Second user: john.smith@socioboard.local / User2024!"
