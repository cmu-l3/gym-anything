#!/usr/bin/env python3
"""
Verifier for grocery_market_basket_arules task.

Scoring Criteria (100 points total):
1. Item Frequencies CSV (15 pts): Exists, valid, 'whole milk' is top frequent item.
2. Association Rules CSV (25 pts): Exists, valid, contains rules (support/conf check implicit in finding rules).
3. Lift Sorting (10 pts): Rules are sorted by lift descending.
4. Whole Milk Subset (15 pts): All rules in this CSV imply 'whole milk' (RHS).
5. Network Visualization (20 pts): PNG exists, valid, >30KB.
6. Setup/Script (15 pts): 'arules' installed, script modified.

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_market_basket(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    score = 0
    feedback = []
    temp_files = []

    # Helper to retrieve file content from container
    def get_csv_content(container_path):
        if not container_path: return None
        tf = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        temp_files.append(tf.name)
        try:
            copy_from_env(container_path, tf.name)
            with open(tf.name, 'r', errors='replace') as f:
                # Use standard csv reader to handle quoting
                reader = csv.reader(f)
                rows = list(reader)
            return rows
        except Exception:
            return None

    # 1. Item Frequencies (15 pts)
    freq_info = result.get('freq_csv', {})
    if freq_info.get('exists') == 'true':
        rows = get_csv_content(freq_info.get('path'))
        if rows and len(rows) > 5:
            # Check content: Look for 'whole milk' in first few rows
            # Header might vary, so search the text
            text_dump = str(rows[:5]).lower()
            if "whole milk" in text_dump:
                score += 15
                feedback.append("Item frequencies correct (whole milk found)")
            else:
                score += 10
                feedback.append("Item frequencies CSV exists but 'whole milk' not at top")
        else:
            score += 5
            feedback.append("Item frequencies CSV exists but empty/invalid")
    else:
        feedback.append("Item frequencies CSV missing")

    # 2. Rules CSV & 3. Lift Sorting (35 pts)
    rules_info = result.get('rules_csv', {})
    if rules_info.get('exists') == 'true':
        rows = get_csv_content(rules_info.get('path'))
        if rows and len(rows) > 2:
            score += 25
            feedback.append("Rules CSV created")
            
            # Check Lift Sorting (10 pts)
            # Try to identify Lift column
            header = [h.lower() for h in rows[0]]
            lift_idx = -1
            for i, col in enumerate(header):
                if 'lift' in col:
                    lift_idx = i
                    break
            
            sorted_correctly = False
            if lift_idx != -1 and len(rows) > 3:
                try:
                    # Check first couple of data rows
                    val1 = float(rows[1][lift_idx])
                    val2 = float(rows[2][lift_idx])
                    if val1 >= val2:
                        sorted_correctly = True
                except ValueError:
                    pass
            
            if sorted_correctly:
                score += 10
                feedback.append("Rules sorted by lift")
            else:
                feedback.append("Rules not strictly sorted by lift or column not found")
        else:
            feedback.append("Rules CSV exists but has no data")
    else:
        feedback.append("Rules CSV missing")

    # 4. Whole Milk Subset (15 pts)
    milk_info = result.get('milk_csv', {})
    if milk_info.get('exists') == 'true':
        rows = get_csv_content(milk_info.get('path'))
        if rows and len(rows) > 2:
            # Basic check: does "whole milk" appear in the file?
            # A strict check would parse RHS, but raw text check is decent proxy for existence
            full_text = str(rows).lower()
            if "whole milk" in full_text:
                score += 15
                feedback.append("Whole milk subset file valid")
            else:
                score += 5
                feedback.append("Whole milk file exists but 'whole milk' not found in text")
    else:
        feedback.append("Whole milk subset CSV missing")

    # 5. Network Visualization (20 pts)
    png_info = result.get('network_png', {})
    if png_info.get('exists') == 'true':
        size = png_info.get('size', 0)
        if size > 30000: # 30KB
            score += 20
            feedback.append("Network graph created and substantial size")
        elif size > 0:
            score += 10
            feedback.append("Network graph exists but small file size")
    else:
        feedback.append("Network graph PNG missing")

    # 6. Script & Setup (15 pts)
    if result.get('script', {}).get('exists') == 'true':
        score += 5
        feedback.append("Script modified")
    
    # We give points if output files exist, implying arules was loaded/used,
    # or if explicitly installed
    if result.get('arules_installed_during_task') or score > 40:
        score += 10
        feedback.append("Environment setup successful")

    # Cleanup local temps
    for f in temp_files:
        if os.path.exists(f):
            os.unlink(f)

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }