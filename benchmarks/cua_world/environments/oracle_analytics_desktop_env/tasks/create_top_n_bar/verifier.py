#!/usr/bin/env python3
"""
Verifier for create_top_n_bar task (Oracle Analytics Desktop).

Criteria:
1. Workbook file 'Top10Cities.dva' exists and was saved during task (20 pts).
2. VLM Trajectory Verification (80 pts):
   - Workflow: Load data -> Create Viz -> Add Columns -> Filter (30 pts).
   - Final Visuals: Horizontal Bar Chart, 10 bars (Top N), Sorted, Color by Region (50 pts).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_top_n_bar(traj, env_info, task_info):
    """
    Verifies the Top N Bar Chart task using file checks and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. FILE VERIFICATION
    # ====================
    file_score = 0
    feedback_parts = []
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        # Note: In Windows envs, the path might need adjustment or mount, 
        # but copy_from_env usually handles the container path mapping.
        # The export script saved to C:\tmp\task_result.json, which usually maps to /tmp/task_result.json 
        # or similar depending on the runtime. We'll try the standard location.
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read result file: {e}")
        # Try Linux-style path just in case
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result_data = json.load(f)
        except:
            pass
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result_data.get('output_exists'):
        file_score += 10
        feedback_parts.append("Workbook file 'Top10Cities.dva' found.")
        if result_data.get('file_created_during_task'):
            file_score += 10
            feedback_parts.append("Workbook was saved during the session.")
        else:
            feedback_parts.append("Warning: Workbook timestamp predates task (stale file?).")
    else:
        feedback_parts.append("Workbook file 'Top10Cities.dva' NOT found.")

    # 2. VLM VERIFICATION (Trajectory & Final State)
    # ==============================================
    vlm_score = 0
    
    # Sample frames to see workflow
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if not final_frame:
         return {"passed": False, "score": file_score, "feedback": "No screenshots available for verification."}

    prompt = """
    You are evaluating a user performing a task in Oracle Analytics Desktop.
    Goal: Create a Horizontal Bar Chart of 'City' by 'Revenue', Color by 'Region', filtered to Top 10 Cities.

    Analyze the provided screenshots (chronological order, last one is final).

    Check for these specific criteria:
    1. **Chart Type**: Is there a Horizontal Bar Chart visible? (Bars going left-to-right).
    2. **Filtering**: Are there exactly 10 bars visible? (Count them carefully). If there are many more (e.g., >20), the Top 10 filter is missing.
    3. **Sorting**: Is the chart sorted with the longest bar at the top (Descending by Revenue)?
    4. **Coloring**: Are the bars multicolored (indicating Region is used for color) or all one color?
    5. **Fields**: Can you see labels indicating 'City', 'Revenue', or 'Region'?

    Return JSON:
    {
        "chart_type_correct": boolean,
        "bar_count_is_ten": boolean,
        "sorted_descending": boolean,
        "colored_by_region": boolean,
        "workflow_evidence": boolean,
        "explanation": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_frame], prompt=prompt)
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('chart_type_correct'):
            vlm_score += 20
            feedback_parts.append("Correctly created a horizontal bar chart.")
        else:
            feedback_parts.append("Failed to identify horizontal bar chart.")
            
        if parsed.get('bar_count_is_ten'):
            vlm_score += 30
            feedback_parts.append("Top N filter applied correctly (10 bars visible).")
        else:
            feedback_parts.append("Incorrect number of bars (Top 10 filter missing or wrong).")
            
        if parsed.get('sorted_descending'):
            vlm_score += 15
            feedback_parts.append("Sorted correctly (descending).")
            
        if parsed.get('colored_by_region'):
            vlm_score += 15
            feedback_parts.append("Color encoding applied.")
            
    else:
        feedback_parts.append("VLM verification failed to process images.")

    # CALCULATE FINAL SCORE
    # =====================
    total_score = file_score + vlm_score
    passed = total_score >= 65 and result_data.get('output_exists') and parsed.get('bar_count_is_ten', False)
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " ".join(feedback_parts)
    }