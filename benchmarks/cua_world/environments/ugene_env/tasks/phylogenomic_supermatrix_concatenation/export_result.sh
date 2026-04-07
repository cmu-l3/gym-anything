#!/bin/bash
echo "=== Exporting Phylogenomic Supermatrix Concatenation Results ==="

# Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Execute a Python script to parse the output ClustalW files and generate the JSON
python3 << 'PYEOF'
import json
import os
import time

# Function to safely extract ClustalW alignments into a dictionary {Taxon: Sequence}
def parse_clustal(filepath):
    if not os.path.exists(filepath): 
        return {}
    seqs = {}
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            # Ignore headers, whitespace, and conservation markers (*)
            if line and not line.startswith('CLUSTAL') and not line.startswith('MUSCLE') and not line.startswith('MAFFT') and not line.startswith('*') and not line.startswith(' '):
                parts = line.split()
                if len(parts) >= 2:
                    taxon = parts[0]
                    seq = parts[1]
                    # Only grab our expected taxa to ignore random malformed lines
                    if taxon in ['Ecoli', 'Senterica', 'Ypestis', 'Sflexneri', 'Vcholerae']:
                        seqs[taxon] = seqs.get(taxon, "") + seq
    return seqs

# Paths
results_dir = '/home/ga/UGENE_Data/phylogenomics/results/'
reca_path = os.path.join(results_dir, 'recA_aligned.aln')
rpob_path = os.path.join(results_dir, 'rpoB_aligned.aln')
superm_path = os.path.join(results_dir, 'supermatrix.aln')
report_path = os.path.join(results_dir, 'supermatrix_report.txt')

# Parse Alignments
reca = parse_clustal(reca_path)
rpob = parse_clustal(rpob_path)
superm = parse_clustal(superm_path)

# Determine Lengths
reca_len = len(list(reca.values())[0]) if reca else 0
rpob_len = len(list(rpob.values())[0]) if rpob else 0
superm_len = len(list(superm.values())[0]) if superm else 0

# Determine Matrix Math
matrix_math_valid = False
if reca_len > 0 and rpob_len > 0 and superm_len == (reca_len + rpob_len):
    matrix_math_valid = True

# Determine Horizontal Integrity (Anti-Gaming Check)
# Check if Ecoli sequence in supermatrix is exactly Ecoli_recA + Ecoli_rpoB
horizontal_valid = False
if superm and reca and rpob and 'Ecoli' in superm and 'Ecoli' in reca and 'Ecoli' in rpob:
    expected_ecoli = reca['Ecoli'] + rpob['Ecoli']
    if superm['Ecoli'] == expected_ecoli:
        horizontal_valid = True

# Read Start Timestamp
task_start = 0
if os.path.exists('/tmp/task_start_time.txt'):
    with open('/tmp/task_start_time.txt', 'r') as f:
        try:
            task_start = int(f.read().strip())
        except:
            pass

# Check supermatrix creation timestamp
superm_mtime = os.path.getmtime(superm_path) if os.path.exists(superm_path) else 0
created_during_task = superm_mtime >= task_start if task_start > 0 else False

# Check Report
report_ok = False
report_content = ""
if os.path.exists(report_path):
    with open(report_path, 'r') as f:
        report_content = f.read()
    
    # Check if report contains taxa and all lengths
    taxa_present = all(t in report_content for t in ['Ecoli', 'Senterica', 'Ypestis', 'Sflexneri', 'Vcholerae'])
    lengths_present = str(reca_len) in report_content and str(rpob_len) in report_content and str(superm_len) in report_content
    if taxa_present and lengths_present:
        report_ok = True

# Construct JSON result
result = {
    "reca_has_5_taxa": len(reca) == 5,
    "rpob_has_5_taxa": len(rpob) == 5,
    "superm_has_5_taxa": len(superm) == 5,
    "reca_len": reca_len,
    "rpob_len": rpob_len,
    "superm_len": superm_len,
    "matrix_math_valid": matrix_math_valid,
    "horizontal_valid": horizontal_valid,
    "created_during_task": created_during_task,
    "report_ok": report_ok,
    "report_content": report_content[:500]
}

# Write to temp file safely, then move
with open('/tmp/phylogenomic_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

mv /tmp/phylogenomic_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON written:"
cat /tmp/task_result.json
echo "=== Export complete ==="