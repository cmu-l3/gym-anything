#!/bin/bash
# Setup script for LOB Document Ingestion task
# Prepares real license files in /tmp/licenses and ensures clean DB state

set -e

echo "=== Setting up LOB Document Ingestion Task ==="

source /workspace/scripts/task_utils.sh

# --- 1. Prepare Data Directory and Real Files ---
DATA_DIR="/tmp/licenses"
mkdir -p "$DATA_DIR"
chmod 755 "$DATA_DIR"

echo "[1/4] Downloading license files..."

# Helper to download with retry
download_file() {
    local url="$1"
    local out="$2"
    if wget -q "$url" -O "$out"; then
        echo "  Downloaded $out"
    else
        echo "  Failed to download $out, using fallback content"
        echo "This is a placeholder for $out due to download failure." > "$out"
    fi
}

# Download real license texts from SPDX repo (reliable source)
download_file "https://raw.githubusercontent.com/spdx/license-list-data/master/text/Apache-2.0.txt" "$DATA_DIR/apache-2.0.txt"
download_file "https://raw.githubusercontent.com/spdx/license-list-data/master/text/MIT.txt" "$DATA_DIR/mit.txt"
download_file "https://raw.githubusercontent.com/spdx/license-list-data/master/text/GPL-3.0-only.txt" "$DATA_DIR/gpl-3.0.txt"
download_file "https://raw.githubusercontent.com/spdx/license-list-data/master/text/BSD-3-Clause.txt" "$DATA_DIR/bsd-3-clause.txt"

# Create the duplicate file (vendor_terms.txt is identical to apache-2.0.txt)
cp "$DATA_DIR/apache-2.0.txt" "$DATA_DIR/vendor_terms.txt"
echo "  Created duplicate file: vendor_terms.txt"

# Ensure all files are readable by Oracle (running as distinct user in container)
# In this environment, Oracle runs as user 'oracle' in the container.
# We make files world-readable to avoid permission issues during BFILENAME access.
chmod 644 "$DATA_DIR"/*.txt
chmod 755 "$DATA_DIR"

# --- 2. Clean Database State ---
echo "[2/4] Cleaning database state..."

# Drop table and directory if they exist
oracle_query "
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE hr.license_archive PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP DIRECTORY license_dir';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "system" > /dev/null 2>&1 || true

rm -f /home/ga/Desktop/duplicate_report.txt

# --- 3. Verify System/HR Connectivity ---
echo "[3/4] Verifying connectivity..."
HR_CHECK=$(oracle_query_raw "SELECT 'OK' FROM dual;" "hr" 2>/dev/null | tr -d ' ')
if [ "$HR_CHECK" != "OK" ]; then
    echo "ERROR: Cannot connect as HR user"
    exit 1
fi

SYSTEM_CHECK=$(oracle_query_raw "SELECT 'OK' FROM dual;" "system" 2>/dev/null | tr -d ' ')
if [ "$SYSTEM_CHECK" != "OK" ]; then
    echo "ERROR: Cannot connect as SYSTEM user"
    exit 1
fi

# --- 4. Record Initial State ---
echo "[4/4] Recording task start..."
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Files located in: $DATA_DIR"
ls -l "$DATA_DIR"