#!/bin/bash
echo "=== Exporting implement_hgv_bottleneck_ban result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Write Python evaluation script to safely check networks and compute ground truth
cat > /tmp/eval_task.py << 'EOF'
import os, json, time
import xml.etree.ElementTree as ET
import subprocess

res = {
    "report_exists": False,
    "reported_edge": "",
    "reported_baseline_dur": 0.0,
    "reported_ban_dur": 0.0,
    "gt_max_edges": [],
    "gt_max_count": 0,
    "net_exists": False,
    "ban_implemented": False,
    "ban_tripinfo_exists": False,
    "actual_baseline_dur": 0.0,
    "actual_ban_dur": 0.0,
    "baseline_truck_count": 0,
    "ban_truck_count": 0,
    "files_modified_after_start": False
}

TASK_START = int(os.environ.get("TASK_START", "0"))

# 1. Parse HGV report
report_path = "/home/ga/SUMO_Output/hgv_report.txt"
if os.path.exists(report_path):
    res["report_exists"] = True
    try:
        with open(report_path, "r") as f:
            for line in f:
                line = line.strip()
                if ":" in line:
                    k, v = line.split(":", 1)
                    k = k.strip()
                    v = v.strip()
                    if k == "banned_edge": res["reported_edge"] = v
                    elif k == "baseline_truck_avg_duration": res["reported_baseline_dur"] = float(v)
                    elif k == "ban_truck_avg_duration": res["reported_ban_dur"] = float(v)
    except Exception:
        pass

# 2. Compute Ground Truth Max Edges
# Run baseline with our own edgeData output to prevent gaming
with open("/tmp/gt_edgedata.add.xml", "w") as f:
    f.write('<additional><edgeData id="gt" file="/tmp/gt_edgedata.xml" vTypes="truck_type"/></additional>')

subprocess.run(["sumo", "-c", "/home/ga/SUMO_Scenarios/bologna_acosta/baseline.sumocfg",
                "--additional-files", "/tmp/gt_edgedata.add.xml",
                "--tripinfo-output", "/tmp/gt_tripinfo.xml",
                "--no-warnings"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

if os.path.exists("/tmp/gt_edgedata.xml"):
    try:
        tree = ET.parse("/tmp/gt_edgedata.xml")
        counts = {}
        for interval in tree.findall("interval"):
            for edge in interval.findall("edge"):
                eid = edge.get("id")
                if not eid.startswith(":"):  # exclude internal edges
                    counts[eid] = counts.get(eid, 0) + int(edge.get("entered", 0))

        if counts:
            max_c = max(counts.values())
            res["gt_max_count"] = max_c
            res["gt_max_edges"] = [e for e, c in counts.items() if c == max_c]
    except Exception:
        pass

# 3. Check Agent's Network Modification
net_path = "/home/ga/SUMO_Scenarios/bologna_acosta/acosta_hgv_ban.net.xml"
if os.path.exists(net_path):
    res["net_exists"] = True
    mtime = os.path.getmtime(net_path)
    if mtime > TASK_START:
        res["files_modified_after_start"] = True

    try:
        tree = ET.parse(net_path)
        edge_found = False
        lanes_banned = 0
        total_lanes = 0
        for edge in tree.findall("edge"):
            if edge.get("id") == res["reported_edge"]:
                edge_found = True
                for lane in edge.findall("lane"):
                    total_lanes += 1
                    allow = lane.get("allow", "")
                    disallow = lane.get("disallow", "")
                    
                    # Verify 'truck' class is banned
                    if "truck" in disallow or "all" in disallow:
                        lanes_banned += 1
                    elif allow != "" and "truck" not in allow:
                        lanes_banned += 1
                        
        if edge_found and total_lanes > 0 and lanes_banned == total_lanes:
            res["ban_implemented"] = True
    except Exception:
        pass

# 4. Parse tripinfos to grade analytical accuracy
def get_avg_dur(path):
    if not os.path.exists(path): return 0.0, 0
    try:
        tree = ET.parse(path)
        durs = []
        for t in tree.findall("tripinfo"):
            if t.get("vType") == "truck_type":
                durs.append(float(t.get("duration", 0)))
        if durs: return sum(durs)/len(durs), len(durs)
    except Exception: pass
    return 0.0, 0

base_dur, base_count = get_avg_dur("/home/ga/SUMO_Output/baseline_tripinfo.xml")
ban_dur, ban_count = get_avg_dur("/home/ga/SUMO_Output/ban_tripinfo.xml")

if os.path.exists("/home/ga/SUMO_Output/ban_tripinfo.xml"):
    res["ban_tripinfo_exists"] = True
    b_mtime = os.path.getmtime("/home/ga/SUMO_Output/ban_tripinfo.xml")
    if b_mtime > TASK_START:
        res["files_modified_after_start"] = True

res["actual_baseline_dur"] = base_dur
res["actual_ban_dur"] = ban_dur
res["baseline_truck_count"] = base_count
res["ban_truck_count"] = ban_count

# Write JSON result
with open("/tmp/task_result.json", "w") as f:
    json.dump(res, f)
EOF

# Run evaluation script safely
export TASK_START="$TASK_START"
su - ga -c "python3 /tmp/eval_task.py"

# Secure permissions for verifier reading
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="