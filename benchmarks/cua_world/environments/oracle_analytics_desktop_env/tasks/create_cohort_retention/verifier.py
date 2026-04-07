#!/usr/bin/env python3
"""
Verifier for Customer Cohort Analysis task.

Criteria:
1. Workbook file (.dva) exists and was modified during task.
2. Internal metadata check: Calculation for 'Acquisition' using MIN/BY logic exists.
3. Internal metadata check: Pivot Table visualization exists.
4. VLM: Visual verification of cohort triangle shape and heatmap.
"""

import json
import os
import tempfile
import zipfile
import logging
import shutil
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_cohort_retention(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup Score
    score = 0
    feedback_parts = []
    
    # 1. Fetch Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify File Existence & Creation (30 points)
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 30
        feedback_parts.append("Workbook saved successfully")
    elif result.get('output_exists'):
        score += 10
        feedback_parts.append("Workbook exists but timestamp check failed (stale?)")
    else:
        feedback_parts.append("Workbook not saved")
        # Fail early if no file
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Deep File Inspection (30 points)
    # The .dva file is a ZIP. We extract it to look for query logic.
    dva_path = result.get('output_path', "C:\\Users\\Docker\\Documents\\Customer_Cohort_Matrix.dva")
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.zip') # .dva is zip
    
    calculation_found = False
    pivot_found = False
    
    try:
        copy_from_env(dva_path, temp_dva.name)
        
        if zipfile.is_zipfile(temp_dva.name):
            with zipfile.ZipFile(temp_dva.name, 'r') as z:
                # Search XML/JSON files for logic
                for filename in z.namelist():
                    if filename.endswith('.xml') or filename.endswith('.json'):
                        try:
                            content = z.read(filename).decode('utf-8', errors='ignore').lower()
                            
                            # Check for MIN aggregation logic (LOD)
                            # Looking for 'min' and 'by' or 'partition'
                            if 'min' in content and ('order' in content and 'date' in content):
                                calculation_found = True
                            
                            # Check for Pivot Table
                            if 'pivot' in content and 'view' in content:
                                pivot_found = True
                        except:
                            continue
    except Exception as e:
        logger.warning(f"Failed to inspect DVA file: {e}")

    if calculation_found:
        score += 15
        feedback_parts.append("Calculation logic found (MIN/LOD)")
    else:
        feedback_parts.append("Could not verify calculation logic in file")

    if pivot_found:
        score += 15
        feedback_parts.append("Pivot table structure found")
    else:
        feedback_parts.append("Pivot table structure not detected in file")

    # 4. VLM Verification (40 points)
    # We verify the visual output: triangular shape and heatmap
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are evaluating a 'Cohort Retention Matrix' created in Oracle Analytics.
    
    Check for these specific visual elements:
    1. TRIANGLE SHAPE: The data table should look like a triangle or staircase.
       (e.g., Rows=2014, 2015... Columns=2014, 2015...).
       Row 2016 should NOT have data in Column 2014.
       Row 2017 should start at Column 2017.
    2. HEATMAP: Are the cells colored based on values (e.g., green/blue shading)?
    3. AXIS LABELS: Do you see years (2014, 2015, etc.) on both axes?
    
    Respond in JSON:
    {
        "triangle_shape_visible": true/false,
        "heatmap_visible": true/false,
        "years_visible": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
    
    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('triangle_shape_visible'):
            score += 20
            feedback_parts.append("Cohort triangle shape confirmed")
        if parsed.get('heatmap_visible'):
            score += 10
            feedback_parts.append("Heatmap formatting confirmed")
        if parsed.get('years_visible'):
            score += 10
            feedback_parts.append("Year labels confirmed")
    else:
        feedback_parts.append("Visual verification failed")

    # Final tally
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }