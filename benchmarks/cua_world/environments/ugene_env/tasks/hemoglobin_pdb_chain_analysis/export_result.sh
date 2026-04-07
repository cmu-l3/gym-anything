#!/bin/bash
echo "=== Exporting hemoglobin_pdb_chain_analysis results ==="

RESULTS_DIR="/home/ga/UGENE_Data/results"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We will use Python to safely parse the output FASTA and alignment files 
# and package them into a JSON payload for the verifier.
python3 << 'PYEOF'
import os
import json
import re

RESULTS_DIR = "/home/ga/UGENE_Data/results"
RESULT_JSON_PATH = "/tmp/task_result.json"

start_time = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = int(f.read().strip())
except Exception:
    pass

def parse_fasta(filename):
    path = os.path.join(RESULTS_DIR, filename)
    if not os.path.exists(path):
        return {"exists": False, "seqs": [], "created_during_task": False}
    
    mtime = os.path.getmtime(path)
    created_during_task = mtime >= start_time
    
    seqs = []
    curr = ""
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if curr: seqs.append(curr)
                curr = ""
            else:
                # Keep only letters to count true sequence length
                curr += re.sub(r'[^a-zA-Z]', '', line).upper()
        if curr:
            seqs.append(curr)
            
    return {"exists": True, "seqs": seqs, "created_during_task": created_during_task}

def parse_aln(filename):
    path = os.path.join(RESULTS_DIR, filename)
    if not os.path.exists(path):
        return {"exists": False, "is_clustal_format": False, "seq_count": 0, "created_during_task": False}
    
    mtime = os.path.getmtime(path)
    created_during_task = mtime >= start_time
    
    is_clustal = False
    seq_ids = set()
    
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        if "CLUSTAL" in content.upper() or "MUSCLE" in content.upper():
            is_clustal = True
            
        # Very basic ClustalW parser to count unique sequence identifiers
        lines = content.split('\n')
        for line in lines:
            line = line.strip()
            # In Clustal format, sequence lines start with an ID and then the sequence
            if line and not line.startswith("CLUSTAL") and not line.startswith("MUSCLE") and not line.startswith("*") and not line.startswith(" "):
                parts = line.split()
                if len(parts) >= 2 and re.match(r'^[A-Za-z0-9_-]+$', parts[0]):
                    seq_ids.add(parts[0])
                    
    return {
        "exists": True, 
        "is_clustal_format": is_clustal, 
        "seq_count": len(seq_ids), 
        "created_during_task": created_during_task
    }

def read_report(filename):
    path = os.path.join(RESULTS_DIR, filename)
    if not os.path.exists(path):
        return {"exists": False, "content": "", "created_during_task": False}
        
    mtime = os.path.getmtime(path)
    created_during_task = mtime >= start_time
    
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        # Read up to first 2000 chars to avoid massive files
        content = f.read(2000).lower()
        
    return {"exists": True, "content": content, "created_during_task": created_during_task}

# Collect all data
payload = {
    "chain_A": parse_fasta("chain_A.fasta"),
    "chain_B": parse_fasta("chain_B.fasta"),
    "chain_C": parse_fasta("chain_C.fasta"),
    "chain_D": parse_fasta("chain_D.fasta"),
    "all_chains": parse_fasta("all_chains.fasta"),
    "alignment": parse_aln("chains_alignment.aln"),
    "report": read_report("chain_analysis_report.txt")
}

# Write out the JSON for verifier
with open(RESULT_JSON_PATH, 'w', encoding='utf-8') as f:
    json.dump(payload, f, indent=2)

print("Result JSON exported successfully.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="