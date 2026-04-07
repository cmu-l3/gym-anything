#!/bin/bash
echo "=== Exporting create_free_recall_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Use Python to analyze both the CSV and the XML structure of the experiment
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import subprocess
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/free_recall.psyexp"
CSV_FILE = "/home/ga/PsychoPyExperiments/word_list.csv"
RESULT_FILE = "/tmp/free_recall_result.json"
TARGET_WORDS = [
    "Apple", "Bridge", "Camera", "Doctor", "Engine", "Forest", "Guitar", 
    "Harbor", "Island", "Jungle", "Kettle", "Lemon", "Magnet", "Number", "Office"
]

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    "exp_file_exists": False,
    "csv_file_exists": False,
    "exp_file_modified": False,
    "csv_file_modified": False,
    # CSV Analysis
    "csv_word_count": 0,
    "csv_has_header": False,
    "csv_words_match": False,
    "csv_missing_words": [],
    # Experiment Analysis
    "is_valid_xml": False,
    "routines_found": [],
    "has_study_routine": False,
    "has_recall_routine": False,
    "has_textbox_component": False,
    "textbox_is_editable": False,
    "has_loop": False,
    "loop_file_ref": "",
    "loop_nreps": "",
    "study_in_loop": False,
    "recall_outside_loop": True # Default assumption, verified below
}

# Read metadata
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# Analyze CSV
if os.path.isfile(CSV_FILE):
    results["csv_file_exists"] = True
    if int(os.path.getmtime(CSV_FILE)) > results["task_start_time"]:
        results["csv_file_modified"] = True
    
    try:
        with open(CSV_FILE, 'r', newline='') as f:
            reader = csv.reader(f)
            rows = list(reader)
            
            if len(rows) > 0:
                header = [h.lower() for h in rows[0]]
                if "word" in header or "words" in header:
                    results["csv_has_header"] = True
                    # If header exists, skip row 0
                    data_rows = rows[1:]
                else:
                    data_rows = rows

                found_words = []
                for row in data_rows:
                    if row: found_words.append(row[0].strip())
                
                results["csv_word_count"] = len(found_words)
                
                # Check target words (case-insensitive check)
                found_lower = [w.lower() for w in found_words]
                missing = []
                for target in TARGET_WORDS:
                    if target.lower() not in found_lower:
                        missing.append(target)
                
                results["csv_missing_words"] = missing
                if not missing and len(found_words) >= 15:
                    results["csv_words_match"] = True
    except Exception as e:
        print(f"CSV Error: {e}")

# Analyze Experiment XML
if os.path.isfile(EXP_FILE):
    results["exp_file_exists"] = True
    if int(os.path.getmtime(EXP_FILE)) > results["task_start_time"]:
        results["exp_file_modified"] = True

    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True

        # Check Routines
        routines = root.find("Routines") or root.find(".//Routines")
        if routines is not None:
            for routine in routines:
                rname = routine.get("name", "")
                results["routines_found"].append(rname)
                
                if "study" in rname.lower():
                    results["has_study_routine"] = True
                
                if "recall" in rname.lower():
                    results["has_recall_routine"] = True
                    # Check for TextBox in recall routine
                    for comp in routine:
                        ctype = comp.tag
                        if "TextBox" in ctype: # Matches TextBoxComponent or TextBox2Component
                            results["has_textbox_component"] = True
                            # Check editable param
                            for param in comp:
                                pname = param.get("name")
                                pval = param.get("val")
                                if pname == "editable" and pval == "True":
                                    results["textbox_is_editable"] = True

        # Check Flow/Loops
        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            in_loop = False
            loop_name = ""
            
            for elem in flow:
                tag = elem.tag
                name = elem.get("name", "")
                
                if "LoopInitiator" in tag:
                    in_loop = True
                    results["has_loop"] = True
                    # Check loop params
                    for param in elem:
                        pname = param.get("name")
                        pval = param.get("val")
                        if pname == "conditionsFile":
                            results["loop_file_ref"] = pval
                        if pname == "nReps":
                            results["loop_nreps"] = pval
                
                elif "LoopTerminator" in tag:
                    in_loop = False
                
                elif "Routine" in tag:
                    # Check if study/recall are inside/outside loop
                    if "study" in name.lower() and in_loop:
                        results["study_in_loop"] = True
                    
                    if "recall" in name.lower() and in_loop:
                        results["recall_outside_loop"] = False # Oops, put recall in loop

    except Exception as e:
        print(f"XML Error: {e}")

# Save results
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)
os.chmod(RESULT_FILE, 0o666)
PYEOF

cat /tmp/free_recall_result.json
echo "=== Export complete ==="