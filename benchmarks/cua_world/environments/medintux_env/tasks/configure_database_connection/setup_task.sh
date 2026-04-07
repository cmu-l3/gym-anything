#!/bin/bash
set -e
echo "=== Setting up Configure Database Connection task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
WINE_PREFIX="/home/ga/.wine"
# Standard location based on MedinTux installer
MANAGER_BIN="$WINE_PREFIX/drive_c/MedinTux-2.16/Programmes/Manager/bin"

# Ensure directory exists (in case install was non-standard or partial)
mkdir -p "$MANAGER_BIN"

INI_FILE="$MANAGER_BIN/Manager.ini"

echo "Resetting Manager.ini at $INI_FILE"

# Create a clean, known initial state for Manager.ini
# Simulating a standard local installation
cat > "$INI_FILE" << EOF
[General]
Path=..\\..\\DrTux\\bin\\DrTux.exe
Theme=Default

[Connexion]
driver=QMYSQL3
host=localhost
port=3306
base=DrTuxTest
user=root
password=
options="UNIX_SOCKET=/var/run/mysqld/mysqld.sock"

[Variables]
CodePostalDefaut=75000
VilleDefaut=PARIS
EOF

# Set ownership to user 'ga' so they can edit it without sudo
chown -R ga:ga "$WINE_PREFIX/drive_c/MedinTux-2.16" 2>/dev/null || true
chmod 644 "$INI_FILE"

# Remove any pre-existing backup files to ensure agent creates a new one
rm -f "$MANAGER_BIN/Manager.ini.bak"

# Save the hash of the initial state for verification (Ground Truth)
sha256sum "$INI_FILE" | awk '{print $1}' > /tmp/original_ini_hash.txt
echo "Original hash saved: $(cat /tmp/original_ini_hash.txt)"

# Take initial screenshot of the desktop
# (Even though it's a file task, context is important)
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="