#!/bin/bash
set -e
echo "=== Setting up hpv_integration_mapping task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/UGENE_Data/integration_mapping/results
chown -R ga:ga /home/ga/UGENE_Data/integration_mapping

# Prepare the data using Python
# We fetch real reference sequences from NCBI and construct the chimeric fragment
python3 << 'PYEOF'
import urllib.request
import json
import re
import sys
import os

def fetch_gb(acc):
    url = f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id={acc}&rettype=gb&retmode=text"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.read().decode('utf-8')
    except Exception as e:
        print(f"Failed to fetch {acc}: {e}")
        return None

print("Fetching Human MYC reference (K02224.1)...")
myc_gb = fetch_gb("K02224.1")

print("Fetching HPV16 reference (NC_001526.4)...")
hpv_gb = fetch_gb("NC_001526.4")

if not myc_gb or not hpv_gb:
    print("ERROR: Could not download reference sequences from NCBI.")
    sys.exit(1)

# Save reference files
with open('/home/ga/UGENE_Data/integration_mapping/human_MYC_reference.gb', 'w') as f:
    f.write(myc_gb)
with open('/home/ga/UGENE_Data/integration_mapping/HPV16_reference.gb', 'w') as f:
    f.write(hpv_gb)

# Extract ORIGIN sequences
def extract_origin(gb_text):
    match = re.search(r'ORIGIN\s+(.*?)(?://|$)', gb_text, re.DOTALL)
    if match:
        return re.sub(r'[\d\s\n]', '', match.group(1)).upper()
    return ""

myc_seq = extract_origin(myc_gb)
hpv_seq = extract_origin(hpv_gb)

if len(myc_seq) < 3000 or len(hpv_seq) < 6000:
    print("ERROR: Downloaded sequences are too short.")
    sys.exit(1)

# Build chimeric patient fragment
# Human MYC: bases 1000 to 3000 (length 2000)
# HPV16: bases 2500 to 6000 (length 3500)
# Breakpoint at 2000 in the resulting fragment
fragment = myc_seq[1000:3000] + hpv_seq[2500:6000]

fasta = ">patient_tumor_fragment Chimeric MYC-HPV16 sequence\n"
for i in range(0, len(fragment), 70):
    fasta += fragment[i:i+70] + "\n"

with open('/home/ga/UGENE_Data/integration_mapping/patient_tumor_fragment.fasta', 'w') as f:
    f.write(fasta)

# Save Ground Truth for verifier
gt = {
    "human_start": 1,
    "human_end": 2000,
    "viral_start": 2001,
    "viral_end": 5500,
    "breakpoint": 2000,
    "expected_genes": ["E2", "E4", "E5"]
}
with open('/tmp/hpv_integration_mapping_gt.json', 'w') as f:
    json.dump(gt, f)

print("Data preparation complete.")
PYEOF

chown -R ga:ga /home/ga/UGENE_Data/integration_mapping

# Kill any existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 2

# Launch UGENE
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected."
        break
    fi
    sleep 2
done

# Give UI time to initialize
sleep 5

# Maximize UGENE window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
fi

# Dismiss any popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for verification evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="