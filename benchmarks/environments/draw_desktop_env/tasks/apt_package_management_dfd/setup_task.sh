#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up apt_package_management_dfd task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any existing output files
rm -f /home/ga/Desktop/apt_dfd.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/apt_dfd.png 2>/dev/null || true

# Create the Reference Architecture Document
cat > /home/ga/Desktop/apt_architecture_ref.txt << 'REFEOF'
APT PACKAGE MANAGEMENT - SYSTEM ARCHITECTURE REFERENCE
======================================================
Compliance Audit: Supply Chain Security
Doc ID: APT-ARCH-V2

NOTATION GUIDE (Standard DFD)
-----------------------------
- Processes: Ellipse / Circle
- External Entities: Rectangle / Square
- Data Stores: Cylinder or Open-Ended Rectangle
- Data Flows: Directed Arrow with Label

EXTERNAL ENTITIES
-----------------
1. System Administrator
   - Triggers updates and installations
   - Receives status and errors
2. Package Repository (e.g., archive.ubuntu.com)
   - Host for .deb files and metadata
3. GPG Keyserver
   - Source of public keys for signature verification
4. Installed System (dpkg)
   - The actual filesystem and low-level package database

DATA STORES (Internal Storage)
------------------------------
D1: Sources List (/etc/apt/sources.list)
D2: Package Lists (/var/lib/apt/lists/)
D3: Package Cache (/var/cache/apt/archives/)
D4: dpkg Status DB (/var/lib/dpkg/status)

PROCESS SPECIFICATIONS (Level 1 Decomposition)
----------------------------------------------

P1: Parse Sources
   - Input: "apt update/install" (from Admin)
   - Input: Reads D1 (Sources List)
   - Output: List of repository URLs to P2

P2: Fetch Metadata
   - Input: Repo URLs from P1
   - Input/Output: HTTP GET Release/Packages.gz (to/from Repository)
   - Output: Writes metadata to D2 (Package Lists)

P3: Resolve Dependencies
   - Input: Reads D2 (Package Lists)
   - Input: Reads D4 (dpkg Status) to check installed versions
   - Output: List of required packages to P4

P4: Download Packages
   - Input: Package list from P3
   - Input/Output: HTTP GET .deb files (to/from Repository)
   - Output: Writes .deb files to D3 (Package Cache)

P5: Verify & Install
   - Input: Reads .deb files from D3
   - Input/Output: Request Keys / Receive Keys (to/from GPG Keyserver)
   - Output: Install commands to Installed System
   - Output: Updates D4 (dpkg Status)
   - Output: Success/Failure message to Administrator

REFEOF

chown ga:ga /home/ga/Desktop/apt_architecture_ref.txt
echo "Reference document created at /home/ga/Desktop/apt_architecture_ref.txt"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_task.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss startup dialog to start with blank canvas
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="