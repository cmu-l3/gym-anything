#!/bin/bash
echo "=== Setting up insulin_cpg_gc_profiling task ==="

# 1. Clean previous task state
rm -rf /home/ga/UGENE_Data/cpg_results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/cpg_results

# Ensure input data exists
if [ ! -s /opt/ugene_data/human_insulin_gene.gb ]; then
    echo "ERROR: Human insulin gene GenBank file not found"
    exit 1
fi

cp /opt/ugene_data/human_insulin_gene.gb /home/ga/UGENE_Data/human_insulin_gene.gb
chown -R ga:ga /home/ga/UGENE_Data

# 2. Compute Ground Truth from the exact file
echo "Computing ground truth from sequence..."
python3 << 'PYEOF'
import json
import re

try:
    with open("/home/ga/UGENE_Data/human_insulin_gene.gb", "r") as f:
        gb_data = f.read()
    
    # Extract original annotation count
    orig_features = len(re.findall(r'\s{5}\w+\s+(?:complement\()?<?\d+\.\.>?\d+', gb_data))
    
    # Extract sequence
    origin_match = re.search(r'ORIGIN\s+(.*?)(?:\/\/|$)', gb_data, re.DOTALL)
    if origin_match:
        seq = re.sub(r'[\d\s\n]', '', origin_match.group(1)).upper()
        length = len(seq)
        a_count = seq.count('A')
        t_count = seq.count('T')
        g_count = seq.count('G')
        c_count = seq.count('C')
        cg_count = seq.count('CG')
        
        if length > 0:
            gc_pct = (g_count + c_count) / length * 100
        else:
            gc_pct = 0.0
            
        gt = {
            "success": True,
            "length": length,
            "a_count": a_count,
            "t_count": t_count,
            "g_count": g_count,
            "c_count": c_count,
            "cg_count": cg_count,
            "gc_pct": gc_pct,
            "orig_features": orig_features
        }
    else:
        gt = {"success": False, "error": "Could not find ORIGIN"}
        
    with open("/tmp/insulin_cpg_gt.json", "w") as f:
        json.dump(gt, f)
    print(f"Ground truth generated: {length}bp, {cg_count} CpGs, {gc_pct:.1f}% GC")
except Exception as e:
    print(f"Error generating GT: {e}")
PYEOF

# 3. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 4. Launch UGENE
echo "Launching UGENE..."
pkill -f "ugene" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 5. Wait for UGENE window
TIMEOUT=60
ELAPSED=0
STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        STARTED=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$STARTED" = true ]; then
    sleep 5
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Maximize and focus the UGENE window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Take initial screenshot
    DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true
    echo "Initial screenshot saved"
else
    echo "WARNING: UGENE failed to start within timeout"
fi

echo "=== Task setup complete ==="