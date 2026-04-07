#!/usr/bin/env python3
"""
Verifier for Audit Rated Disabilities task.

Checks:
1. Output file exists and follows format.
2. Reported Patient exists in VistA.
3. Reported Disability matches the patient's record in VistA (Name + Percentage).
4. VLM verification of navigation.
"""

import json
import base64
import os
import logging
import difflib

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_rated_disabilities(traj, env_info, task_info):
    """
    Verify the agent correctly identified a patient's rated disabilities.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve files from environment
    import tempfile
    
    # Files to copy
    files = {
        'result': '/tmp/audit_disabilities_result.json',
        'gt': '/tmp/ground_truth_disabilities.json'
    }
    
    local_files = {}
    for name, path in files.items():
        tf = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tf.close()
        try:
            copy_from_env(path, tf.name)
            with open(tf.name, 'r') as f:
                local_files[name] = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load {name}: {e}")
            local_files[name] = {}
        finally:
            if os.path.exists(tf.name):
                os.unlink(tf.name)

    result_data = local_files.get('result', {})
    ground_truth = local_files.get('gt', {})

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence (10 pts)
    if result_data.get('output_exists', False):
        score += 10
        feedback_parts.append("Output file created")
        
        # Decode content
        try:
            content_b64 = result_data.get('file_content_base64', '')
            content = base64.b64decode(content_b64).decode('utf-8')
        except:
            content = ""
            feedback_parts.append("Failed to decode output file")
    else:
        feedback_parts.append("Output file missing")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Parse Content (10 pts for valid format)
    # Expected format:
    # Patient: NAME
    # Disability: NAME
    # Percentage: 50%
    
    parsed = {}
    lines = content.splitlines()
    for line in lines:
        if ':' in line:
            key, val = line.split(':', 1)
            parsed[key.strip().lower()] = val.strip()

    p_name = parsed.get('patient', '')
    p_dis = parsed.get('disability', '')
    p_pct = parsed.get('percentage', '').replace('%', '')

    if p_name and p_dis and p_pct:
        score += 10
        feedback_parts.append("Valid file format")
    else:
        feedback_parts.append("Invalid file format (missing fields)")
        # Continue to see if we can salvage partial credit? Probably not.
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. Verify Data against Ground Truth (60 pts total)
    
    # 4a. Find Patient (20 pts)
    # Fuzzy match patient name
    gt_patient_key = None
    
    # Direct match first
    if p_name in ground_truth:
        gt_patient_key = p_name
    else:
        # Try case insensitive
        for k in ground_truth.keys():
            if k.lower() == p_name.lower():
                gt_patient_key = k
                break
        # Try difflib for close match
        if not gt_patient_key:
            matches = difflib.get_close_matches(p_name, ground_truth.keys(), n=1, cutoff=0.8)
            if matches:
                gt_patient_key = matches[0]

    if gt_patient_key:
        score += 20
        feedback_parts.append(f"Patient '{gt_patient_key}' found in DB")
        
        # 4b. Check Disability & Percentage (40 pts)
        disabilities = ground_truth[gt_patient_key]
        
        # Look for match
        match_found = False
        disability_match = False
        percent_match = False
        
        for d in disabilities:
            # Check name (fuzzy)
            gt_d_name = d['disability']
            gt_d_pct = d['percent']
            
            # Simple substring or lower match
            name_ok = (p_dis.lower() in gt_d_name.lower()) or (gt_d_name.lower() in p_dis.lower())
            
            # Check percent (exact int conversion)
            try:
                pct_ok = int(float(p_pct)) == int(float(gt_d_pct))
            except:
                pct_ok = False
            
            if name_ok and pct_ok:
                match_found = True
                disability_match = True
                percent_match = True
                break
            elif name_ok:
                disability_match = True
        
        if match_found:
            score += 40
            feedback_parts.append(f"Disability '{p_dis}' and Percentage '{p_pct}%' correct")
        elif disability_match:
            score += 20
            feedback_parts.append(f"Disability '{p_dis}' correct, but percentage wrong")
        else:
            feedback_parts.append(f"Disability '{p_dis}' not found for patient")
            
    else:
        feedback_parts.append(f"Patient '{p_name}' not found in VistA database")

    # 5. VLM Verification (20 pts)
    # Check if they actually used the interface
    if query_vlm:
        screenshot_path = result_data.get('screenshot_path')
        if screenshot_path: # Note: This path is in container, we need to extract it or assume framework handles it
            # The framework's 'traj' object usually has frames.
            # We'll use the final frame from traj for VLM
            final_frame = traj.get('final_screenshot') or traj.get('last_frame')
            
            if final_frame:
                prompt = """
                Analyze this screenshot of the VistA/YDBGui interface.
                I am looking for evidence that the user is viewing Patient Disabilities.
                
                Look for:
                1. Reference to "^DPT" and Node ".372" or "RATED DISABILITIES".
                2. A list of disabilities or a percentage number.
                3. A patient name.
                
                Does this screen show patient disability data?
                """
                vlm_res = query_vlm(prompt, final_frame)
                if "yes" in vlm_res.lower() or "partial" in vlm_res.lower():
                    score += 20
                    feedback_parts.append("VLM confirms visual evidence")
                else:
                    feedback_parts.append("VLM did not see disability data")

    # Pass threshold
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }