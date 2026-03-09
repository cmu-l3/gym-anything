#!/usr/bin/env python3
"""
Verifier for relate_tables_outbreak task.

Verifies:
1. Agent generated an HTML output file.
2. File contains results from FREQ and TABLES commands.
3. Correct counts and statistics are present (indicating successful data join).
4. VLM verifies workflow progression.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_relate_tables_outbreak(traj, env_info, task_info):
    """
    Verify the Epi Info 7 data linking and analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('output_path', r"C:\Users\Docker\Documents\SalmonellaOutbreak_Output.html")
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Analysis of Exported Result (Programmatic)
    # ---------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        # Copy result JSON from container
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check output file existence (10 pts)
    if result_data.get('output_exists'):
        score += 10
        feedback_parts.append("Output file created.")
    else:
        feedback_parts.append("Output file missing.")
        
    # Check if created during task (5 pts)
    if result_data.get('file_created_during_task'):
        score += 5
        feedback_parts.append("File created during task session.")
    elif result_data.get('output_exists'):
        feedback_parts.append("File timestamp indicates stale data.")

    # Check Analysis Content (Max 55 pts)
    # FREQ LabResult (15 pts)
    if result_data.get('freq_lab_result_found'):
        score += 15
        feedback_parts.append("LabResult frequency analysis found.")
    
    # FREQ AgeGroup (10 pts)
    if result_data.get('freq_age_group_found'):
        score += 10
        feedback_parts.append("AgeGroup frequency analysis found.")

    # TABLES (30 pts total)
    tables_found = 0
    if result_data.get('table_chicken_found'): tables_found += 1
    if result_data.get('table_eggs_found'): tables_found += 1
    if result_data.get('table_sex_found'): tables_found += 1
    
    score += (tables_found * 10)
    if tables_found > 0:
        feedback_parts.append(f"Found {tables_found}/3 Cross-Tabulations.")
        
    # Check correct record count (55) - implies successful join (10 pts)
    if result_data.get('record_count_found') == 55:
        score += 10
        feedback_parts.append("Correct record count (55) verified.")
    else:
        feedback_parts.append("Record count mismatch or not found.")

    # ---------------------------------------------------------
    # 2. VLM Verification (Trajectory)
    # ---------------------------------------------------------
    # Use VLM to verify the workflow steps that are hard to check via output file
    # specifically the "READ" and "RELATE" commands in the UI
    
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an Epidemiology software task (Epi Info 7).
    The user should have:
    1. Opened the Classic Analysis module.
    2. Loaded a dataset (READ command).
    3. Linked a second table (RELATE command).
    4. Produced statistical output tables.

    Look at the sequence of images. 
    - Do you see the Epi Info Classic Analysis interface (command prompt at bottom, output window)?
    - Is there evidence of 'READ' or 'RELATE' commands being typed or appearing in the log?
    - Do you see output tables (Frequency or Crosstab) in the final images?

    Return valid JSON:
    {
        "analysis_interface_visible": true,
        "relate_command_evidence": true,
        "output_tables_visible": true,
        "score_0_to_20": 15
    }
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        vlm_score = min(20, parsed.get('score_0_to_20', 0))
        
        if parsed.get('relate_command_evidence'):
            feedback_parts.append("VLM confirmed RELATE command usage.")
        if parsed.get('output_tables_visible'):
            feedback_parts.append("VLM confirmed visible output.")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if programmatic check passed high, give partial VLM points
        if score > 50:
            vlm_score = 10
            
    score += vlm_score
    
    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    passed = score >= 60 and result_data.get('output_exists') and tables_found >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }