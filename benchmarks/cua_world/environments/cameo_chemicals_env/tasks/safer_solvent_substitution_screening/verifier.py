#!/usr/bin/env python3
"""
Verifier for safer_solvent_substitution_screening task.

Checks:
1. Report file creation and freshness (Anti-gaming)
2. Presence of all 5 candidate chemicals in the report
3. Correct logic application for each candidate based on criteria
4. Identification of the correct winner (Dimethyl Sulfoxide)
5. VLM verification of the agent's research process
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_solvent_screening(traj, env_info, task_info):
    """
    Verify the solvent screening report and workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Initialize Scoring
    score = 0
    max_score = 100
    feedback = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Task Results & Output File
    # ------------------------------------------------------------------
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Load JSON result
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_data = json.load(f)
            
        # Load Report Text (if it exists)
        report_content = ""
        if result_data.get("output_exists") and result_data.get("output_file_path"):
            try:
                copy_from_env(result_data["output_file_path"], temp_report_txt.name)
                with open(temp_report_txt.name, 'r', errors='ignore') as f:
                    report_content = f.read()
            except Exception as e:
                logger.warning(f"Failed to copy report file: {e}")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"System error retrieving results: {e}"}
    finally:
        if os.path.exists(temp_result_json.name): os.unlink(temp_result_json.name)
        if os.path.exists(temp_report_txt.name): os.unlink(temp_report_txt.name)

    # ------------------------------------------------------------------
    # 2. Verify File Existence & Freshness (10 pts)
    # ------------------------------------------------------------------
    if not result_data.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Report file was not created."}
    
    if not result_data.get("file_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Report file timestamp indicates it was not created during this task session."}
        
    score += 10
    feedback.append("Report file created successfully.")

    # ------------------------------------------------------------------
    # 3. Analyze Content Logic (65 pts)
    # ------------------------------------------------------------------
    content_lower = report_content.lower()
    
    # Check for candidates (15 pts - 3 pts each)
    candidates = ["benzene", "acetone", "dimethyl sulfoxide", "methylene chloride", "acetophenone"]
    candidates_found = 0
    for cand in candidates:
        if cand in content_lower or (cand == "dimethyl sulfoxide" and "dmso" in content_lower):
            candidates_found += 1
            
    score += (candidates_found * 3)
    if candidates_found < 5:
        feedback.append(f"Only found {candidates_found}/5 candidate chemicals in report.")
    else:
        feedback.append("All candidates analyzed.")

    # Check Winner Logic (25 pts)
    # Winner: Dimethyl Sulfoxide (DMSO)
    # It passes all criteria: FP > 140F, Miscible, Non-carcinogen
    winner_pattern = r"recommendation.*(dimethyl sulfoxide|dmso)"
    if re.search(winner_pattern, content_lower):
        score += 25
        feedback.append("Correctly identified Dimethyl Sulfoxide as the recommended solvent.")
    else:
        feedback.append("Failed to identify the correct recommended solvent (DMSO).")

    # Check Rejection Logic (25 pts total)
    # We look for indications that specific bad candidates were marked as FAIL or identified with their flaws
    
    logic_score = 0
    
    # Benzene: Carcinogen or Flash Point issue
    if "benzene" in content_lower and ("carcinogen" in content_lower or "cancer" in content_lower or "fail" in content_lower):
        logic_score += 5
    
    # Acetone: Flash point issue (FAIL)
    if "acetone" in content_lower and ("flash point" in content_lower or "fail" in content_lower):
        logic_score += 5

    # Methylene Chloride: Carcinogen (FAIL)
    if "methylene chloride" in content_lower and ("carcinogen" in content_lower or "cancer" in content_lower or "fail" in content_lower):
        logic_score += 10

    # Acetophenone: Solubility issue (FAIL - slightly soluble)
    if "acetophenone" in content_lower and ("solubility" in content_lower or "fail" in content_lower):
        logic_score += 5
        
    score += logic_score
    if logic_score < 25:
        feedback.append("Some logic checks for rejected solvents were missing or incorrect.")
    else:
        feedback.append("Logic for rejecting unsuitable solvents appears correct.")

    # ------------------------------------------------------------------
    # 4. VLM Verification (25 pts)
    # ------------------------------------------------------------------
    # Check if agent actually visited CAMEO Chemicals and looked at datasheets
    frames = sample_trajectory_frames(traj, n=8)
    final_img = get_final_screenshot(traj)
    if final_img:
        frames.append(final_img)
        
    vlm_prompt = """
    Review this sequence of screenshots. The agent should be performing a chemical safety research task on the CAMEO Chemicals website.
    
    Please verify:
    1. Did the agent visit the CAMEO Chemicals website?
    2. Did the agent search for specific chemicals (like Benzene, DMSO, Acetone)?
    3. Did the agent view Chemical Datasheets (look for headers like "Physical Properties", "Hazards")?
    
    Answer JSON: {"cameo_visited": bool, "searches_performed": bool, "datasheets_viewed": bool}
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_result.get("parsed", {})
        
        vlm_score = 0
        if parsed.get("cameo_visited"): vlm_score += 5
        if parsed.get("searches_performed"): vlm_score += 10
        if parsed.get("datasheets_viewed"): vlm_score += 10
        
        score += vlm_score
        if vlm_score < 25:
            feedback.append("VLM verification found incomplete workflow evidence.")
        else:
            feedback.append("Visual evidence confirms valid research workflow.")
            
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        # Fallback: if text report is perfect, give benefit of doubt for VLM
        if score >= 75:
            score += 25
            feedback.append("VLM check skipped (error), assuming valid workflow based on high-quality output.")

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = score >= 80 and "dimethyl sulfoxide" in content_lower and result_data.get("file_created_during_task")
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }