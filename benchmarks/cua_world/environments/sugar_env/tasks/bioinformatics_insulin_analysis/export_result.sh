#!/bin/bash
echo "=== Exporting bioinformatics_insulin_analysis task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/bio_task_end.png" 2>/dev/null || true

# Run Python script to perform static checks AND dynamic anti-gaming execution
python3 << 'PYEOF'
import json
import os
import re
import shutil
import subprocess

res = {
    "script_exists": False,
    "report_exists": False,
    "report_modified": False,
    "static_length": False,
    "static_counts": {"A": False, "C": False, "G": False, "T": False},
    "static_gc": False,
    "static_mrna_ok": False,
    "dynamic_success": False,
    "dynamic_length": False,
    "dynamic_counts": {"A": False, "C": False, "G": False, "T": False},
    "dynamic_gc": False,
    "dynamic_mrna_ok": False,
    "error": None
}

try:
    with open('/tmp/bio_start_ts', 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

script_path = '/home/ga/Documents/dna_analyzer.py'
report_path = '/home/ga/Documents/insulin_report.txt'
fasta_path = '/home/ga/Documents/insulin.fasta'

# 1. Evaluate Static Results
if os.path.exists(script_path):
    res['script_exists'] = True

if os.path.exists(report_path):
    res['report_exists'] = True
    try:
        mtime = os.stat(report_path).st_mtime
        res['report_modified'] = mtime > task_start
    except Exception:
        pass
        
    with open(report_path, 'r', errors='ignore') as f:
        content = f.read()
        
    res['static_length'] = bool(re.search(r'\b465\b', content))
    res['static_counts']['A'] = bool(re.search(r'\b97\b', content))
    res['static_counts']['C'] = bool(re.search(r'\b172\b', content))
    res['static_counts']['G'] = bool(re.search(r'\b131\b', content))
    res['static_counts']['T'] = bool(re.search(r'\b65\b', content))
    # Look for GC percentage (~65.16)
    res['static_gc'] = bool(re.search(r'65\.1\d*|65\.2\d*', content))
    # Look for transcribed mRNA sequence (contains U, no T)
    res['static_mrna_ok'] = bool(re.search(r'\b[ACGUacgu]{50,}\b', content))

# 2. Dynamic Execution (Anti-Gaming Check)
if res['script_exists']:
    backup_fasta = fasta_path + '.bak'
    backup_report = report_path + '.bak'
    
    try:
        if os.path.exists(fasta_path):
            shutil.move(fasta_path, backup_fasta)
        if os.path.exists(report_path):
            shutil.move(report_path, backup_report)
            
        # Create a new testing sequence (Length: 100, GC: 50.0%)
        test_seq = "A"*10 + "C"*20 + "G"*30 + "T"*40
        with open(fasta_path, 'w') as f:
            f.write(">Test_Sequence_Hidden\n")
            f.write(test_seq + "\n")
            
        # Execute the agent's script
        subprocess.run(['python3', script_path], cwd='/home/ga/Documents', timeout=15)
        
        # Verify the dynamic output
        if os.path.exists(report_path):
            res['dynamic_success'] = True
            with open(report_path, 'r', errors='ignore') as f:
                dyn_content = f.read()
                
            res['dynamic_length'] = bool(re.search(r'\b100\b', dyn_content))
            res['dynamic_counts']['A'] = bool(re.search(r'\b10\b', dyn_content))
            res['dynamic_counts']['C'] = bool(re.search(r'\b20\b', dyn_content))
            res['dynamic_counts']['G'] = bool(re.search(r'\b30\b', dyn_content))
            res['dynamic_counts']['T'] = bool(re.search(r'\b40\b', dyn_content))
            res['dynamic_gc'] = bool(re.search(r'50\.0\d*|50\s*%', dyn_content))
            res['dynamic_mrna_ok'] = bool(re.search(r'\b[ACGUacgu]{50,}\b', dyn_content))
            
    except subprocess.TimeoutExpired:
        res['error'] = "Dynamic execution timed out."
    except Exception as e:
        res['error'] = str(e)
    finally:
        # Restore original state
        if os.path.exists(backup_fasta):
            shutil.move(backup_fasta, fasta_path)
        if os.path.exists(backup_report):
            shutil.move(backup_report, report_path)

# Save result for verifier
with open('/tmp/bioinformatics_result.json', 'w') as f:
    json.dump(res, f)
PYEOF

chmod 666 /tmp/bioinformatics_result.json
echo "Result saved to /tmp/bioinformatics_result.json"
cat /tmp/bioinformatics_result.json
echo "=== Export complete ==="