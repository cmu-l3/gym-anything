#!/bin/bash
# Aerobridge Installation Script (pre_start hook)
# Installs Aerobridge drone management system with SQLite database
# Source: https://github.com/openskies-sh/aerobridge (archived Dec 2023)

set -e

echo "=== Installing Aerobridge ==="

export DEBIAN_FRONTEND=noninteractive

# ============================================================
# 1. Update packages and install system dependencies
# ============================================================
apt-get update

apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    git \
    wget \
    curl \
    firefox \
    wmctrl \
    xdotool \
    scrot \
    x11-utils \
    xclip \
    build-essential \
    libssl-dev \
    libffi-dev \
    libgeos-dev \
    libpq-dev \
    pkg-config

echo "System dependencies installed."

# ============================================================
# 2. Clone Aerobridge from GitHub
# ============================================================
echo "Cloning Aerobridge repository..."
cd /opt
git clone https://github.com/openskies-sh/aerobridge.git
echo "Aerobridge cloned to /opt/aerobridge"

# ============================================================
# 3. Create Python virtual environment and install requirements
# ============================================================
echo "Creating Python virtual environment..."
python3 -m venv /opt/aerobridge_venv

echo "Installing Python dependencies (this may take several minutes)..."
/opt/aerobridge_venv/bin/pip install --upgrade pip setuptools wheel

# Install requirements; suppress warnings about older package versions
/opt/aerobridge_venv/bin/pip install -r /opt/aerobridge/requirements.txt \
    2>&1 | tee /var/log/aerobridge_pip_install.log || {
    echo "Some packages may have had issues. Trying with --ignore-requires-python..."
    /opt/aerobridge_venv/bin/pip install -r /opt/aerobridge/requirements.txt \
        --ignore-requires-python 2>&1 | tee -a /var/log/aerobridge_pip_install.log
}

# CRITICAL FIX: Upgrade django-simple-history to >=3.7.0 which uses importlib.metadata
# instead of pkg_resources (pkg_resources is not importable in Python 3.10+ venvs despite
# setuptools being installed - it changed to a different distribution mechanism)
echo "Upgrading django-simple-history to fix pkg_resources compatibility..."
/opt/aerobridge_venv/bin/pip install --upgrade 'django-simple-history>=3.7.0' \
    2>&1 | tee -a /var/log/aerobridge_pip_install.log

echo "Python dependencies installed."

# ============================================================
# 4. Generate a valid Fernet encryption key for CRYPTOGRAPHY_SALT
# ============================================================
echo "Generating Fernet encryption key..."
CRYPTO_KEY=$(/opt/aerobridge_venv/bin/python3 -c \
    "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
echo "Fernet key generated: ${CRYPTO_KEY:0:10}..."

# ============================================================
# 5. Create .env configuration file
# ============================================================
echo "Creating .env configuration..."
cat > /opt/aerobridge/.env << EOF
DJANGO_SECRET='aerobridge-gym-anything-development-secret-key-not-for-production'

PASSPORT_AUDIENCE=localhost
PASSPORT_DOMAIN=localhost
PASSPORT_TOKEN_URL=/oauth/token/
PASSPORT_URL=http://localhost:8000

CRYPTOGRAPHY_SALT='${CRYPTO_KEY}'

S3_ACCESS_KEY='dummy_s3_access_key'
S3_SECRET_KEY='dummy_s3_secret_key'
S3_REGION_NAME='ap-south-1'
S3_ENDPOINT_URL='http://localhost:9000'
S3_BUCKET_NAME='aerobridge-dev'

FLIGHT_PASSPORT_PERMISSION_CLIENT_ID='dummy_client_id'
FLIGHT_PASSPORT_PERMISSION_CLIENT_SECRET='dummy_client_secret'
FLIGHT_PASSPORT_TOKEN_URL='http://localhost:8000/oauth/token/'
EOF

chmod 600 /opt/aerobridge/.env
echo ".env configuration created."

# ============================================================
# 6. Patch settings.py to use SQLite and disable Celery tasks
#    (the default settings already use SQLite unless POSTGRES_HOST is set)
# ============================================================
echo "Verifying SQLite is configured as default database..."
# The Aerobridge settings.py uses SQLite by default when POSTGRES_HOST is not set.
# No patching needed as long as we don't set POSTGRES_HOST in .env.

# ============================================================
# 7. Run database migrations
# ============================================================
echo "Running database migrations..."
cd /opt/aerobridge

# Source .env into current shell (bash strips quotes automatically)
set -a
# shellcheck disable=SC1091
source /opt/aerobridge/.env
set +a

/opt/aerobridge_venv/bin/python manage.py migrate --run-syncdb 2>&1 | \
    tee /var/log/aerobridge_migrate.log

echo "Migrations complete."

# ============================================================
# 8. Load official Aerobridge sample/fixture data
#    (real data from the Aerobridge project: persons, aircraft, manufacturers,
#     operators, flight plans with real GPS coordinates around India)
# ============================================================
echo "Loading initial fixture data..."
/opt/aerobridge_venv/bin/python manage.py loaddata fixtures/initial_data.json \
    2>&1 | tee /var/log/aerobridge_loaddata.log

echo "Fixture data loaded."

# ============================================================
# 9. Create Django admin superuser (non-interactive)
# ============================================================
echo "Creating admin superuser..."
DJANGO_SUPERUSER_PASSWORD='adminpass123' \
    /opt/aerobridge_venv/bin/python manage.py createsuperuser \
    --noinput \
    --username admin \
    --email admin@aerobridge.io \
    2>&1 | tee /var/log/aerobridge_superuser.log \
    || echo "Superuser may already exist or another issue occurred (non-fatal)"

# Verify superuser was created
ADMIN_EXISTS=$(/opt/aerobridge_venv/bin/python -c "
import django, os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()
from django.contrib.auth.models import User
print(User.objects.filter(username='admin').exists())
" 2>/dev/null || echo "False")
echo "Admin user exists: ${ADMIN_EXISTS}"

# ============================================================
# 10. Collect static files
# ============================================================
echo "Collecting static files..."
/opt/aerobridge_venv/bin/python manage.py collectstatic --noinput \
    2>&1 | tee /var/log/aerobridge_collectstatic.log \
    || echo "Collectstatic had issues (non-fatal, DEBUG mode serves static files)"

# ============================================================
# 11. Create server startup script
# ============================================================
cat > /opt/aerobridge/start_server.sh << 'SCRIPT'
#!/bin/bash
# Start Aerobridge Django development server
set -a
source /opt/aerobridge/.env
set +a
cd /opt/aerobridge
exec /opt/aerobridge_venv/bin/python manage.py runserver 0.0.0.0:8000
SCRIPT
chmod +x /opt/aerobridge/start_server.sh

# ============================================================
# 12. Verify the installation
# ============================================================
echo "Verifying Aerobridge installation..."
AIRCRAFT_COUNT=$(/opt/aerobridge_venv/bin/python -c "
import django, os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
set_a = True
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            v = v.strip(\"'\").strip('\"')
            os.environ.setdefault(k, v)
django.setup()
try:
    from registry.models import Aircraft
    print(Aircraft.objects.count())
except Exception as e:
    print(f'0 (error: {e})')
" 2>/dev/null || echo "N/A")
echo "Aircraft in database: ${AIRCRAFT_COUNT}"

echo "=== Aerobridge installation complete ==="
echo "Database: /opt/aerobridge/aerobridge.sqlite3"
echo "Server will start on: http://localhost:8000"
echo "Admin credentials: admin / adminpass123"
