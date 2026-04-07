#!/bin/bash
echo "=== Exporting simulate_signal_power_outage result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We will use Python to safely check timestamps, parse XML line counts, 
# and safely escape the report content into JSON to avoid Bash string escaping issues.
python3 - << 'EOF'
import json
import os

task_start = 0
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except Exception as e:
    print(f"Warning: Could not read task start time: {e}")

outdir = "/home/ga/SUMO_Output"

def check_file(filename):
    path = os.path.join(outdir, filename)
    if os.path.exists(path):
        mtime = os.stat(path).st_mtime
        if mtime >= task_start:
            return "true"
        return "false_old"
    return "false"

result = {
    "outage_net": check_file("pasubio_outage.net.xml"),
    "base_cfg": check_file("run_baseline.sumocfg"),
    "out_cfg": check_file("run_outage.sumocfg"),
    "base_trip": check_file("baseline_tripinfo.xml"),
    "base_log": check_file("baseline_log.txt"),
    "out_trip": check_file("outage_tripinfo.xml"),
    "out_log": check_file("outage_log.txt"),
    "report": check_file("resilience_report.txt"),
    "tllogic_count": -1,
    "report_content": "",
    "outage_cfg_contains_tls": False
}

# Safely check tlLogic count in the generated network
net_path = os.path.join(outdir, "pasubio_outage.net.xml")
if os.path.exists(net_path):
    try:
        with open(net_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            result["tllogic_count"] = content.count("<tlLogic")
    except Exception as e:
        print(f"Warning reading network file: {e}")

# Check if the agent mistakenly included the TLS definitions in the outage config
out_cfg_path = os.path.join(outdir, "run_outage.sumocfg")
if os.path.exists(out_cfg_path):
    try:
        with open(out_cfg_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            result["outage_cfg_contains_tls"] = "pasubio_tls.add.xml" in content
    except Exception as e:
        print(f"Warning reading outage config: {e}")

# Extract the report content
rep_path = os.path.join(outdir, "resilience_report.txt")
if os.path.exists(rep_path):
    try:
        with open(rep_path, "r", encoding="utf-8", errors="ignore") as f:
            result["report_content"] = f.read()
    except Exception as e:
        print(f"Warning reading report: {e}")

# Write strictly formatted JSON
with open("/tmp/task_result.json", "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)

EOF

# Ensure permissions are correct so copy_from_env can grab it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="