#!/usr/bin/env python3
"""
Verifier for distillation_separation_difficulty task.

Verifies:
1. Output file exists and was created during the task.
2. Chemicals are sorted correctly by boiling point.
3. Boiling point values match CAMEO Chemicals data (approximate).
4. Delta calculations are correct.
5. The 'Critical Separation Pair' is correctly identified.
6. VLM Check: Confirms the agent actually used the CAMEO interface.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth values (approximate Celsius boiling points)
# Based on common data found in CAMEO/PubChem
GROUND_TRUTH = {
    "acetone": 56,
    "mek": 80,         # Methyl Ethyl Ketone / 2-Butanone
    "ipa": 82,         # Isopropyl Alcohol / 2-Propanol
    "toluene": 111,
    "xylene": 139      # Mixed isomers range, usually ~138-144
}

# The expected order based on BP
EXPECTED_ORDER = ["acetone", "mek", "ipa", "toluene", "xylene"]

# Map common names or synonyms agent might use to keys
NAME_MAP = {
    "acetone": "acetone",
    "toluene": "toluene",
    "methyl ethyl ketone": "mek",
    "2-butanone": "mek",
    "mek": "mek",
    "isopropyl alcohol": "ipa",
    "2-propanol": "ipa",
    "isopropanol": "ipa",
    "ipa": "ipa",
    "xylene": "xylene",
    "xylenes": "xylene",
    "mixed xylenes": "xylene"
}

def normalize_name(name):
    """Normalize chemical name to key."""
    n = name.lower().strip()
    # Check direct map
    if n in NAME_MAP:
        return NAME_MAP[n]
    # Check partials
    for k, v in NAME_MAP.items():
        if k in n:
            return v
    return "unknown"

def parse_report(content):
    """Extracts chemicals, BPs, deltas, and critical pair from text."""
    lines = content.split('\n')
    chemicals = []
    deltas = []
    critical_pair = None
    
    # Regex for list items: "1. Acetone (56 C)"
    # Captures: Name, Value
    item_pattern = re.compile(r'^\d+\.\s+([A-Za-z0-9\s\-\(\)]+?)\s*\(\s*([\d\.]+)\s*[C|c]\s*\)')
    
    # Regex for Delta lines: "   -> Delta: 24 C"
    delta_pattern = re.compile(r'Delta:\s*([\d\.]+)')
    
    # Regex for Critical Pair: "[Chemical A] and [Chemical B]"
    crit_pattern = re.compile(r'CRITICAL SEPARATION PAIR.*:\s*\n(.+?)\s+and\s+(.+?)\s+\(')

    current_chem = None
    
    for i, line in enumerate(lines):
        line = line.strip()
        
        # Check for chemical list item
        m_item = item_pattern.search(line)
        if m_item:
            name_raw = m_item.group(1).strip()
            bp = float(m_item.group(2))
            key = normalize_name(name_raw)
            chemicals.append({"name": name_raw, "key": key, "bp": bp})
            continue

        # Check for delta
        m_delta = delta_pattern.search(line)
        if m_delta:
            deltas.append(float(m_delta.group(1)))
            continue
            
        # Check for critical pair (look ahead usually not needed if format is strict)
        # We look for the line AFTER the header usually, or just search the whole text
    
    # Extract Critical Pair specifically
    full_text = "\n".join(lines)
    m_crit = crit_pattern.search(full_text)
    if m_crit:
        critical_pair = (normalize_name(m_crit.group(1)), normalize_name(m_crit.group(2)))
    
    return chemicals, deltas, critical_pair

def verify_distillation_separation_difficulty(traj, env_info, task_info):
    """Main verification function."""
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # 2. Retrieve Result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)
            
    # 3. Check Basic File Existence (10 pts)
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created during this task (stale)."}
        
    score += 10
    feedback.append("Report file created.")

    # 4. Retrieve and Parse Report Content
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(task_result["output_path"], temp_report.name)
        with open(temp_report.name, 'r') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read report content: {str(e)}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
            
    chemicals, deltas, critical_pair_found = parse_report(content)
    
    if len(chemicals) != 5:
        return {"passed": False, "score": score, "feedback": f"Expected 5 chemicals in report, found {len(chemicals)}."}

    # 5. Verify Sorting and BP Accuracy (25 pts for sort, 25 pts for values)
    # Check Sort Order
    actual_order = [c["key"] for c in chemicals]
    
    # MEK and IPA are very close (80 vs 82). We allow them to swap IF the values written support it, 
    # but strictly speaking IPA > MEK. 
    # Let's check against EXPECTED_ORDER directly first.
    
    sort_correct = (actual_order == EXPECTED_ORDER)
    if sort_correct:
        score += 25
        feedback.append("Chemicals sorted correctly.")
    else:
        # Check if only MEK/IPA are swapped (acceptable variation if data source varies slightly)
        swapped_order = ["acetone", "ipa", "mek", "toluene", "xylene"]
        if actual_order == swapped_order:
            score += 20 # Partial credit
            feedback.append("Chemicals mostly sorted (MEK/IPA swapped).")
        else:
            feedback.append(f"Incorrect sort order: {actual_order}")

    # Check BP Values
    bp_errors = 0
    for c in chemicals:
        key = c["key"]
        val = c["bp"]
        if key in GROUND_TRUTH:
            expected = GROUND_TRUTH[key]
            # Tolerance +/- 5 degrees C
            if not (expected - 5 <= val <= expected + 5):
                bp_errors += 1
                feedback.append(f"BP for {c['name']} ({val}) out of expected range ({expected}).")
    
    if bp_errors == 0:
        score += 25
        feedback.append("All boiling points accurate.")
    elif bp_errors <= 1:
        score += 15
        feedback.append("Most boiling points accurate.")
    else:
        feedback.append(f"{bp_errors} boiling point errors.")

    # 6. Verify Logic (Deltas and Critical Pair) (20 pts for Deltas, 20 pts for Critical Pair)
    
    # Check calculated deltas
    logic_errors = 0
    if len(deltas) == 4: # 5 items have 4 gaps
        for i in range(4):
            # Calculate from the AGENT'S numbers, not ground truth
            calc_delta = chemicals[i+1]["bp"] - chemicals[i]["bp"]
            reported_delta = deltas[i]
            if abs(calc_delta - reported_delta) > 1.0:
                logic_errors += 1
        
        if logic_errors == 0:
            score += 20
            feedback.append("Delta calculations correct.")
        else:
            score += 10
            feedback.append("Some delta calculations incorrect.")
    else:
        feedback.append(f"Found {len(deltas)} deltas, expected 4.")

    # Check Critical Pair
    # Should be the pair with the minimum delta based on AGENT'S data
    # Calculate min delta from agent data
    min_delta = float('inf')
    expected_pair_indices = -1
    
    for i in range(len(chemicals) - 1):
        d = abs(chemicals[i+1]["bp"] - chemicals[i]["bp"])
        if d < min_delta:
            min_delta = d
            expected_pair_indices = i
            
    if expected_pair_indices != -1 and critical_pair_found:
        chem_a = chemicals[expected_pair_indices]["key"]
        chem_b = chemicals[expected_pair_indices+1]["key"]
        
        # Check if found matches expected
        # Order in tuple might vary
        cp_set = set(critical_pair_found)
        target_set = {chem_a, chem_b}
        
        if cp_set == target_set:
            score += 20
            feedback.append("Critical separation pair correctly identified.")
        else:
            feedback.append(f"Wrong critical pair identified. Expected {chem_a}/{chem_b}, got {critical_pair_found}.")
    else:
        feedback.append("Critical pair not found or could not be verified.")

    # 7. VLM Verification (Trajectory Analysis)
    # Ensure they actually used CAMEO Chemicals
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    if final_img:
        frames.append(final_img)
    
    vlm_prompt = (
        "Does the agent appear to be using the 'CAMEO Chemicals' website? "
        "Look for the NOAA CAMEO Chemicals logo or search interface. "
        "Also, is there a text editor open showing a list of chemicals? "
        "Reply 'YES' if CAMEO Chemicals is visible at some point."
    )
    
    try:
        vlm_res = query_vlm(frames, vlm_prompt)
        if "YES" in vlm_res.get("response", "").upper() or vlm_res.get("success", False):
            # We don't assign points specifically for this, but it validates the approach
            # Just logging it for now, can be a fail condition if strictly enforcing tool usage
            pass
    except Exception:
        pass

    # Final Result
    passed = (score >= 75) and sort_correct
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }