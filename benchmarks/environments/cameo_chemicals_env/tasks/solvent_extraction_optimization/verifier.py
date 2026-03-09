#!/usr/bin/env python3
"""
Verifier for solvent_extraction_optimization task.

Verifies:
1. Report file creation and timing.
2. Content parsing for 5 solvent candidates.
3. Accuracy of extracted physical properties (SG, FP, BP).
4. Logic of final selection (Dichloromethane must be winner).
5. Identification of 1,2-Dichloroethane as flammable/rejected.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_solvent_line(line):
    """
    Parses a line like: "Dichloromethane: SG=1.33, FP=N/A, BP=104 F"
    Returns a dict with parsed values or None.
    """
    # Normalize
    line = line.strip()
    if not line or ':' not in line:
        return None
    
    name_part, data_part = line.split(':', 1)
    name = name_part.strip()
    
    data = {}
    
    # Extract SG
    sg_match = re.search(r'SG\s*=\s*([\d\.]+)', data_part, re.IGNORECASE)
    if sg_match:
        try:
            data['sg'] = float(sg_match.group(1))
        except ValueError:
            pass
            
    # Extract BP (look for numbers)
    bp_match = re.search(r'BP\s*=\s*([^\s,]+)', data_part, re.IGNORECASE)
    if bp_match:
        bp_str = bp_match.group(1)
        # Try to extract just the number
        num_match = re.search(r'([\d\.]+)', bp_str)
        if num_match:
            try:
                data['bp'] = float(num_match.group(1))
            except ValueError:
                pass
        data['bp_raw'] = bp_str

    # Extract FP
    fp_match = re.search(r'FP\s*=\s*([^,]+)', data_part, re.IGNORECASE)
    if fp_match:
        data['fp_raw'] = fp_match.group(1).strip()
        
    return name, data

def verify_solvent_selection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('output_file', '/home/ga/Documents/solvent_selection_report.txt')
    
    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Check File Existence & Timestamp (10 pts)
    if not result_meta.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if not result_meta.get('file_created_during_task'):
        feedback_parts.append("File exists but was not created/modified during task.")
    else:
        score += 10
        feedback_parts.append("Report file created.")

    # 3. Read Report Content
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(expected_output_path, temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read report content: {e}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
            
    # 4. Parse Content
    lines = report_content.splitlines()
    parsed_solvents = {}
    final_selection = ""
    
    for line in lines:
        if "Selected Solvent:" in line:
            final_selection = line.split(":", 1)[1].strip()
        else:
            res = parse_solvent_line(line)
            if res:
                parsed_solvents[res[0]] = res[1]

    # 5. Verify Data Completeness (25 pts)
    required_solvents = [
        "Dichloromethane", "Chloroform", "Carbon Tetrachloride", 
        "Trichloroethylene", "1,2-Dichloroethane"
    ]
    
    found_count = 0
    for req in required_solvents:
        # fuzzy match name
        found = False
        for parsed_name in parsed_solvents:
            if req.lower() in parsed_name.lower():
                found = True
                found_count += 1
                break
        if not found:
            feedback_parts.append(f"Missing data for {req}")

    if found_count == 5:
        score += 25
        feedback_parts.append("All 5 solvents listed.")
    else:
        score += (found_count * 5)
        feedback_parts.append(f"Found {found_count}/5 solvents.")

    # 6. Verify Data Accuracy (25 pts)
    # Check BP for Dichloromethane (should be ~104 F) and Chloroform (~142 F) as spot checks
    accuracy_points = 0
    
    # Helper to find solvent data
    def get_data(name_fragment):
        for name, data in parsed_solvents.items():
            if name_fragment.lower() in name.lower():
                return data
        return None

    dm_data = get_data("Dichloromethane") or get_data("Methylene")
    cf_data = get_data("Chloroform")
    
    if dm_data and 'bp' in dm_data:
        # Allow range 100-110 F or 38-42 C
        bp = dm_data['bp']
        if (100 <= bp <= 110) or (38 <= bp <= 42):
            accuracy_points += 12.5
        else:
            feedback_parts.append(f"Dichloromethane BP inaccurate ({bp})")
    
    if cf_data and 'bp' in cf_data:
        bp = cf_data['bp']
        if (138 <= bp <= 146) or (59 <= bp <= 63):
            accuracy_points += 12.5
        else:
            feedback_parts.append(f"Chloroform BP inaccurate ({bp})")
            
    score += accuracy_points
    if accuracy_points == 25:
        feedback_parts.append("Data values accurate.")

    # 7. Flammability Check (20 pts)
    # 1,2-Dichloroethane must have a listed FP (e.g., 56) or NOT be marked "N/A" / "Non-flam"
    dce_data = get_data("1,2-Dichloroethane")
    flam_detected = False
    
    if dce_data:
        fp_raw = dce_data.get('fp_raw', '').lower()
        # Look for indication of flammability (a number, or lack of "non-flam")
        # If it says "56", "13", "flammable", it passes
        if re.search(r'\d+', fp_raw) or "flam" in fp_raw:
             # But exclude "non-flammable"
             if "non" not in fp_raw and "not" not in fp_raw:
                 flam_detected = True
             # If it has a number like 56, it's definitely flammable regardless of text
             if re.search(r'\d+', fp_raw):
                 flam_detected = True
        
        if flam_detected:
            score += 20
            feedback_parts.append("1,2-Dichloroethane correctly identified as flammable/having FP.")
        else:
            feedback_parts.append(f"Failed to identify 1,2-Dichloroethane flammability (FP reported as: {fp_raw}).")

    # 8. Correct Selection (20 pts)
    correct_selection = False
    if "dichloromethane" in final_selection.lower() or "methylene chloride" in final_selection.lower():
        # Ensure 1,2-Dichloroethane wasn't also selected
        if "1,2-dichloroethane" not in final_selection.lower():
            correct_selection = True
    
    if correct_selection:
        score += 20
        feedback_parts.append("Correct solvent selected.")
    else:
        feedback_parts.append(f"Incorrect selection: '{final_selection}'")

    # Final Check
    passed = score >= 80 and correct_selection
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }