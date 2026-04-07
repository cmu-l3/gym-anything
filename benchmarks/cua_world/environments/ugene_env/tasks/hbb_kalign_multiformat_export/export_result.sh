#!/bin/bash
echo "=== Exporting task results ==="

# Record final state
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Run Python script to parse and export results cleanly into JSON
python3 << 'EOF'
import json
import os
import re

start_time = 0
try:
    with open('/tmp/task_start_time.txt') as f:
        start_time = float(f.read().strip())
except Exception:
    pass

results_dir = '/home/ga/UGENE_Data/results'
res = {
    "fasta": {"exists": False, "valid": False, "seq_count": 0, "aln_length": 0, "new": False},
    "phy": {"exists": False, "valid": False, "seq_count": 0, "aln_length": 0, "new": False},
    "aln": {"exists": False, "valid": False, "seq_count": 0, "aln_length": 0, "new": False},
    "report": {"exists": False, "content": "", "new": False}
}

# Helper to check if file was created/modified during task
def is_new(filepath):
    return os.path.exists(filepath) and os.path.getmtime(filepath) > start_time

# 1. FASTA Checks
f_path = os.path.join(results_dir, 'hbb_kalign.fasta')
if os.path.exists(f_path):
    res["fasta"]["exists"] = True
    res["fasta"]["new"] = is_new(f_path)
    try:
        with open(f_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            seqs = [l for l in lines if l.startswith('>')]
            res["fasta"]["seq_count"] = len(seqs)
            res["fasta"]["valid"] = len(seqs) > 0
            
            if len(seqs) > 0:
                seq_data = ""
                for l in lines[1:]:
                    if l.startswith('>'): break
                    seq_data += l.strip()
                res["fasta"]["aln_length"] = len(seq_data)
    except Exception as e:
        print(f"Error parsing FASTA: {e}")

# 2. PHYLIP Checks
p_path = os.path.join(results_dir, 'hbb_kalign.phy')
if os.path.exists(p_path):
    res["phy"]["exists"] = True
    res["phy"]["new"] = is_new(p_path)
    try:
        with open(p_path, 'r', encoding='utf-8') as f:
            lines = [l.strip() for l in f.readlines() if l.strip()]
            if lines:
                parts = lines[0].split()
                if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
                    res["phy"]["valid"] = True
                    res["phy"]["seq_count"] = int(parts[0])
                    res["phy"]["aln_length"] = int(parts[1])
    except Exception as e:
        print(f"Error parsing PHYLIP: {e}")

# 3. ClustalW Checks
a_path = os.path.join(results_dir, 'hbb_kalign.aln')
if os.path.exists(a_path):
    res["aln"]["exists"] = True
    res["aln"]["new"] = is_new(a_path)
    try:
        with open(a_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            if lines and ("CLUSTAL" in lines[0].upper() or "MUSCLE" in lines[0].upper() or "MAFFT" in lines[0].upper()):
                res["aln"]["valid"] = True
                prefixes = set()
                for l in lines[1:]:
                    if l.strip() and not l.startswith(' ') and not l.startswith('*') and not l.startswith('-'):
                        parts = l.split()
                        if len(parts) >= 2:
                            prefixes.add(parts[0])
                res["aln"]["seq_count"] = len(prefixes)
                
                # Estimate length
                if prefixes:
                    first_seq = list(prefixes)[0]
                    length = 0
                    for l in lines:
                        if l.startswith(first_seq):
                            parts = l.split()
                            if len(parts) >= 2:
                                length += len(parts[1])
                    res["aln"]["aln_length"] = length
    except Exception as e:
        print(f"Error parsing ALN: {e}")

# 4. Report Checks
r_path = os.path.join(results_dir, 'identity_report.txt')
if os.path.exists(r_path):
    res["report"]["exists"] = True
    res["report"]["new"] = is_new(r_path)
    try:
        with open(r_path, 'r', encoding='utf-8') as f:
            res["report"]["content"] = f.read()
    except Exception as e:
        print(f"Error parsing Report: {e}")

# Ensure file is saved securely
with open('/tmp/task_result.json', 'w') as f:
    json.dump(res, f, indent=2)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export logic complete. Result JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="