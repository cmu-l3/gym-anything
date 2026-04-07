#!/bin/bash
echo "=== Exporting Masked Priming Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Run analysis script
python3 << 'PYEOF'
import json
import os
import csv
import sys
import xml.etree.ElementTree as ET
import datetime

EXP_FILE = "/home/ga/PsychoPyExperiments/masked_priming/masked_priming.psyexp"
CSV_FILE = "/home/ga/PsychoPyExperiments/masked_priming/stimuli.csv"
RESULT_FILE = "/tmp/masked_priming_result.json"

results = {
    "exp_exists": False,
    "csv_exists": False,
    "csv_valid": False,
    "csv_rows": 0,
    "csv_columns": [],
    "has_related_condition": False,
    "has_nonword_condition": False,
    "prime_component_found": False,
    "prime_duration_val": None,
    "prime_duration_type": None,
    "mask_component_found": False,
    "target_component_found": False,
    "keyboard_correct_ans": False,
    "loop_found": False,
    "timestamp": datetime.datetime.now().isoformat()
}

# Check CSV
if os.path.exists(CSV_FILE):
    results["csv_exists"] = True
    try:
        with open(CSV_FILE, 'r') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                results["csv_columns"] = [c.strip() for c in reader.fieldnames]
                rows = list(reader)
                results["csv_rows"] = len(rows)
                
                # Check for required content types
                for row in rows:
                    cond = row.get('condition', '').lower()
                    if 'related' in cond:
                        results["has_related_condition"] = True
                    if 'nonword' in cond:
                        results["has_nonword_condition"] = True
                
                # Check required columns
                req_cols = {'prime', 'target', 'condition', 'corrAns'}
                # normalize columns to handle potential whitespace or case
                found_cols = {c.strip() for c in results["csv_columns"]}
                # allow case-insensitive match for corrAns
                has_corrans = any(c.lower() == 'corrans' for c in found_cols)
                if 'prime' in found_cols and 'target' in found_cols and 'condition' in found_cols and has_corrans:
                    results["csv_valid"] = True
    except Exception as e:
        results["csv_error"] = str(e)

# Check Experiment XML
if os.path.exists(EXP_FILE):
    results["exp_exists"] = True
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        
        # Analyze Routines
        routines = root.findall(".//Routine")
        for routine in routines:
            # Look for components
            for comp in routine:
                # Get component params
                params = {p.get('name'): p.get('val') for p in comp.findall('Param')}
                
                # Check if this is the Prime text component
                # Identifiers: name="prime" OR text="$prime"
                text_val = params.get('text', '')
                name_val = params.get('name', '')
                
                if name_val == 'prime' or '$prime' in text_val:
                    results["prime_component_found"] = True
                    results["prime_duration_val"] = params.get('stopVal')
                    results["prime_duration_type"] = params.get('stopType')
                
                # Check for Mask
                if '#######' in text_val or name_val == 'mask':
                    results["mask_component_found"] = True
                    
                # Check for Target
                if '$target' in text_val or name_val == 'target':
                    results["target_component_found"] = True
                    
                # Check Response
                if comp.tag == 'KeyboardComponent' or params.get('type') == 'Keyboard':
                    if '$corrAns' in params.get('correctAns', '') or '$corrAns' in params.get('storeCorrect', ''):
                        results["keyboard_correct_ans"] = True

        # Check for Loop
        loops = root.findall(".//LoopInitiator")
        if loops:
            results["loop_found"] = True
            
    except Exception as e:
        results["exp_error"] = str(e)

with open(RESULT_FILE, 'w') as f:
    json.dump(results, f, indent=2)
    
os.chmod(RESULT_FILE, 0o666)
PYEOF

echo "Export complete."