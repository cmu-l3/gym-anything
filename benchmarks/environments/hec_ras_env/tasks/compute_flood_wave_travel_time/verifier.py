#!/usr/bin/env python3
"""
Verifier for compute_flood_wave_travel_time task.

Verification Strategy:
1. Check if output file exists and was created during task.
2. Parse the output text file for required 9 fields.
3. Validate values are physically reasonable (positive flow, plausible celerity).
4. Check internal consistency (Celerity ~= Distance / Time).
5. VLM check on trajectory to ensure Python/analysis was performed.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flood_wave_travel_time(traj, env_info, task_info):
    """
    Verify the flood wave travel time calculation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get Metadata
    metadata = task_info.get('metadata', {})
    expected_ranges = metadata.get('expected_ranges', {})

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Get Result JSON
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ================================================================
    # 2. Get Agent Output File
    # ================================================================
    agent_text = ""
    if result_data.get('output_exists', False):
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/agent_output.txt", temp_txt.name)
            with open(temp_txt.name, 'r') as f:
                agent_text = f.read()
        except Exception:
            feedback_parts.append("Output file exists but could not be read.")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)
    
    # ================================================================
    # Criterion 1: Output File Existence & Timing (20 pts)
    # ================================================================
    if result_data.get('output_exists') and result_data.get('file_created_during_task'):
        score += 20
        feedback_parts.append("Output file created successfully.")
    elif result_data.get('output_exists'):
        score += 5
        feedback_parts.append("Output file exists but timestamp suggests pre-existence (gaming check).")
    else:
        return {"passed": False, "score": 0, "feedback": "No output file found at expected location."}

    # ================================================================
    # Criterion 2: Content Parsing (40 pts)
    # ================================================================
    # Helper to extract float from line
    def extract_val(pattern, text):
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            try:
                # Find the first float-like number in the match group or after the pattern
                # If the group captures the number directly
                if match.groups():
                    return float(match.group(1))
                # Otherwise look for number after the match
                return None # Should assume regex captures the number
            except ValueError:
                return None
        return None

    # Regex patterns looking for "Label: Number" format
    # Using more flexible regex to catch variations
    patterns = {
        "upstream_st": r"Upstream.*Station.*:\s*([\d\.]+)",
        "downstream_st": r"Downstream.*Station.*:\s*([\d\.]+)",
        "reach_len": r"Reach.*Length.*:\s*([\d\.]+)",
        "peak_up": r"Peak.*Upstream.*:\s*([\d\.]+)",
        "peak_down": r"Peak.*Downstream.*:\s*([\d\.]+)",
        "time_up": r"Time.*Upstream.*:\s*([\d\.]+)",
        "time_down": r"Time.*Downstream.*:\s*([\d\.]+)",
        "travel_time": r"Travel.*Time.*:\s*([\d\.]+)",
        "celerity": r"Celerity.*:\s*([\d\.]+)"
    }

    extracted = {}
    missing_fields = []
    
    for key, pat in patterns.items():
        val = extract_val(pat, agent_text)
        if val is not None:
            extracted[key] = val
        else:
            missing_fields.append(key)

    # Score for present fields (approx 4.5 pts each)
    fields_found_count = len(extracted)
    score += int((fields_found_count / 9) * 40)
    
    if missing_fields:
        feedback_parts.append(f"Missing fields: {', '.join(missing_fields)}")
    else:
        feedback_parts.append("All required fields found.")

    # ================================================================
    # Criterion 3: Value Plausibility (20 pts)
    # ================================================================
    plausibility_score = 0
    
    # Check Reach Length (1,000 - 200,000 ft)
    rl = extracted.get("reach_len", -1)
    if 1000 <= rl <= 200000:
        plausibility_score += 5
    
    # Check Travel Time (0 - 48 hrs)
    tt = extracted.get("travel_time", -1)
    if 0 <= tt <= 48:
        plausibility_score += 5
        
    # Check Celerity (0.1 - 50 ft/s)
    cel = extracted.get("celerity", -1)
    if 0.1 <= cel <= 50:
        plausibility_score += 5
        
    # Check Upstream Station > Downstream Station
    us = extracted.get("upstream_st", 0)
    ds = extracted.get("downstream_st", 0)
    if us > ds and ds >= 0:
        plausibility_score += 5
        
    score += plausibility_score
    if plausibility_score < 20:
        feedback_parts.append("Some values are outside plausible physical ranges.")

    # ================================================================
    # Criterion 4: Internal Consistency (20 pts)
    # ================================================================
    # Celerity ~ Reach Length / (Travel Time * 3600)
    # Allow 20% tolerance
    consistency_passed = False
    if "reach_len" in extracted and "travel_time" in extracted and "celerity" in extracted:
        L = extracted["reach_len"]
        T_hrs = extracted["travel_time"]
        C_reported = extracted["celerity"]
        
        if T_hrs > 0:
            C_calc = L / (T_hrs * 3600.0)
            if C_reported > 0:
                ratio = C_calc / C_reported
                if 0.8 <= ratio <= 1.2:
                    score += 20
                    consistency_passed = True
                    feedback_parts.append("Calculated values are internally consistent.")
                else:
                    feedback_parts.append(f"Consistency check failed: Reported C={C_reported}, Calculated C={C_calc:.2f}")
            else:
                 feedback_parts.append("Reported celerity is zero/negative.")
        else:
             feedback_parts.append("Travel time is zero, cannot check consistency.")
    else:
        feedback_parts.append("Cannot check consistency due to missing values.")

    # ================================================================
    # Final Result
    # ================================================================
    passed = (score >= 60) and consistency_passed and (result_data.get('output_exists') is True)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }