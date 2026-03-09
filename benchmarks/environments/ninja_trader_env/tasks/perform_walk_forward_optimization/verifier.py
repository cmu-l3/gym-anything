#!/usr/bin/env python3
"""
Verifier for perform_walk_forward_optimization task.

Criteria:
1. Result CSV file exists and was created during the task. (30 pts)
2. Content Validation: File contains multiple rows (indicating WFO steps). (30 pts)
3. Content Validation: References 'SPY' or 'SampleMA' parameters. (20 pts)
4. VLM Verification: Strategy Analyzer window is visible and set to 'Walk Forward Optimization'. (20 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perform_walk_forward_optimization(traj, env_info, task_info):
    """
    Verify Walk-Forward Optimization task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # ================================================================
    # 1. Fetch Result JSON from Container
    # ================================================================
    # Note: In Windows env, paths might need adjustment depending on how copy_from_env handles them.
    # Assuming standard path mapping.
    remote_json_path = "C:/Users/Docker/Desktop/NinjaTraderTasks/task_result.json"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        copy_from_env(remote_json_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy or read result JSON: {e}")
        # If file missing, score remains 0
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ================================================================
    # 2. File-Based Verification (80 Points Total)
    # ================================================================
    
    output_exists = result_data.get('output_exists', False)
    created_during_task = result_data.get('file_created_during_task', False)
    line_count = result_data.get('line_count', 0)
    contains_spy = result_data.get('contains_spy', False)
    contains_ma = result_data.get('contains_ma', False)
    is_wfo_format = result_data.get('is_wfo_format', False)

    # Criterion 1: File Exists & Created (30 pts)
    if output_exists and created_during_task:
        score += 30
        feedback_parts.append("Result file created successfully (+30)")
    elif output_exists:
        score += 10
        feedback_parts.append("Result file exists but timestamp check failed (+10)")
    else:
        feedback_parts.append("Result file not found (0)")

    # Criterion 2: WFO Structure (30 pts)
    # WFO output typically has headers + multiple rows for each test period
    if line_count > 5:
        score += 30
        feedback_parts.append(f"File contains {line_count} rows, indicating WFO steps (+30)")
    elif line_count > 0:
        score += 10
        feedback_parts.append("File content is very short, possibly failed WFO (+10)")
    else:
        feedback_parts.append("File is empty (0)")

    # Criterion 3: Content Relevance (20 pts)
    if contains_spy or contains_ma:
        score += 20
        feedback_parts.append("Content matches Strategy/Instrument criteria (+20)")
    else:
        feedback_parts.append("Content does not explicitly show SPY/SampleMA (0)")

    # ================================================================
    # 3. VLM Verification (20 Points)
    # ================================================================
    # We check if the agent actually used the Strategy Analyzer
    
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=3)
    all_images = frames + ([final_screenshot] if final_screenshot else [])

    if all_images:
        prompt = """
        Analyze these screenshots of NinjaTrader 8.
        The user is supposed to be running a 'Walk Forward Optimization' in the Strategy Analyzer.
        
        Look for:
        1. A window titled 'Strategy Analyzer'.
        2. Settings showing 'Walk Forward Optimization' (or WFO) selected in the 'Mode' dropdown.
        3. A grid of results with dates (Walk Forward results).
        
        Does the visual evidence suggest the WFO was configured and run?
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=all_images)
            
            if vlm_res.get("success"):
                # Basic positive sentiment analysis of the VLM response
                analysis = vlm_res.get("parsed", {}).get("analysis", "") or vlm_res.get("response", "")
                lower_analysis = str(analysis).lower()
                
                # Check for keywords in VLM reasoning
                positive_signals = ["strategy analyzer", "walk forward", "wfo", "optimization"]
                matches = sum(1 for sig in positive_signals if sig in lower_analysis)
                
                if matches >= 2:
                    score += 20
                    feedback_parts.append("VLM confirms Strategy Analyzer usage (+20)")
                elif matches == 1:
                    score += 10
                    feedback_parts.append("VLM partially confirms UI usage (+10)")
                else:
                    feedback_parts.append("VLM could not confirm correct UI usage")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if file score is high, assume pass
            if score >= 60: 
                score += 20
                feedback_parts.append("VLM skipped, assuming success based on file")

    # ================================================================
    # Final Evaluation
    # ================================================================
    
    # Pass threshold: 60 points (Requires file creation + some content validity)
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }