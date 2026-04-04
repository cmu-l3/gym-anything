#!/bin/bash
set -e
echo "=== Setting up MAC OUI Inventory task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify required PCAP files exist
REQUIRED_FILES=("http.cap" "dns.cap" "telnet-cooked.pcap" "smtp.pcap")
CAPTURES_DIR="/home/ga/Documents/captures"

for f in "${REQUIRED_FILES[@]}"; do
    FPATH="$CAPTURES_DIR/$f"
    if [ ! -s "$FPATH" ]; then
        echo "ERROR: Required capture file $FPATH is missing or empty!"
        exit 1
    fi
    echo "  Verified: $FPATH ($(stat -c%s "$FPATH") bytes)"
done

# Remove any previous report to ensure clean state
rm -f "$CAPTURES_DIR/mac_inventory_report.txt"

# Create a secure directory for ground truth
GROUND_TRUTH_DIR="/var/lib/wireshark_ground_truth"
mkdir -p "$GROUND_TRUTH_DIR"

# Compute ground truth using Python and tshark
# We process files one by one and aggregate results
echo "Computing ground truth..."

python3 << PYEOF
import subprocess
import json
import os
import sys

captures_dir = "$CAPTURES_DIR"
files = ["http.cap", "dns.cap", "telnet-cooked.pcap", "smtp.pcap"]
gt_dir = "$GROUND_TRUTH_DIR"

# Dictionary to store MAC info: 
# mac -> {vendor, src_count, dst_count, files_seen (set)}
mac_db = {}

def normalize_mac(mac):
    return mac.lower().strip()

def get_vendor(mac, resolved):
    # If resolved looks like the MAC, vendor wasn't found. 
    # Otherwise resolved usually contains "Vendor_XX:XX:XX" or just "Vendor"
    if resolved == mac:
        return "Unknown"
    # Wireshark often returns "Dell_1a:2b:3c" or "CiscoInc_..."
    # We take the part before the underscore if present, or the whole string
    return resolved.split('_')[0]

for fname in files:
    fpath = os.path.join(captures_dir, fname)
    if not os.path.exists(fpath):
        continue
        
    print(f"Processing {fname}...")
    
    # 1. Get Source MACs and counts
    # Format: eth.src | eth.src_resolved
    cmd = ["tshark", "-r", fpath, "-T", "fields", "-e", "eth.src", "-e", "eth.src_resolved"]
    try:
        output = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8')
        for line in output.splitlines():
            if not line.strip(): continue
            parts = line.split('\t')
            if len(parts) < 1: continue
            
            mac = normalize_mac(parts[0])
            resolved = parts[1] if len(parts) > 1 else mac
            
            if not mac: continue
            
            if mac not in mac_db:
                mac_db[mac] = {"vendor": "", "src_count": 0, "dst_count": 0, "files": set()}
            
            mac_db[mac]["src_count"] += 1
            mac_db[mac]["files"].add(fname)
            
            # Update vendor if we have a better name now
            current_vendor = mac_db[mac]["vendor"]
            new_vendor = get_vendor(parts[0], resolved)
            if new_vendor != "Unknown" and (current_vendor == "" or current_vendor == "Unknown"):
                mac_db[mac]["vendor"] = new_vendor
                
    except Exception as e:
        print(f"Error processing sources in {fname}: {e}")

    # 2. Get Destination MACs and counts
    cmd = ["tshark", "-r", fpath, "-T", "fields", "-e", "eth.dst", "-e", "eth.dst_resolved"]
    try:
        output = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8')
        for line in output.splitlines():
            if not line.strip(): continue
            parts = line.split('\t')
            if len(parts) < 1: continue
            
            mac = normalize_mac(parts[0])
            resolved = parts[1] if len(parts) > 1 else mac
            
            if not mac: continue
            
            if mac not in mac_db:
                mac_db[mac] = {"vendor": "", "src_count": 0, "dst_count": 0, "files": set()}
            
            mac_db[mac]["dst_count"] += 1
            mac_db[mac]["files"].add(fname)
            
            # Update vendor
            current_vendor = mac_db[mac]["vendor"]
            new_vendor = get_vendor(parts[0], resolved)
            if new_vendor != "Unknown" and (current_vendor == "" or current_vendor == "Unknown"):
                mac_db[mac]["vendor"] = new_vendor

    except Exception as e:
        print(f"Error processing destinations in {fname}: {e}")

# Find most active sender
most_active_mac = None
max_pkts = -1

for mac, info in mac_db.items():
    if info["src_count"] > max_pkts:
        max_pkts = info["src_count"]
        most_active_mac = mac

# Convert sets to lists for JSON serialization
serialized_macs = {}
for mac, info in mac_db.items():
    serialized_macs[mac] = {
        "vendor": info["vendor"],
        "src_count": info["src_count"],
        "dst_count": info["dst_count"],
        "files": list(info["files"])
    }

ground_truth = {
    "total_unique_macs": len(mac_db),
    "most_active_sender": most_active_mac,
    "most_active_sent_count": max_pkts,
    "mac_details": serialized_macs
}

with open(os.path.join(gt_dir, "ground_truth.json"), "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth generated. Found {len(mac_db)} unique MACs.")
PYEOF

chmod 644 "$GROUND_TRUTH_DIR/ground_truth.json"

# Launch Wireshark
echo "Starting Wireshark..."
if ! pgrep -f "wireshark" > /dev/null; then
    su - ga -c "DISPLAY=:1 wireshark &" &
    sleep 5
fi

# Wait for Wireshark window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "wireshark"; then
        echo "Wireshark window detected"
        break
    fi
    sleep 1
done

# Maximize Wireshark
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="