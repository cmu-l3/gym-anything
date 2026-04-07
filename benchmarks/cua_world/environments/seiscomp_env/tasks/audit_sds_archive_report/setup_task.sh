#!/bin/bash
echo "=== Setting up audit_sds_archive_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Ensure data exists in the archive
ARCHIVE_DIR="/home/ga/seiscomp/var/lib/archive"
if [ ! -d "$ARCHIVE_DIR" ]; then
    echo "ERROR: SDS archive directory not found at $ARCHIVE_DIR"
    exit 1
fi

# 3. Compute ground truth using a Python script
# This dynamically evaluates exactly what is in the archive to avoid hardcoding
cat > /tmp/compute_ground_truth.py << 'EOF'
import os
import json

archive_dir = "/home/ga/seiscomp/var/lib/archive"
gt = {
    "networks": set(),
    "stations": set(),
    "channels": set(),
    "details": [],
    "total_files": 0,
    "total_size": 0
}

if os.path.exists(archive_dir):
    for year in os.listdir(archive_dir):
        year_path = os.path.join(archive_dir, year)
        if not os.path.isdir(year_path): continue
        
        for net in os.listdir(year_path):
            net_path = os.path.join(year_path, net)
            if not os.path.isdir(net_path): continue
            gt["networks"].add(net)
            
            for sta in os.listdir(net_path):
                sta_path = os.path.join(net_path, sta)
                if not os.path.isdir(sta_path): continue
                gt["stations"].add(sta)
                
                for cha_d in os.listdir(sta_path):
                    cha_path = os.path.join(sta_path, cha_d)
                    if not os.path.isdir(cha_path): continue
                    
                    # Extract channel from "BHE.D"
                    cha = cha_d.replace(".D", "")
                    gt["channels"].add(cha)
                    
                    files = [f for f in os.listdir(cha_path) if os.path.isfile(os.path.join(cha_path, f))]
                    num_files = len(files)
                    size = sum(os.path.getsize(os.path.join(cha_path, f)) for f in files)
                    
                    gt["total_files"] += num_files
                    gt["total_size"] += size
                    
                    dates = []
                    for f in files:
                        # Format: NET.STA.LOC.CHA.TYPE.YEAR.DOY
                        parts = f.split('.')
                        if len(parts) >= 7:
                            dates.append(f"{parts[-2]}.{parts[-1]}")
                    
                    if dates:
                        dates.sort()
                        date_range = f"{dates[0]}-{dates[-1]}"
                    else:
                        date_range = "Unknown"
                        
                    gt["details"].append({
                        "net": net,
                        "sta": sta,
                        "cha": cha,
                        "files": num_files,
                        "size": size,
                        "date_range": date_range
                    })

# Convert sets to lists for JSON serialization
gt["networks"] = sorted(list(gt["networks"]))
gt["stations"] = sorted(list(gt["stations"]))
gt["channels"] = sorted(list(gt["channels"]))

with open("/tmp/archive_ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)
EOF

python3 /tmp/compute_ground_truth.py
echo "Ground truth computed and saved to /tmp/archive_ground_truth.json"

# 4. Clean up any previous task artifacts
rm -f /home/ga/data_availability_report.txt 2>/dev/null || true

# 5. Open a terminal for the agent
echo "Starting terminal..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
sleep 3

# Focus and maximize terminal
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
fi

sleep 1

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="