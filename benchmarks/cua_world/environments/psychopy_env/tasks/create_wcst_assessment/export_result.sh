#!/bin/bash
echo "=== Exporting WCST Assessment Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# We use an embedded Python script to analyze both the CSV structure and the Python code content.
# This avoids dependencies on external tools and keeps the logic self-contained.

python3 << 'PYEOF'
import json
import os
import sys
import csv
import ast
import datetime
import subprocess

SCRIPT_FILE = "/home/ga/PsychoPyExperiments/wcst_task.py"
CSV_FILE = "/home/ga/PsychoPyExperiments/conditions/wcst_cards.csv"
RESULT_FILE = "/tmp/wcst_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    
    # CSV Metrics
    "csv_exists": False,
    "csv_modified": False,
    "csv_row_count": 0,
    "csv_columns_valid": False,
    "csv_complete_deck": False, # Has 64 unique combinations
    "csv_columns_found": [],
    
    # Script Metrics
    "script_exists": False,
    "script_modified": False,
    "script_syntax_valid": False,
    "script_line_count": 0,
    
    # Script Content Analysis (AST/String search)
    "imports_visual": False,
    "imports_event": False,
    "imports_data": False,
    "has_window": False,
    "has_mouse": False,
    "has_text_stim": False,
    "has_shape_stim": False,
    "has_feedback_logic": False, # "CORRECT" string or logic
    "has_rule_logic": False, # Checks for "color", "shape", "number" rules
    "saves_data": False, # Checks for experiment handler or csv writer
}

# Read task start time
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

# Read nonce
try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# --- Analyze CSV ---
if os.path.isfile(CSV_FILE):
    results["csv_exists"] = True
    if int(os.path.getmtime(CSV_FILE)) > results["task_start_time"]:
        results["csv_modified"] = True
    
    try:
        with open(CSV_FILE, 'r', newline='') as f:
            reader = csv.DictReader(f)
            headers = [h.strip().lower() for h in (reader.fieldnames or [])]
            results["csv_columns_found"] = headers
            
            # Check required columns
            required = {'cardid', 'color', 'shape', 'number'}
            if required.issubset(set(headers)):
                results["csv_columns_valid"] = True
            
            # Check rows and combinations
            rows = list(reader)
            results["csv_row_count"] = len(rows)
            
            if len(rows) == 64:
                combinations = set()
                valid_colors = {'red', 'green', 'yellow', 'blue'}
                valid_shapes = {'triangle', 'star', 'cross', 'circle'}
                valid_nums = {'1', '2', '3', '4'}
                
                valid_data = True
                for r in rows:
                    c = r.get('color', '').lower().strip()
                    s = r.get('shape', '').lower().strip()
                    n = str(r.get('number', '')).strip()
                    
                    if c not in valid_colors or s not in valid_shapes or n not in valid_nums:
                        valid_data = False
                    
                    combinations.add((c, s, n))
                
                if valid_data and len(combinations) == 64:
                    results["csv_complete_deck"] = True

    except Exception as e:
        print(f"CSV Check Error: {e}")

# --- Analyze Python Script ---
if os.path.isfile(SCRIPT_FILE):
    results["script_exists"] = True
    if int(os.path.getmtime(SCRIPT_FILE)) > results["task_start_time"]:
        results["script_modified"] = True
        
    try:
        with open(SCRIPT_FILE, 'r') as f:
            source = f.read()
        
        results["script_line_count"] = len(source.splitlines())
        
        # Syntax check
        try:
            tree = ast.parse(source)
            results["script_syntax_valid"] = True
            
            # AST Analysis
            for node in ast.walk(tree):
                # Imports
                if isinstance(node, (ast.Import, ast.ImportFrom)):
                    module = getattr(node, 'module', '') or ''
                    names = [n.name for n in node.names]
                    
                    if 'psychopy' in module or 'psychopy' in names:
                        pass # Generic check
                    
                    if 'visual' in module or 'visual' in names:
                        results["imports_visual"] = True
                    if 'event' in module or 'event' in names:
                        results["imports_event"] = True
                    if 'data' in module or 'data' in names:
                        results["imports_data"] = True
                
                # Function calls / Attributes
                if isinstance(node, ast.Call):
                    func = node.func
                    # Handle visual.Window()
                    if isinstance(func, ast.Attribute) and func.attr == 'Window':
                        results["has_window"] = True
                    # Handle event.Mouse()
                    if isinstance(func, ast.Attribute) and func.attr == 'Mouse':
                        results["has_mouse"] = True
                    # Stimuli
                    if isinstance(func, ast.Attribute) and func.attr in ['TextStim', 'ShapeStim', 'Rect', 'Circle']:
                        if func.attr == 'TextStim': results["has_text_stim"] = True
                        else: results["has_shape_stim"] = True
                    
            # String search for logic logic (easier than complex AST for logic flow)
            lower_source = source.lower()
            if "correct" in lower_source and ("incorrect" in lower_source or "wrong" in lower_source):
                results["has_feedback_logic"] = True
            
            # Rule switching keywords
            if "color" in lower_source and "shape" in lower_source and "number" in lower_source:
                # Check for some counter logic
                if "streak" in lower_source or "consecutive" in lower_source or "count" in lower_source:
                    results["has_rule_logic"] = True
            
            # Data saving
            if "experimenthandler" in lower_source or "csv" in lower_source or ".save" in lower_source or "write" in lower_source:
                results["saves_data"] = True

        except SyntaxError:
            results["script_syntax_valid"] = False

    except Exception as e:
        print(f"Script Check Error: {e}")

# Write results
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/wcst_result.json
echo "=== Export complete ==="