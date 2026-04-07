#!/bin/bash
echo "=== Exporting Workflow Designer Pipeline Results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Execute Python script inside the container to safely parse and evaluate files
# This guarantees we extract correct sequences counts, lengths, and UWL schema info
python3 << 'EOF'
import json
import os
import glob

res_dir = "/home/ga/UGENE_Data/workflow_results"
start_time_file = "/tmp/task_start_time.txt"

# Read task start time (with 10s buffer for slight system delays)
start_ts = 0
if os.path.exists(start_time_file):
    try:
        with open(start_time_file) as f:
            start_ts = int(f.read().strip()) - 10
    except:
        pass

def is_created_during_task(fpath):
    if not os.path.exists(fpath): return False
    return os.path.getmtime(fpath) >= start_ts

result = {
    "uwl_exists": False,
    "uwl_size": 0,
    "uwl_has_clustal": False,
    "uwl_has_structure": False,
    "aln_exists": False,
    "aln_size": 0,
    "valid_format": False,
    "seq_count": 0,
    "is_aligned": False
}

# 1. Analyze Workflow Schema (.uwl)
uwl_files = glob.glob(os.path.join(res_dir, "*.uwl")) + glob.glob(os.path.join(res_dir, "*.wf"))
if uwl_files:
    target_uwl = uwl_files[0]
    if is_created_during_task(target_uwl):
        result["uwl_exists"] = True
        result["uwl_size"] = os.path.getsize(target_uwl)
        try:
            with open(target_uwl, 'r', errors='ignore') as f:
                content = f.read().lower()
                if 'clustal' in content:
                    result["uwl_has_clustal"] = True
                
                # Check for XML/JSON workflow schema structural elements
                structural_tags = ['<workflow', '<actor', '<element', '<port', '<connection', 'type:', 'script:']
                tag_count = sum(1 for tag in structural_tags if tag in content)
                if tag_count >= 2:
                    result["uwl_has_structure"] = True
        except Exception:
            pass

# 2. Analyze Alignment Output
# Check any file that isn't the workflow file
aln_files = [f for f in glob.glob(os.path.join(res_dir, "*")) if not f.endswith(".uwl") and os.path.isfile(f)]

for af in aln_files:
    if not is_created_during_task(af):
        continue
    if os.path.getsize(af) < 50:
        continue
        
    result["aln_exists"] = True
    result["aln_size"] = os.path.getsize(af)
    
    seqs = {}
    
    # Try parsing as FASTA format
    try:
        with open(af, 'r', errors='ignore') as f:
            curr = None
            for line in f:
                line = line.strip()
                if not line: continue
                if line.startswith('>'):
                    curr = line[1:]
                    seqs[curr] = ''
                elif curr:
                    seqs[curr] += line
    except Exception:
        pass
        
    if len(seqs) >= 4:
        result["valid_format"] = True
        result["seq_count"] = len(seqs)
        lengths = set(len(s) for s in seqs.values())
        result["is_aligned"] = (len(lengths) == 1 and list(lengths)[0] > 0)
        break

    # Try parsing as Clustal/Stockholm format
    seqs = {}
    try:
        with open(af, 'r', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('CLUSTAL') or line.startswith('#') or line.startswith('*'):
                    continue
                parts = line.split()
                if len(parts) >= 2:
                    name = parts[0]
                    if name not in seqs: seqs[name] = ''
                    seqs[name] += parts[1]
    except Exception:
        pass

    if len(seqs) >= 4:
        result["valid_format"] = True
        result["seq_count"] = len(seqs)
        lengths = set(len(s) for s in seqs.values())
        result["is_aligned"] = (len(lengths) == 1 and list(lengths)[0] > 0)
        break

# Write evaluation to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export Complete. Results saved to /tmp/task_result.json"