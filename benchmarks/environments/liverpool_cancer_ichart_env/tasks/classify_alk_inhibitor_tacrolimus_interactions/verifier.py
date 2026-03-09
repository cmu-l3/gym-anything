#!/usr/bin/env python3
"""
Verifier for ALK Inhibitor Interaction Classification Task.
Verifies that the agent correctly identified the direction of interaction effects
for Crizotinib, Brigatinib, and Alectinib with Tacrolimus.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_alk_interactions(traj, env_info, task_info):
    """
    Verify the ALK inhibitor interaction audit task.
    
    Criteria:
    1. Report file exists (10 pts)
    2. All 3 drugs mentioned (15 pts)
    3. Crizotinib classified as INCREASE (Inhibition) (25 pts)
    4. Brigatinib classified as DECREASE (Induction) (25 pts)
    5. Alectinib classified as NEUTRAL/MINIMAL (15 pts)
    6. VLM: Evidence of opening details pages (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Files to fetch
    result_json_path = "/sdcard/task_result.json"
    report_file_path = "/sdcard/alk_transplant_audit.txt"
    
    # 1. Fetch JSON metadata
    task_data = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env(result_json_path, tmp.name)
            with open(tmp.name, 'r') as f:
                task_data = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load task result JSON: {e}")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # 2. Analyze File Content
    file_exists = task_data.get('file_exists', False)
    content_raw = task_data.get('content_raw', "").replace('|', '\n')
    
    if file_exists:
        score += 10
        feedback_parts.append("Report file created")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found"}

    # Parse lines
    lines = content_raw.strip().split('\n')
    drugs_found = []
    
    # Keywords for classification
    # Crizotinib (Inhibitor) -> Levels UP
    kw_increase = ["increase", "raise", "elevate", "higher", "up", "inhibit"]
    # Brigatinib (Inducer) -> Levels DOWN
    kw_decrease = ["decrease", "reduce", "lower", "drop", "down", "induce"]
    # Alectinib (Neutral) -> No change
    kw_neutral = ["no effect", "minimal", "none", "safe", "neutral", "green", "no interaction"]

    criz_score = 0
    brig_score = 0
    alec_score = 0
    
    for line in lines:
        line_lower = line.lower()
        
        if "crizotinib" in line_lower:
            drugs_found.append("Crizotinib")
            if any(k in line_lower for k in kw_increase):
                criz_score = 25
                feedback_parts.append("Crizotinib classified correctly (Increase)")
            elif any(k in line_lower for k in kw_decrease):
                feedback_parts.append("Crizotinib INCORRECT (marked as decrease)")
            elif any(k in line_lower for k in kw_neutral):
                feedback_parts.append("Crizotinib INCORRECT (marked as neutral)")
        
        elif "brigatinib" in line_lower:
            drugs_found.append("Brigatinib")
            if any(k in line_lower for k in kw_decrease):
                brig_score = 25
                feedback_parts.append("Brigatinib classified correctly (Decrease)")
            elif any(k in line_lower for k in kw_increase):
                feedback_parts.append("Brigatinib INCORRECT (marked as increase)")
        
        elif "alectinib" in line_lower:
            drugs_found.append("Alectinib")
            if any(k in line_lower for k in kw_neutral):
                alec_score = 15
                feedback_parts.append("Alectinib classified correctly (Neutral)")
            elif any(k in line_lower for k in (kw_increase + kw_decrease)):
                feedback_parts.append("Alectinib INCORRECT (marked as having effect)")

    score += criz_score + brig_score + alec_score
    
    # Check drug coverage
    unique_drugs = set(drugs_found)
    if len(unique_drugs) == 3:
        score += 15
        feedback_parts.append("All 3 drugs included")
    elif len(unique_drugs) > 0:
        score += 5 * len(unique_drugs)
        feedback_parts.append(f"Only {len(unique_drugs)}/3 drugs found")

    # 3. VLM Trajectory Verification
    # We want to see if they opened the details page (text heavy page) vs just the list
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    You are verifying a drug interaction checking task. The agent should have checked 3 different drugs.
    
    Look at these screenshots. 
    1. Do you see the "Interaction Details" screen? (It usually has a header "Interaction Details" or long text paragraphs describing mechanism).
    2. Do you see evidence of multiple different drugs being checked (Crizotinib, Brigatinib, Alectinib)?
    
    Respond in JSON:
    {
        "details_page_opened": true/false,
        "multiple_drugs_checked": true/false,
        "drugs_visible": ["list", "drug", "names"]
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_score = 0
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("details_page_opened"):
            vlm_score += 10
            feedback_parts.append("VLM confirmed details page was opened")
        else:
            feedback_parts.append("VLM: No evidence of reading interaction details")
    
    score += vlm_score

    # Final logic
    # Must have at least 2 correct classifications to pass
    correct_classifications = (criz_score > 0) + (brig_score > 0) + (alec_score > 0)
    passed = (score >= 75) and (correct_classifications >= 2)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }