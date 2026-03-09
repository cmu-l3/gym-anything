#!/usr/bin/env python3
"""
Verifier for PID Detector Suitability Assessment task.
"""

import json
import os
import re
import tempfile
import logging

# Import VLM utilities if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_assessment_file(content):
    """
    Parses the student's output text file.
    Returns a dictionary keyed by chemical name (lowercase) containing 'ie' and 'detectable'.
    """
    results = {}
    current_chem = None
    
    lines = content.split('\n')
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        # Match Chemical Name
        name_match = re.match(r"Chemical:\s*(.+)", line, re.IGNORECASE)
        if name_match:
            current_chem = name_match.group(1).strip().lower()
            if current_chem not in results:
                results[current_chem] = {}
            continue

        if current_chem:
            # Match Ionization Energy
            ie_match = re.search(r"Ionization Energy:\s*([\d\.]+)", line, re.IGNORECASE)
            if ie_match:
                try:
                    results[current_chem]['ie'] = float(ie_match.group(1))
                except ValueError:
                    pass
            
            # Match Detectable status
            if "NOT DETECTABLE" in line.upper():
                results[current_chem]['detectable'] = False
            elif "DETECTABLE" in line.upper():
                results[current_chem]['detectable'] = True
                
    # Parse Summary counts if possible (optional but good for debugging)
    summary_match_det = re.search(r"Detectable.*:\s*(\d+)", content, re.IGNORECASE | re.DOTALL)
    summary_match_not = re.search(r"Not detectable.*:\s*(\d+)", content, re.IGNORECASE | re.DOTALL)
    
    summary = {
        "detectable": int(summary_match_det.group(1)) if summary_match_det else 0,
        "not_detectable": int(summary_match_not.group(1)) if summary_match_not else 0
    }
    
    return results, summary

def verify_pid_detector_suitability(traj, env_info, task_info):
    """
    Verifies the PID Suitability Assessment task.
    
    Scoring Breakdown (100 pts total):
    - 15 pts: File exists and created during task
    - 60 pts: Data accuracy (10 pts per chemical: 5 for IE value, 5 for classification)
    - 10 pts: Correct summary counts
    - 15 pts: VLM Verification (Evidence of CAMEO website usage)
    """
    
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    score = 0
    feedback = []
    
    # Load metadata
    metadata = task_info.get('metadata', {})
    chemicals_gt = metadata.get('chemicals', [])
    
    # 2. Retrieve Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            tf.seek(0)
            task_result = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

    # 3. Check File Existence and Anti-Gaming (15 pts)
    if not task_result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file pid_assessment.txt not found."}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task window."}
        
    score += 15
    feedback.append("File created successfully during task.")

    # 4. Retrieve and Parse Content
    content = ""
    with tempfile.NamedTemporaryFile(suffix='.txt') as tf:
        try:
            copy_from_env("/home/ga/Documents/pid_assessment.txt", tf.name)
            tf.seek(0)
            content = tf.read().decode('utf-8', errors='ignore')
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to read output file content: {str(e)}"}

    parsed_data, summary = parse_assessment_file(content)
    
    # 5. Verify Chemical Data (60 pts max)
    chem_score = 0
    chem_feedback = []
    
    for item in chemicals_gt:
        name = item['name']
        key = name.lower()
        expected_ie = item['expected_ie']
        expected_det = item['detectable']
        
        # Check if chemical present in output (fuzzy match by name inclusion)
        found_data = None
        for k, v in parsed_data.items():
            if key in k or k in key:
                found_data = v
                break
        
        if not found_data:
            chem_feedback.append(f"Missing: {name}")
            continue
            
        # Check Ionization Energy (Tolerance +/- 0.5 eV)
        actual_ie = found_data.get('ie')
        if actual_ie is not None and abs(actual_ie - expected_ie) <= 0.5:
            chem_score += 5
        else:
            chem_feedback.append(f"{name} IE mismatch (Exp: {expected_ie}, Got: {actual_ie})")

        # Check Classification
        actual_det = found_data.get('detectable')
        if actual_det == expected_det:
            chem_score += 5
        else:
            chem_feedback.append(f"{name} Classification mismatch")

    score += chem_score
    if not chem_feedback:
        feedback.append("All chemical data correct.")
    else:
        feedback.append(f"Data issues: {', '.join(chem_feedback)}")

    # 6. Verify Summary Counts (10 pts)
    # 3 Detectable, 3 Not Detectable
    if summary['detectable'] == 3 and summary['not_detectable'] == 3:
        score += 10
        feedback.append("Summary counts correct.")
    else:
        feedback.append(f"Summary incorrect (Det: {summary['detectable']}, Not: {summary['not_detectable']}).")

    # 7. VLM Verification (15 pts)
    # Check if the agent actually used CAMEO Chemicals
    vlm_score = 0
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=4)
        prompt = (
            "Review these screenshots of the agent's workflow. "
            "Did the agent visit the CAMEO Chemicals website (NOAA) and search for chemicals or view datasheets? "
            "Answer YES only if you clearly see the CAMEO Chemicals interface. "
            "Answer NO if the agent just wrote a file without looking up data."
        )
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("success") and "YES" in vlm_res.get("response", "").upper():
                vlm_score = 15
                feedback.append("VLM confirmed CAMEO usage.")
            else:
                feedback.append("VLM could not confirm CAMEO usage.")
        except Exception:
            # Fallback if VLM fails: give benefit of doubt if data is highly accurate
            if chem_score >= 50: 
                vlm_score = 15
                feedback.append("VLM skipped, implicit pass due to high data accuracy.")
    else:
        # No VLM available, award points if data is good
        if chem_score >= 50:
            vlm_score = 15
            feedback.append("VLM unavailable, passed based on data.")

    score += vlm_score

    # Final Pass/Fail
    # Threshold: 60 pts (Requires roughly 4/6 chemicals correct + file creation)
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }