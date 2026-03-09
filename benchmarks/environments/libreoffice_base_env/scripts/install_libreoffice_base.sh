#!/bin/bash
# pre_start hook: Install LibreOffice Base and create the Chinook database ODB file.
# This script runs ONCE during environment build (before the desktop starts).
set -e

echo "=== Installing LibreOffice Base ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq

# Install LibreOffice Base with HSQLDB driver support and Java (required for Base)
apt-get install -y \
    libreoffice-base \
    libreoffice-base-drivers \
    libreoffice-java-common \
    default-jdk \
    libreoffice-calc \
    xdotool \
    wmctrl \
    scrot \
    imagemagick \
    python3 \
    wget \
    unzip

echo "LibreOffice Base version: $(libreoffice --version 2>/dev/null | head -1)"
echo "Java version: $(java -version 2>&1 | head -1)"

# --- Download Chinook SQLite (real music store dataset) ---
mkdir -p /opt/libreoffice_base_samples

CHINOOK_URLS=(
    "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
    "https://raw.githubusercontent.com/lerocha/chinook-database/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
)

DOWNLOAD_OK=false
for url in "${CHINOOK_URLS[@]}"; do
    echo "Downloading Chinook SQLite from: $url"
    if wget -q --timeout=120 --tries=3 "$url" -O /opt/libreoffice_base_samples/Chinook_Sqlite.sqlite; then
        SIZE=$(stat -c%s /opt/libreoffice_base_samples/Chinook_Sqlite.sqlite 2>/dev/null || echo 0)
        if [ "$SIZE" -gt 500000 ]; then
            echo "Chinook SQLite downloaded successfully: ${SIZE} bytes"
            DOWNLOAD_OK=true
            break
        else
            echo "Downloaded file too small (${SIZE} bytes), trying next URL..."
        fi
    else
        echo "Download failed from $url, trying next..."
    fi
done

if [ "$DOWNLOAD_OK" = "false" ]; then
    echo "ERROR: Failed to download Chinook SQLite database from all sources" >&2
    ls -la /opt/libreoffice_base_samples/ || true
    exit 1
fi

# --- Convert Chinook SQLite to LibreOffice Base ODB format ---
echo "Creating LibreOffice Base ODB from Chinook SQLite..."
python3 /workspace/scripts/create_chinook_odb.py \
    /opt/libreoffice_base_samples/Chinook_Sqlite.sqlite \
    /opt/libreoffice_base_samples/chinook.odb

if [ ! -f /opt/libreoffice_base_samples/chinook.odb ]; then
    echo "ERROR: Failed to create chinook.odb" >&2
    exit 1
fi

ODB_SIZE=$(stat -c%s /opt/libreoffice_base_samples/chinook.odb)
if [ "$ODB_SIZE" -lt 10000 ]; then
    echo "ERROR: chinook.odb is too small (${ODB_SIZE} bytes), creation likely failed" >&2
    exit 1
fi

echo "chinook.odb created successfully: ${ODB_SIZE} bytes"

# Set permissions so the ga user can read (and copy) the sample files
chmod 644 /opt/libreoffice_base_samples/chinook.odb
chmod 644 /opt/libreoffice_base_samples/Chinook_Sqlite.sqlite
chmod 755 /opt/libreoffice_base_samples

echo "=== LibreOffice Base installation complete ==="
