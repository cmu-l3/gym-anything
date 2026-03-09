#!/bin/bash
set -e

echo "=== Installing GNU Health HIS 5.0 ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install PostgreSQL 15
apt-get install -y postgresql postgresql-client

# Install Python and build tools
apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    libpq-dev \
    gcc \
    build-essential \
    nodejs \
    npm \
    wget \
    curl \
    jq \
    lsof \
    netcat-openbsd

# Install GUI tools
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    scrot \
    imagemagick

# Enable and start PostgreSQL
systemctl enable postgresql
systemctl start postgresql
sleep 5

# Create the gnuhealth OS user
if ! id -u gnuhealth &>/dev/null; then
    useradd -m -d /home/gnuhealth -s /bin/bash gnuhealth
fi

# Create the gnuhealth PostgreSQL role (with createdb permission, no password - uses peer auth)
su - postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='gnuhealth'\" | grep -q 1 || createuser --createdb --no-createrole --no-superuser gnuhealth"

# Create install directory
mkdir -p /opt/gnuhealth
chown gnuhealth:gnuhealth /opt/gnuhealth

# Install GNU Health 5.0 and trytond 7.0 into a virtual environment
# GNU Health 5.0 requires trytond>=7.0,<7.1
su - gnuhealth -c "
    set -e
    python3 -m venv /opt/gnuhealth/venv
    source /opt/gnuhealth/venv/bin/activate
    pip install --upgrade pip

    # Install trytond 7.0.x (GNU Health 5.0 requires this exact series)
    pip install 'trytond>=7.0,<7.1'

    # Install ALL GNU Health 5.0 modules (meta-package)
    # This installs the core + all 50+ specialty modules
    pip install 'gnuhealth==5.0.*'
    pip install 'gnuhealth-all-modules==5.0.*'

    # psycopg2 for PostgreSQL connectivity (binary build - no compilation needed)
    pip install psycopg2-binary
"

# Download and install the Sao web client (tryton-sao 7.0.x)
# Sao is the JavaScript web interface that trytond serves on port 8000
SAO_DIR=/opt/gnuhealth/sao
mkdir -p "$SAO_DIR"

# Download Sao from Tryton's official download server
SAO_DOWNLOADED=0
for SAO_URL in \
    "https://downloads.tryton.org/7.0/tryton-sao-last.tgz" \
    "https://ftp.tryton.org/pub/tryton/sao/7.0/tryton-sao-last.tgz"; do
    if curl -fsSL --max-time 180 "$SAO_URL" -o /tmp/sao.tgz 2>/dev/null; then
        tar -xzf /tmp/sao.tgz --strip-components=1 -C "$SAO_DIR"
        SAO_DOWNLOADED=1
        break
    fi
done

if [ "$SAO_DOWNLOADED" -eq 1 ]; then
    cd "$SAO_DIR"
    npm install --production --legacy-peer-deps 2>/dev/null || true
    echo "Sao web client installed"
else
    echo "WARNING: Could not download Sao web client from known URLs"
fi

chown -R gnuhealth:gnuhealth /opt/gnuhealth

# Create trytond configuration file
# Uses Unix socket (postgresql://gnuhealth@/) for peer auth - no password needed
cat > /opt/gnuhealth/trytond.conf << 'EOF'
[database]
uri = postgresql://gnuhealth@/

[web]
listen = 0.0.0.0:8000
root = /opt/gnuhealth/sao

[session]
timeout = 43200

[cache]
clean_timeout = 0

EOF
chown gnuhealth:gnuhealth /opt/gnuhealth/trytond.conf

# Download the official GNU Health 5.0 demo database
# This contains realistic clinical data: "GNU Solidario Hospital"
# Patients: Ana Isabel Betz (T1D, BRCA1), John Zenon, family history, lab results, prescriptions
echo "Downloading GNU Health 5.0 demo database..."
DEMO_URL="https://www.gnuhealth.org/downloads/postgres_dumps/gnuhealth-50-demo.sql.gz"

# Must use root/sudo for download since /tmp may be root-owned
if curl -fsSL --max-time 600 "$DEMO_URL" -o /tmp/gnuhealth-50-demo.sql.gz; then
    echo "Demo database downloaded: $(ls -lh /tmp/gnuhealth-50-demo.sql.gz | awk '{print $5}')"
    gunzip -f /tmp/gnuhealth-50-demo.sql.gz
    echo "Demo database decompressed"
    touch /tmp/gnuhealth-demo-ready
else
    echo "WARNING: Could not download demo database. Will initialize empty database instead."
    touch /tmp/gnuhealth-no-demo
fi

# Create systemd service for GNU Health
cat > /etc/systemd/system/gnuhealth.service << 'EOF'
[Unit]
Description=GNU Health Hospital Information System
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=gnuhealth
WorkingDirectory=/opt/gnuhealth
Environment=PATH=/opt/gnuhealth/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/gnuhealth/venv/bin/trytond -c /opt/gnuhealth/trytond.conf
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=gnuhealth

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gnuhealth

echo "=== GNU Health HIS installation complete ==="
