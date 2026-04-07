#!/bin/bash
echo "=== Setting up disguised_document_authorship_triage task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up stale artifacts and old cases
rm -f /tmp/authorship_triage_result.json /tmp/authorship_gt.json /tmp/task_start_time.txt 2>/dev/null || true
for d in /home/ga/Cases/Authorship_Triage_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
mkdir -p /home/ga/evidence/seized_docs
rm -rf /home/ga/evidence/seized_docs/*
chown -R ga:ga /home/ga/Reports/ /home/ga/evidence/seized_docs/ 2>/dev/null || true

# 2. Dynamically generate the dataset (HTML & RTF files disguised as system files)
echo "Generating disguised document dataset..."
python3 << 'PYEOF'
import os, hashlib, json

out_dir = "/home/ga/evidence/seized_docs"

# Files disguised with fake extensions
files_to_create = [
    {"name": "system_cache_01.dat", "type": "html", "author": "A. Smith", "content": "<html><head><meta name=\"author\" content=\"A. Smith\"></head><body>Project X details and proprietary algorithms.</body></html>"},
    {"name": "temp_spool_14.tmp", "type": "rtf", "author": "A. Smith", "content": "{\\rtf1\\ansi{\\info{\\author A. Smith}} Secret financial records for offshore accounts.}"},
    {"name": "win_config_old.sys", "type": "html", "author": "A. Smith", "content": "<html><head><meta name=\"author\" content=\"A. Smith\"></head><body>Offshore accounts routing numbers.</body></html>"},
    
    # Decoys by a different author
    {"name": "system_cache_02.dat", "type": "html", "author": "B. Jones", "content": "<html><head><meta name=\"author\" content=\"B. Jones\"></head><body>Lunch menu for the week of October 12th.</body></html>"},
    {"name": "temp_spool_15.tmp", "type": "rtf", "author": "B. Jones", "content": "{\\rtf1\\ansi{\\info{\\author B. Jones}} Draft letter regarding the printer malfunction.}"},
    {"name": "win_config_new.sys", "type": "html", "author": "B. Jones", "content": "<html><head><meta name=\"author\" content=\"B. Jones\"></head><body>Standard server configuration backups.</body></html>"},
]

gt_data = {
    "target_author": "A. Smith",
    "target_files": [],
    "decoy_files": [],
    "total_files": 0
}

# Create documents
for f in files_to_create:
    path = os.path.join(out_dir, f["name"])
    with open(path, "w") as out:
        out.write(f["content"])
    
    md5 = hashlib.md5(f["content"].encode('utf-8')).hexdigest()
    mime = "text/html" if f["type"] == "html" else "text/rtf"
    
    info = {"name": f["name"], "md5": md5, "mime": mime}
    if f["author"] == "A. Smith":
        gt_data["target_files"].append(info)
    else:
        gt_data["decoy_files"].append(info)
    
    gt_data["total_files"] += 1

# Create pure dummy binary files (no author)
for i in range(2):
    name = f"random_data_{i}.bin"
    path = os.path.join(out_dir, name)
    rand_bytes = os.urandom(2048)
    with open(path, "wb") as out:
        out.write(rand_bytes)
    
    md5 = hashlib.md5(rand_bytes).hexdigest()
    gt_data["decoy_files"].append({"name": name, "md5": md5, "mime": "application/octet-stream"})
    gt_data["total_files"] += 1

with open("/tmp/authorship_gt.json", "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Generated {gt_data['total_files']} files. Target files: {len(gt_data['target_files'])}.")
PYEOF

chown -R ga:ga /home/ga/evidence/seized_docs/

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Launch Autopsy and wait for UI
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy Welcome screen..."
wait_for_autopsy_window 300

# Dismiss welcome screen dialogs if needed
sleep 5
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Maximize Autopsy window
DISPLAY=:1 wmctrl -r "Autopsy" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="