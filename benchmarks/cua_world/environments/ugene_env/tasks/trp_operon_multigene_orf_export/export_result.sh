#!/bin/bash
echo "=== Exporting trp_operon_multigene_orf_export results ==="

# Export for Python context
export TASK_END=$(date +%s)
export TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract data using Python
python3 << 'EOF'
import json, os, re

res_dir = "/home/ga/UGENE_Data/ecoli_trp_operon/results"
genes = ["trpE", "trpD", "trpC", "trpB", "trpA"]

data = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "report_exists": False,
    "report_content": ""
}

for g in genes:
    fpath = f"{res_dir}/{g}_protein.fasta"
    g_data = {"exists": False, "length": 0, "starts_with_M": False, "created_during_task": False}
    if os.path.exists(fpath):
        g_data["exists"] = True
        
        mtime = os.path.getmtime(fpath)
        if mtime >= data["task_start"]:
            g_data["created_during_task"] = True
            
        try:
            with open(fpath, 'r') as f:
                lines = f.readlines()
                seq = "".join([l.strip() for l in lines if not l.startswith(">")])
                g_data["length"] = len(seq)
                if len(seq) > 0 and seq[0].upper() == 'M':
                    g_data["starts_with_M"] = True
        except Exception:
            pass
    data[g] = g_data

rep_path = f"{res_dir}/trp_operon_report.txt"
if os.path.exists(rep_path):
    data["report_exists"] = True
    try:
        with open(rep_path, 'r', errors='ignore') as f:
            data["report_content"] = f.read()[:5000]
    except Exception:
        pass

with open("/tmp/trp_operon_result.json", "w") as f:
    json.dump(data, f)
EOF

chmod 666 /tmp/trp_operon_result.json 2>/dev/null || sudo chmod 666 /tmp/trp_operon_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/trp_operon_result.json"
cat /tmp/trp_operon_result.json
echo "=== Export Complete ==="