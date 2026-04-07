#!/usr/bin/env python3
"""
Verifier for analyze_yoy_growth task (Oracle Analytics Desktop).

Criteria:
1. File Verification (40 pts): 'Annual_Growth_Analysis.dva' exists and was created during task.
2. Content Verification (30 pts): DVA file contains evidence of Growth metric and Year usage.
3. VLM Verification (30 pts): Trajectory shows Combo Chart (Bars + Line) and Percentage formatting.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_yoy_growth(traj, env_info, task_info):
    """
    Verify the YoY Growth Analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Windows Env
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Path must match what's in export_result.ps1
        # Note: In Windows containers, paths might need careful handling, 
        # but copy_from_env usually handles absolute paths in the guest.
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from environment."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Check 1: File Existence & Anti-Gaming (40 pts) ---
    if result.get('output_exists'):
        if result.get('file_created_during_task'):
            score += 40
            feedback_parts.append("Workbook saved successfully during task.")
        else:
            score += 10
            feedback_parts.append("Workbook exists but timestamp indicates it wasn't saved *during* the task (anti-gaming).")
    else:
        feedback_parts.append("Workbook 'Annual_Growth_Analysis.dva' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Check 2: Content Inspection (30 pts) ---
    found_terms = result.get('found_terms', [])
    chart_type = result.get('chart_type_detected', 'unknown')
    
    if "GrowthMetric" in found_terms:
        score += 15
        feedback_parts.append("Growth calculation detected in workbook.")
    
    if chart_type == "combo":
        score += 15
        feedback_parts.append("Combo/Dual-Axis chart configuration detected in workbook metadata.")
    elif chart_type != "unknown":
        score += 5
        feedback_parts.append(f"Chart type detected ('{chart_type}') but expected Combo/Dual-Axis.")
    
    # --- Check 3: VLM Verification (30 pts) ---
    # We check for: 1. Combo chart structure (Bars + Line), 2. Percentage formatting
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images_to_check = frames + [final_screen] if final_screen else frames

    if images_to_check:
        prompt = """
        Analyze these screenshots of Oracle Analytics Desktop.
        The user is supposed to create a "Year-Over-Year Growth" analysis.
        
        Look for a chart that has TWO axes or mixed types:
        1. Are there BARS (vertical columns) representing Revenue?
        2. Is there a LINE overlaid on the bars representing Growth?
        3. Do you see a Percentage (%) scale on the right axis or percentage values?
        4. Is the X-axis showing Years (e.g. 2014, 2015)?

        Respond in JSON:
        {
            "combo_chart_visible": true/false,
            "bars_and_line_present": true/false,
            "percentage_format_visible": true/false,
            "years_on_axis": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        vlm_resp = query_vlm(prompt=prompt, images=images_to_check)
        
        if vlm_resp.get('success'):
            analysis = vlm_resp.get('parsed', {})
            
            if analysis.get('combo_chart_visible') or analysis.get('bars_and_line_present'):
                score += 20
                feedback_parts.append("VLM confirmed Combo Chart (Bars + Line) visual structure.")
            
            if analysis.get('percentage_format_visible'):
                score += 10
                feedback_parts.append("VLM confirmed percentage formatting.")
            else:
                feedback_parts.append("VLM could not clearly see percentage formatting.")
        else:
            feedback_parts.append("VLM analysis failed.")
            # Grace points if file content was perfect
            if score >= 60: score += 10

    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }