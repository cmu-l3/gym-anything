#!/bin/bash
echo "=== Exporting Create Transcription Typing Task Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call to analyze both CSV and XML structure
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import xml.etree.ElementTree as ET

CSV_FILE = "/home/ga/PsychoPyExperiments/conditions/phrases.csv"
EXP_FILE = "/home/ga/PsychoPyExperiments/transcription_task.psyexp"
RESULT_FILE = "/tmp/task_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    # CSV Metrics
    "csv_exists": False,
    "csv_modified": False,
    "csv_header_valid": False,
    "csv_row_count": 0,
    "csv_phrases_found": 0,
    "csv_content_check": [],
    # Experiment Metrics
    "exp_exists": False,
    "exp_modified": False,
    "exp_valid_xml": False,
    "has_trial_routine": False,
    "has_text_stim": False,
    "text_uses_variable": False,
    "has_textbox": False,
    "textbox_editable": False,
    "has_loop": False,
    "loop_random": False,
    "loop_links_csv": False,
    "has_return_key_end": False
}

# 1. Read integrity data
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# 2. Analyze CSV
EXPECTED_PHRASES = [
    "my watch fell in the water",
    "prevailing wind from the east",
    "never too rich and never too thin",
    "breathing is difficult",
    "i can see the rings on saturn"
]

if os.path.isfile(CSV_FILE):
    results["csv_exists"] = True
    if os.path.getmtime(CSV_FILE) > results["task_start_time"]:
        results["csv_modified"] = True
    
    try:
        with open(CSV_FILE, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            headers = [h.strip() for h in (reader.fieldnames or [])]
            
            # Check header (case-insensitive)
            if any(h.lower() == 'target_phrase' for h in headers):
                results["csv_header_valid"] = True
            
            rows = list(reader)
            results["csv_row_count"] = len(rows)
            
            # Check content
            found_phrases = []
            col_name = next((h for h in headers if h.lower() == 'target_phrase'), None)
            
            if col_name:
                for row in rows:
                    val = row.get(col_name, "").strip().lower()
                    found_phrases.append(val)
            
            match_count = 0
            checks = []
            for expected in EXPECTED_PHRASES:
                # Approximate matching (allow missing punctuation or minor spacing diffs)
                # But task asks for exact phrases, so we'll be strict but case-insensitive
                clean_expected = expected.lower()
                matched = clean_expected in found_phrases
                checks.append({"phrase": expected, "found": matched})
                if matched:
                    match_count += 1
            
            results["csv_phrases_found"] = match_count
            results["csv_content_check"] = checks

    except Exception as e:
        print(f"CSV Error: {e}")

# 3. Analyze Experiment XML
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    if os.path.getmtime(EXP_FILE) > results["task_start_time"]:
        results["exp_modified"] = True
    
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["exp_valid_xml"] = True
        
        # Check Routines
        routines = root.findall(".//Routine")
        for routine in routines:
            if routine.get("name") == "trial":
                results["has_trial_routine"] = True
                
                # Check Components in trial
                for comp in routine:
                    comp_type = comp.tag
                    
                    # A. Text Component (Target)
                    if "TextComponent" in comp_type:
                        results["has_text_stim"] = True
                        for param in comp:
                            if param.get("name") == "text" and "$target_phrase" in param.get("val"):
                                results["text_uses_variable"] = True
                    
                    # B. TextBox Component (Input)
                    if "TextBoxComponent" in comp_type or "TextBox2" in str(comp_type):
                        results["has_textbox"] = True
                        for param in comp:
                            # Check editable (can be 'True', '1', or check box logic)
                            if param.get("name") == "editable" and param.get("val") in ["True", "1"]:
                                results["textbox_editable"] = True
                    
                    # C. Termination (Return key)
                    # Case 1: Keyboard component
                    if "KeyboardComponent" in comp_type:
                        for param in comp:
                            if param.get("name") == "allowedKeys" and "'return'" in param.get("val"):
                                results["has_return_key_end"] = True
                    
                    # Case 2: TextBox itself can end routine on commit (often return)
                    # We check if there's a param for ending routine
                    # (Simplified check: we look for Keyboard or generic end capability)

        # Check Flow / Loop
        loops = root.findall(".//LoopInitiator")
        for loop in loops:
            results["has_loop"] = True
            for param in loop:
                if param.get("name") == "loopType" and param.get("val") == "random":
                    results["loop_random"] = True
                if param.get("name") == "conditionsFile" and "phrases.csv" in param.get("val"):
                    results["loop_links_csv"] = True

    except Exception as e:
        print(f"XML Error: {e}")

# Write result
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="