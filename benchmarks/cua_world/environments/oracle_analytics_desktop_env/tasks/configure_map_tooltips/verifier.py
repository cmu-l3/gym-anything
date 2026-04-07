#!/usr/bin/env python3
"""
Verifier for configure_map_tooltips task in Oracle Analytics Desktop.
Verifies that the agent created a map and correctly configured tooltip aggregation.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_map_tooltips(traj, env_info, task_info):
    """
    Verify the task using programmatic file checks and VLM visual analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Programmatic Verification (File Analysis)
    # ==========================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve validation results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Criterion 1: Workbook saved (10 pts)
    if result.get('output_exists'):
        score += 10
        feedback_parts.append("Workbook saved successfully")
    else:
        feedback_parts.append("Workbook 'State_Insights.dva' not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Map visualization created (20 pts)
    # We trust the file inspection from export script, backed up by VLM later
    if result.get('viz_type_map_found'):
        score += 20
        feedback_parts.append("Map visualization detected in file")
    else:
        feedback_parts.append("Map visualization type not detected in workbook")

    # Criterion 3: Tooltip fields present (30 pts)
    profit_found = result.get('tooltip_profit_found')
    discount_found = result.get('tooltip_discount_found')
    
    if profit_found:
        score += 15
        feedback_parts.append("Profit field found")
    else:
        feedback_parts.append("Profit missing from workbook data")
        
    if discount_found:
        score += 15
        feedback_parts.append("Discount field found")
    else:
        feedback_parts.append("Discount missing from workbook data")

    # Criterion 4: Aggregation Rule (Critical - 20 pts)
    # This is the "smart" part of the task
    if result.get('discount_aggregation_avg'):
        score += 20
        feedback_parts.append("Correct Aggregation (Average) verified")
    else:
        feedback_parts.append("Incorrect Aggregation: Discount should be Average, not Sum")

    # 2. Visual Verification (VLM)
    # ==========================
    # Use trajectory to confirm user interaction with tooltip settings
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
         feedback_parts.append("No screenshots available for visual verification")
    else:
        vlm_prompt = """
        You are verifying an Oracle Analytics Desktop task.
        Goal: Create a Map of Sales by State, and configure tooltips to show Profit and Avg Discount.
        
        Analyze the images (trajectory + final):
        1. Is a US Map visible? (Polygons colored by data)
        2. Is there a Tooltip visible on hover? (Box showing details)
        3. If a tooltip is visible, does it show "Average Discount" or "Avg Discount"?
           (It should NOT say "Sum Discount" or just "Discount" with a large number > 1)
        4. Did the user interact with the settings menu/grammar panel?
        
        Return JSON:
        {
            "map_visible": true/false,
            "tooltip_visible": true/false,
            "aggregation_label_correct": true/false,
            "confidence": "low/high"
        }
        """
        
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        vlm_data = vlm_result.get('parsed', {})
        
        if vlm_data.get('map_visible'):
            score += 10
            feedback_parts.append("Visual: Map confirmed")
        
        # Bonus for actually seeing the tooltip with correct label
        if vlm_data.get('tooltip_visible') and vlm_data.get('aggregation_label_correct'):
            score += 10
            feedback_parts.append("Visual: Correct tooltip label 'Avg' observed")
        elif vlm_data.get('tooltip_visible'):
             # Partial credit if tooltip exists but label unclear
             score += 5
             feedback_parts.append("Visual: Tooltip observed")

    passed = score >= 60 and result.get('discount_aggregation_avg')
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }