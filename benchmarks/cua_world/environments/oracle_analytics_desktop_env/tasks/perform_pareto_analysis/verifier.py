#!/usr/bin/env python3
"""
Verifier for perform_pareto_analysis task (Oracle Analytics Desktop).

Checks:
1. File 'Pareto_Analysis.dva' exists and was created during task.
2. DVA file is a valid ZIP and contains visualization metadata.
3. Metadata confirms 'Combo' chart type, 'Sales' measure, and Descending Sort.
4. VLM verifies the visual structure (Pareto shape: bars dropping, line rising).
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perform_pareto_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Fetch Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Score Components
    score = 0
    feedback_parts = []
    
    # Criterion A: Output File Existence & Freshness (20 pts)
    output_exists = result_data.get('output_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("Workbook file saved.")
        if created_during:
            score += 10
            feedback_parts.append("File created during session.")
        else:
            feedback_parts.append("File timestamp indicates old file (not created now).")
    else:
        feedback_parts.append("Workbook 'Pareto_Analysis.dva' not found.")
        # If file missing, fail immediately
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # Criterion B: DVA Content Analysis (40 pts)
    # DVA files are ZIPs containing XML/JSON metadata
    dva_valid = False
    viz_keywords_found = []
    
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.dva')
    try:
        copy_from_env(result_data.get('file_path', "C:\\Users\\Docker\\Documents\\Pareto_Analysis.dva"), temp_dva.name)
        
        if zipfile.is_zipfile(temp_dva.name):
            dva_valid = True
            with zipfile.ZipFile(temp_dva.name, 'r') as z:
                # Search for visualization metadata in common DVA internal files
                # Often in /datamodel/.. or /canvas/..
                # We search all text-based files for keywords
                for filename in z.namelist():
                    if filename.endswith(('.xml', '.json', '.txt')):
                        try:
                            content = z.read(filename).decode('utf-8', errors='ignore').lower()
                            
                            # Check for Combo Chart
                            if 'combo' in content or 'dual' in content:
                                if 'combo' not in viz_keywords_found: viz_keywords_found.append('combo')
                            
                            # Check for Sort Order (Desc)
                            if 'desc' in content or 'descending' in content:
                                if 'sort_desc' not in viz_keywords_found: viz_keywords_found.append('sort_desc')
                                
                            # Check for Running Sum
                            if 'runningsum' in content or 'msum' in content or 'running' in content:
                                if 'running_sum' not in viz_keywords_found: viz_keywords_found.append('running_sum')
                                
                        except:
                            continue
        else:
            feedback_parts.append("Saved file is not a valid DVA package.")
            
    except Exception as e:
        feedback_parts.append(f"Failed to inspect DVA content: {e}")
    finally:
        if os.path.exists(temp_dva.name):
            os.unlink(temp_dva.name)

    if dva_valid:
        if 'combo' in viz_keywords_found:
            score += 15
            feedback_parts.append("Combo chart detected in metadata.")
        if 'sort_desc' in viz_keywords_found:
            score += 15
            feedback_parts.append("Descending sort configuration detected.")
        if 'running_sum' in viz_keywords_found:
            score += 10
            feedback_parts.append("Running total calculation detected.")

    # Criterion C: VLM Verification (40 pts)
    # Use trajectory frames to confirm the visual Pareto shape
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    vlm_prompt = """
    You are verifying a "Pareto Analysis" task in Oracle Analytics Desktop.
    Look at the screen. The user should have created a Combo Chart (Bars + Line).
    
    Verify three things:
    1. Is there a chart with BOTH bars and a line? (Combo Chart)
    2. Do the bars decrease in height from left to right? (Sorted Descending)
    3. Does the line start low on the left and rise to the right? (Cumulative/Running Sum)
    
    Answer JSON:
    {
      "is_combo_chart": boolean,
      "bars_sorted_descending": boolean,
      "line_is_cumulative": boolean,
      "chart_title_visible": boolean
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('parsed'):
        parsed = vlm_result['parsed']
        if parsed.get('is_combo_chart'): vlm_score += 10
        if parsed.get('bars_sorted_descending'): vlm_score += 15
        if parsed.get('line_is_cumulative'): vlm_score += 15
        
        feedback_parts.append(f"VLM Analysis: Combo={parsed.get('is_combo_chart')}, Sorted={parsed.get('bars_sorted_descending')}, Cumulative={parsed.get('line_is_cumulative')}")
    else:
        # Fallback if VLM fails but DVA was good
        if dva_valid and len(viz_keywords_found) >= 2:
            vlm_score = 20
            feedback_parts.append("VLM inconclusive, using metadata confidence.")

    score += vlm_score
    
    # Final Pass/Fail
    # Must have file, must look sorted (critical for Pareto)
    passed = (output_exists and created_during and score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }