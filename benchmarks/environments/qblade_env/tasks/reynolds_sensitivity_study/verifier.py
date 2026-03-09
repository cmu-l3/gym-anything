#!/usr/bin/env python3
import json
import os
import re
import base64
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_content(content):
    """
    Parses the student report to extract metrics for different Reynolds numbers.
    Expected format is loosely defined, so we use regex to find blocks associated with Re.
    """
    # Normalize content
    text = content.lower()
    
    # Structure to hold results
    data = {
        500000: {},
        1000000: {},
        3000000: {}
    }
    
    # Heuristic: split by lines and look for context
    # Regex to find numbers close to keywords
    
    # We look for sections. A simple approach is to look for "Re" or numbers like "500000"
    # followed by metrics.
    
    # Let's try to extract blocks defined by Re headers
    # e.g., "Re = 500000 ... metrics ... Re = 1000000"
    
    # Find positions of Re headers
    re_map = {
        500000: ["500000", "5e5", "500k"],
        1000000: ["1000000", "1e6", "1m"],
        3000000: ["3000000", "3e6", "3m"]
    }
    
    current_re = None
    lines = text.split('\n')
    
    for line in lines:
        # Detect Reynolds header
        for re_val, keywords in re_map.items():
            for kw in keywords:
                if kw in line and ("re" in line or "reynolds" in line):
                    current_re = re_val
                    break
        
        if current_re is None:
            continue
            
        # extract metrics from line
        # Look for cl max
        if "cl" in line and "max" in line:
            val = extract_value(line)
            if val is not None: data[current_re]['cl_max'] = val
            
        # Look for cd min
        if "cd" in line and "min" in line:
            val = extract_value(line)
            if val is not None: data[current_re]['cd_min'] = val
            
        # Look for stall angle (often contains 'angle' or 'alpha' or 'deg')
        if ("stall" in line) or ("angle" in line and "cl" in line):
            # Distinguish from just 'angle of attack' label
            val = extract_value(line)
            if val is not None: data[current_re]['stall_angle'] = val

        # Look for L/D max
        if ("l/d" in line) or ("lift" in line and "drag" in line and "ratio" in line):
            val = extract_value(line)
            if val is not None: data[current_re]['ld_max'] = val

    return data

def extract_value(line):
    # Extracts the last float in a line usually, or looks for number after '=' or ':'
    # Regex for float: -?\d+(\.\d+)?
    matches = re.findall(r'-?\d+\.?\d*', line)
    if matches:
        # Filter out the Reynolds number itself if it appears in the line (heuristic)
        cleaned = [float(x) for x in matches if float(x) < 400000] # Metrics are usually small
        if cleaned:
            return cleaned[-1] # Assume the value is at the end "Cl_max = 1.2"
    return None

def verify_reynolds_study(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load results from container
    import tempfile
    temp_json = tempfile.NamedTemporaryFile(delete=False)
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result file: {e}"}
    finally:
        os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 2. Check Report Existence (10 pts)
    if result.get("report_exists") and result.get("report_created_during_task"):
        score += 10
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing or stale.")
        return {"passed": False, "score": 0, "feedback": "Report file not found."}

    # 3. Parse Content and Check Metrics (40 pts)
    content_b64 = result.get("report_content_base64", "")
    try:
        content_text = base64.b64decode(content_b64).decode('utf-8')
    except:
        content_text = ""
        
    data = parse_report_content(content_text)
    
    metrics_score = 0
    re_found = 0
    
    # Check each Re
    for re_val in [500000, 1000000, 3000000]:
        metrics = data.get(re_val, {})
        if not metrics:
            continue
        re_found += 1
        
        # Check if we have at least 3 of 4 metrics
        if len(metrics) >= 3:
            metrics_score += 10
        elif len(metrics) >= 1:
            metrics_score += 5
            
        # Value Plausibility Check
        # S809 approx: Cl_max ~0.9-1.1, Cd_min ~0.004-0.01, L/D ~50-120
        if 'cl_max' in metrics and 0.5 < metrics['cl_max'] < 1.8:
            metrics_score += 2
        if 'cd_min' in metrics and 0.001 < metrics['cd_min'] < 0.03:
            metrics_score += 2
            
    score += min(40, metrics_score)
    if re_found < 3:
        feedback.append(f"Only found data for {re_found}/3 Reynolds numbers.")
    else:
        feedback.append("Data found for all Reynolds numbers.")

    # 4. Physical Trend Check (20 pts)
    # Cd_min should decrease with Re (or stay very similar)
    # L/D max should increase with Re
    trend_score = 0
    try:
        cd_500 = data[500000].get('cd_min', 999)
        cd_3m = data[3000000].get('cd_min', 0)
        
        ld_500 = data[500000].get('ld_max', 0)
        ld_3m = data[3000000].get('ld_max', 999)
        
        if cd_3m < cd_500 and cd_3m > 0:
            trend_score += 10
            feedback.append("Correct Trend: Drag decreases with Re.")
        
        if ld_3m > ld_500 and ld_500 > 0:
            trend_score += 10
            feedback.append("Correct Trend: Efficiency (L/D) increases with Re.")
    except:
        pass
    score += trend_score

    # 5. Project File Check (10 pts)
    if result.get("project_exists") and result.get("project_size_bytes", 0) > 5000:
        score += 10
        feedback.append("Valid project file saved.")
    else:
        feedback.append("Project file missing or empty.")

    # 6. VLM Verification (20 pts)
    # Sample frames to see if XFoil Graphs were visible
    frames = sample_trajectory_frames(traj, 5)
    vlm_prompt = (
        "These are screenshots of QBlade. Verify the following:\n"
        "1. Is the 'XFoil Direct Analysis' or 'Airfoil Design' module visible?\n"
        "2. Are there Polar plots (graphs with curves) visible?\n"
        "3. Did the user appear to change Reynolds number settings (look for 'Re', 'Viscous', or number inputs)?\n"
        "Answer with a confidence score (0-10) and explanation."
    )
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    # Simple logic on VLM output (in production would parse JSON)
    # Assuming VLM returns text, we scan for keywords or rely on a structured VLM wrapper
    # Here assuming a mock positive for template purposes
    if "yes" in str(vlm_result).lower() or "visible" in str(vlm_result).lower():
         score += 20
         feedback.append("Visual verification passed.")
    else:
         # Fallback if VLM is uncertain but result files are perfect
         if score >= 60:
             score += 10 # Benefit of doubt
             feedback.append("Visual verification inconclusive, but files look good.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }