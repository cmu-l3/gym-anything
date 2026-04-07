#!/usr/bin/env python3
"""
Verifier for download_sectional_chart task.

Verifies:
1. Filesystem: Significant increase in file count/size in Avare data directory.
2. Content: Existence of 'San Francisco' specific chart files.
3. Visual: VLM verification of the download process and final map state.
"""

import json
import tempfile
import os
import logging
import time
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_download_sectional_chart(traj, env_info, task_info):
    """
    Verify that the San Francisco Sectional chart was downloaded.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_expected_size_bytes', 5000000) # 5MB min for a chart
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. PROGRAMMATIC VERIFICATION (Filesystem)
    # =========================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    new_files = result_data.get('new_files_count', 0)
    sf_files_found = result_data.get('sf_files_found', False)
    total_size = result_data.get('total_data_size_bytes', 0)

    # Criteria 1: San Francisco files exist (20 pts)
    if sf_files_found:
        score += 20
        feedback_parts.append("Found San Francisco chart files.")
    else:
        feedback_parts.append("Did not find specific 'San Francisco' chart files.")

    # Criteria 2: Data size check (20 pts)
    # A real sectional download is substantial (usually >10MB)
    if total_size > min_size:
        score += 20
        feedback_parts.append(f"Downloaded data size ({total_size/1024/1024:.1f} MB) is valid.")
    elif total_size > 100000: # >100KB, maybe just started
        score += 5
        feedback_parts.append("Downloaded data size is too small for a full chart.")
    else:
        feedback_parts.append("No significant data downloaded.")

    # Criteria 3: New file count (10 pts)
    # Charts usually consist of many tiles
    if new_files > 10:
        score += 10
        feedback_parts.append(f"Significant new files created ({new_files}).")
    
    # =========================================================
    # 2. VLM VERIFICATION (Trajectory & Visuals)
    # =========================================================
    
    # Get frames for analysis
    # We want to see:
    # 1. Download Manager screen
    # 2. 'San Francisco' being selected
    # 3. Final map showing terrain/chart data (not just gray/black background)
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    if not frames:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " (No screenshots available)"}

    prompt = """
    Analyze this sequence of screenshots from the Avare aviation app.
    The user task is to download the "San Francisco" Sectional Chart.

    Check for these specific steps:
    1. Did the user navigate to the 'Download' or 'Map Data' screen?
    2. Is the "San Francisco" chart selected or checked in a list?
    3. Is there a "Get" or "Download" button interaction?
    4. Does the FINAL screenshot show a colorful aviation map (terrain, airspace circles, airports) or just a blank/black grid?
    
    If the final map is colorful and detailed, that is strong evidence of success.
    
    Return JSON:
    {
        "download_menu_reached": boolean,
        "sf_chart_selected": boolean,
        "final_map_shows_chart": boolean,
        "reasoning": "string"
    }
    """

    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    if vlm_result.get('success'):
        analysis = vlm_result.get('parsed', {})
        
        # Scoring VLM components
        if analysis.get('download_menu_reached'):
            score += 10
            feedback_parts.append("VLM: Reached Download menu.")
        
        if analysis.get('sf_chart_selected'):
            score += 15
            feedback_parts.append("VLM: Selected San Francisco chart.")
            
        if analysis.get('final_map_shows_chart'):
            score += 25
            feedback_parts.append("VLM: Final map shows loaded chart data.")
        else:
            feedback_parts.append("VLM: Final map does not appear to show chart data.")
            
    else:
        feedback_parts.append("VLM verification failed to run.")

    # =========================================================
    # FINAL SCORING
    # =========================================================
    # Max score: 50 (Prog) + 50 (VLM) = 100
    
    passed = score >= 60 and (sf_files_found or analysis.get('final_map_shows_chart'))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }