#!/usr/bin/env python3
"""
Verifier for analyze_weekly_seasonality task.

Verification Strategy:
1. File Check: Verify 'Seasonality_Analysis.dva' exists and was created during the task.
2. Content Analysis: Unzip the .dva file (OAD workbooks are ZIPs) to inspect:
   - Metadata for a calculated column named "Day of Week" (or similar).
   - Usage of a Heatmap visualization.
3. VLM Verification: Use trajectory frames to verify the visual workflow (creation of calc field, grid layout of heatmap).
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
from vlm_utils import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_weekly_seasonality(traj, env_info, task_info):
    """
    Verifies that the agent created a seasonality heatmap with a calculated day-of-week column.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get JSON result from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task status from environment"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic Criteria: File Existence & Anti-Gaming (20 pts)
    output_exists = result_data.get('output_exists', False)
    created_fresh = result_data.get('file_created_during_task', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("Workbook file found.")
        if created_fresh:
            score += 10
            feedback_parts.append("Workbook saved during task session.")
        else:
            feedback_parts.append("WARNING: Workbook file timestamp is too old.")
    else:
        feedback_parts.append("Seasonality_Analysis.dva not found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # 2. Deep Content Analysis (40 pts)
    # We need to inspect the .dva file to check for the calculated column and heatmap.
    dva_path = result_data.get('output_path', "C:\\Users\\Docker\\Documents\\Seasonality_Analysis.dva")
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.zip') # .dva is a zip
    
    has_calc = False
    has_heatmap = False
    
    try:
        copy_from_env(dva_path, temp_dva.name)
        
        with zipfile.ZipFile(temp_dva.name, 'r') as z:
            # List files to find relevant XML/JSONs
            file_list = z.namelist()
            
            # Search for data model definition (often in datamodel/ or simply xml files)
            # We assume a standard structure or search text in all XML/JSON files
            for fname in file_list:
                if fname.endswith('.xml') or fname.endswith('.json'):
                    try:
                        content = z.read(fname).decode('utf-8', errors='ignore').lower()
                        
                        # Check for Calculated Column
                        # Keywords: "Day of Week", "DayName", "DayOfWeek", formula
                        if 'day of week' in content or 'dayname' in content:
                            # Rudimentary check, but effective if name is unique
                            has_calc = True
                            
                        # Check for Heatmap
                        # Visualization types in OAD XML often look like <obj type="heatmap"> or similar
                        if 'heatmap' in content or 'trellis' in content:
                            has_heatmap = True
                    except:
                        continue
    except Exception as e:
        feedback_parts.append(f"Could not inspect workbook contents: {e}")
    finally:
        if os.path.exists(temp_dva.name):
            os.unlink(temp_dva.name)

    if has_calc:
        score += 25
        feedback_parts.append("Calculated column 'Day of Week' detected in workbook metadata.")
    else:
        feedback_parts.append("Could not verify specific 'Day of Week' calculation in metadata.")

    if has_heatmap:
        score += 15
        feedback_parts.append("Heatmap visualization detected in workbook metadata.")
    else:
        feedback_parts.append("Heatmap visualization not explicitly found in metadata.")

    # 3. VLM Verification (40 pts)
    # Visual check is crucial for layout correctness (Rows=Month, Cols=Day)
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this final screenshot of Oracle Analytics Desktop.
    The user is trying to create a 'Seasonality Analysis' heatmap.
    
    Check for the following:
    1. Is there a Heatmap visualization (grid of colored cells)?
    2. Are the X-axis columns labeled with Days of the Week (Mon, Tue, Wed...)?
    3. Are the Y-axis rows labeled with Months (Jan, Feb...)?
    4. Does the title say 'Order Volume Heatmap' or similar?
    
    Provide a score between 0 and 100 based on these criteria.
    Reply with JSON: {"score": <int>, "heatmap_visible": <bool>, "days_on_axis": <bool>, "months_on_axis": <bool>}
    """
    
    vlm_result = query_vlm(images=[final_screen] if final_screen else frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and isinstance(vlm_result, dict):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('heatmap_visible'):
            vlm_score += 15
        if parsed.get('days_on_axis'):
            vlm_score += 15
        if parsed.get('months_on_axis'):
            vlm_score += 10
            
        feedback_parts.append(f"VLM Analysis: Heatmap={'Yes' if parsed.get('heatmap_visible') else 'No'}, DaysAxis={'Yes' if parsed.get('days_on_axis') else 'No'}.")
    else:
        # Fallback if VLM fails but file checks passed
        if has_calc and has_heatmap:
            vlm_score = 30 # Give partial credit
            feedback_parts.append("VLM unavailable, trusting metadata checks.")

    score += vlm_score

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }