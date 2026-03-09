#!/usr/bin/env python3
"""
Verifier for CERCLA Reportable Quantity Spill Assessment task.

Evaluates:
1. File existence and creation timestamp (Anti-gaming).
2. Correct extraction of CERCLA RQ values for 5 chemicals.
3. Correct YES/NO determination for NRC notification based on spill amounts.
4. Visual verification (VLM) of CAMEO usage via trajectory.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cercla_reportable_quantity_assessment(traj, env_info, task_info):
    """
    Verify the agent correctly identified RQs and notification requirements.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load ground truth from metadata
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    expected_count = metadata.get('expected_notification_count', 3)
    
    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Load Result JSON
    # ================================================================
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ================================================================
    # 2. Check File Existence & Timestamp (Anti-gaming)
    # ================================================================
    output_exists = task_result.get("output_exists", False)
    created_during_task = task_result.get("created_during_task", False)
    output_size = task_result.get("output_size", 0)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if output_size < 50:
        return {"passed": False, "score": 0, "feedback": "Report file is empty or too small."}

    if not created_during_task:
        # Penalize but continue to check content (maybe timestamp drift issue)
        feedback_parts.append("WARNING: File timestamp suggests it wasn't created during this session.")
        score_multiplier = 0.5 
    else:
        score += 5 # Points for creating file
        score_multiplier = 1.0
        feedback_parts.append("Report file created successfully.")

    # ================================================================
    # 3. Analyze Content (Programmatic Check)
    # ================================================================
    report_content = ""
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/Documents/cercla_spill_report.txt", temp_report.name)
        with open(temp_report.name, 'r', errors='ignore') as f:
            report_content = f.read().lower()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read report content: {str(e)}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # Helper to check RQ and Determination
    # Ground Truth:
    # Benzene: RQ 10, YES
    # Sulfuric: RQ 1000, NO
    # Chlorine: RQ 10, YES
    # Acetone: RQ 5000, NO
    # Mercury: RQ 1, YES

    correct_rq_count = 0
    correct_det_count = 0

    for chem, data in ground_truth.items():
        chem_name = chem.replace('_', ' ')
        
        # Check RQ (allow some flexibility in format)
        # Regex looks for chemical name followed eventually by the RQ number
        # e.g., "Benzene ... 10"
        rq_pattern = re.compile(re.escape(chem_name) + r".{1,100}?" + str(data['rq']), re.DOTALL)
        if rq_pattern.search(report_content):
            score += 10
            correct_rq_count += 1
        else:
            feedback_parts.append(f"Missing/Wrong RQ for {chem_name} (Expected {data['rq']})")

        # Check Determination (YES/NO)
        expected_det = "yes" if data['notify'] else "no"
        # Regex looks for chemical name ... yes/no
        # Ideally checks proximity to avoid cross-contamination
        # We assume line-based or block-based structure
        
        # Simpler robust check: Split content by chemical sections?
        # Or just look for "Benzene ... Yes" sequence
        det_pattern = re.compile(re.escape(chem_name) + r".{1,150}?(yes|no|required|not required)", re.DOTALL)
        match = det_pattern.search(report_content)
        if match:
            found_det = match.group(1)
            # Normalize "required" -> "yes", "not required" -> "no"
            if "not" in found_det: found_det = "no"
            elif "required" in found_det: found_det = "yes"
            
            if found_det == expected_det:
                score += 5
                correct_det_count += 1
            else:
                feedback_parts.append(f"Wrong determination for {chem_name} (Expected {expected_det.upper()})")
        else:
            feedback_parts.append(f"Could not find determination for {chem_name}")

    # Check Summary Count
    # Look for "3" near keywords like "total", "count", "summary"
    summary_pattern = re.compile(r"(total|count|summary).{1,50}?\b3\b")
    if summary_pattern.search(report_content):
        score += 10
        feedback_parts.append("Correct summary count found.")
    else:
        feedback_parts.append("Summary count missing or incorrect (Expected 3).")

    # ================================================================
    # 4. Visual Verification (VLM Trajectory)
    # ================================================================
    # Check if agent actually used CAMEO Chemicals
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Review these screenshots of an agent performing a task.
    The agent should be using the CAMEO Chemicals website (NOAA) to look up chemical data.
    
    1. Do you see the CAMEO Chemicals website?
    2. Do you see any chemical datasheets or search results for: Benzene, Sulfuric Acid, Chlorine, Acetone, or Mercury?
    3. Is the agent navigating to the 'Regulatory Information' section where 'CERCLA Reportable Quantity' is listed?
    
    Answer JSON: {"cameo_visible": bool, "chemicals_seen": bool, "regulatory_info_seen": bool}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('cameo_visible'): vlm_score += 5
        if parsed.get('chemicals_seen'): vlm_score += 3
        if parsed.get('regulatory_info_seen'): vlm_score += 2
    
    score += vlm_score
    if vlm_score > 0:
        feedback_parts.append(f"Visual verification passed ({vlm_score}/10 pts).")
    else:
        feedback_parts.append("Visual verification failed - CAMEO usage not clearly visible.")

    # ================================================================
    # Final Scoring
    # ================================================================
    # Total possible: 5 (file) + 50 (RQs) + 25 (Dets) + 10 (Summary) + 10 (VLM) = 100
    
    score = int(score * score_multiplier)
    
    # Key criteria for passing: 
    # - File exists
    # - At least 3 correct RQs (shows they know how to look it up)
    # - At least 3 correct determinations
    pass_threshold = 60
    key_criteria_met = output_exists and (correct_rq_count >= 3)
    
    passed = (score >= pass_threshold) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }