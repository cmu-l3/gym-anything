#!/usr/bin/env python3
import json
import os
import re
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_derby_inputs(dump_str):
    """
    Parses the raw text output from the Derby SQL query in export_result.sh.
    Expected format lines: " 0.4             |Electricity, wind... "
    Returns a list of dicts: [{'amount': float, 'name': str}]
    """
    if not dump_str:
        return []
    
    inputs = []
    # Regex to find lines starting with a number, followed by pipe, then text
    # Derby output often has lots of whitespace
    pattern = re.compile(r'^\s*([0-9]+\.?[0-9]*)\s*\|\s*(.+)$', re.MULTILINE)
    
    for match in pattern.finditer(dump_str):
        try:
            amt = float(match.group(1))
            name = match.group(2).strip()
            inputs.append({'amount': amt, 'name': name})
        except ValueError:
            continue
    return inputs

def check_mix_compliance(inputs):
    """
    Verifies if the inputs match the 40/30/20/10 mix.
    Handles unit conversion (kWh vs MJ).
    Target:
      Wind: 40% (0.4 kWh OR ~1.44 MJ)
      Solar: 30% (0.3 kWh OR ~1.08 MJ)
      Nuclear: 20% (0.2 kWh OR ~0.72 MJ)
      Gas: 10% (0.1 kWh OR ~0.36 MJ)
    """
    # Categorize inputs based on name keywords
    mix = {'wind': 0.0, 'solar': 0.0, 'nuclear': 0.0, 'gas': 0.0}
    
    for i in inputs:
        name = i['name'].lower()
        amt = i['amount']
        
        # Identify category
        cat = None
        if 'wind' in name: cat = 'wind'
        elif 'solar' in name or 'photovoltaic' in name or 'pv' in name: cat = 'solar'
        elif 'nuclear' in name: cat = 'nuclear'
        elif 'gas' in name and 'natural' in name: cat = 'gas'
        
        # Add normalized amount (attempting to detect MJ vs kWh)
        # 1 kWh = 3.6 MJ. 
        # If the amount is > 1.0 for a fraction < 0.5, it's likely MJ.
        # Heuristic: If amount matches the MJ target within 10%, convert to kWh equivalent.
        if cat:
            # Targets in MJ
            target_mj = {'wind': 1.44, 'solar': 1.08, 'nuclear': 0.72, 'gas': 0.36}[cat]
            if abs(amt - target_mj) < 0.2:
                # It's likely MJ, convert to kWh logic (divide by 3.6)
                # Actually, simpler: Just normalize everything to "Share of 1 kWh"
                mix[cat] += amt / 3.6
            else:
                # Assume it's already kWh (or kg fuel which is harder, but let's assume electricity flow)
                mix[cat] += amt

    # Score based on proximity to 0.4, 0.3, 0.2, 0.1
    # Tolerances: +/- 0.05
    score = 0
    feedback = []
    
    # Wind (0.4)
    if 0.35 <= mix['wind'] <= 0.45: score += 15
    else: feedback.append(f"Wind share incorrect: found {mix['wind']:.2f} (expected 0.4)")
    
    # Solar (0.3)
    if 0.25 <= mix['solar'] <= 0.35: score += 15
    else: feedback.append(f"Solar share incorrect: found {mix['solar']:.2f} (expected 0.3)")
    
    # Nuclear (0.2)
    if 0.15 <= mix['nuclear'] <= 0.25: score += 15
    else: feedback.append(f"Nuclear share incorrect: found {mix['nuclear']:.2f} (expected 0.2)")
    
    # Gas (0.1)
    if 0.05 <= mix['gas'] <= 0.15: score += 15
    else: feedback.append(f"Gas share incorrect: found {mix['gas']:.2f} (expected 0.1)")
    
    return score, feedback

def verify_future_grid_mix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Check Result Export (20 pts)
    if result.get('result_csv_exists') and result.get('result_fresh'):
        score += 20
    elif result.get('result_csv_exists'):
        score += 10 # Old file
        feedback.append("Result file exists but timestamp is old")
    else:
        feedback.append("Result CSV not found")

    if result.get('doc_exists'):
        score += 5
    else:
        feedback.append("Documentation text file not found")

    # 3. Check Database Structure (Process Existence & Mix) (75 pts max here)
    if result.get('process_found'):
        score += 15
        inputs = parse_derby_inputs(result.get('inputs_dump', ''))
        
        if len(inputs) >= 4:
            mix_score, mix_feedback = check_mix_compliance(inputs)
            score += mix_score
            feedback.extend(mix_feedback)
        else:
            feedback.append(f"Process found but has too few inputs ({len(inputs)})")
    else:
        feedback.append("Process 'US Electricity Grid Mix 2035' not found in database")

    # 4. VLM Verification (Trajectory) - Secondary Check
    # Only if score is borderline or to confirm workflow
    frames = sample_trajectory_frames(traj, 5)
    final = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of an OpenLCA session.
    1. Did the user import a database? (Look for import dialogs)
    2. Did the user create a new process? (Look for 'New Process' dialog or form)
    3. Did the user calculate results? (Look for 'Calculation setup' or 'Analysis result' tabs)
    
    Return JSON: {"imported_db": bool, "created_process": bool, "calculated": bool}
    """
    
    vlm_data = {}
    try:
        vlm_resp = query_vlm(images=frames + [final], prompt=vlm_prompt)
        if vlm_resp and 'parsed' in vlm_resp:
            vlm_data = vlm_resp['parsed']
    except:
        pass

    # Bonus points for clear visual evidence if programmatic check missed something
    # or just to top up score
    if vlm_data.get('calculated', False):
        score = min(100, score + 5)

    # 5. Final Threshold
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": {"inputs_parsed": parse_derby_inputs(result.get('inputs_dump', ''))}
    }