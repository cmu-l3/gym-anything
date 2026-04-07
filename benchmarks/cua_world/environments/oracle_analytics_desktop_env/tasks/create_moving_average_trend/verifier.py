#!/usr/bin/env python3
"""
Verifier for create_moving_average_trend task.

Verification Strategy:
1. File Existence: Check if Sales_Trend_Analysis.dva exists and was created during the task.
2. Content Analysis: Unzip the .dva file (it's a ZIP archive) and search internal XML/JSON
   definitions for "movingAverage" configuration and period="3".
3. VLM Analysis: Use trajectory frames to confirm the user accessed the Analytics pane 
   and that the final chart shows two lines (raw + smooth).
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_moving_average_trend(traj, env_info, task_info):
    """
    Verifies the creation of a Moving Average trend line in Oracle Analytics Desktop.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Task Results & File
    # ------------------------------------------------------------------
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    dva_file_path = os.path.join(temp_dir, "Sales_Trend_Analysis.dva")
    
    try:
        # Get JSON result
        copy_from_env("C:\\tmp\\task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
            
        # Get DVA file if it exists
        dva_copied = False
        if result_data.get("output_exists"):
            try:
                copy_from_env("C:\\tmp\\Sales_Trend_Analysis.dva", dva_file_path)
                dva_copied = True
            except Exception as e:
                logger.warning(f"Failed to copy DVA file: {e}")

        # ------------------------------------------------------------------
        # 2. Evaluate File Metrics (40 points)
        # ------------------------------------------------------------------
        if result_data.get("output_exists"):
            score += 10
            feedback_parts.append("Workbook file saved.")
            
            if result_data.get("file_created_during_task"):
                score += 10
                feedback_parts.append("File created during task session.")
            else:
                feedback_parts.append("File timestamp indicates stale data.")

            if result_data.get("output_size_bytes", 0) > 1000: # Arbitrary small threshold
                score += 10
                feedback_parts.append("File content non-empty.")
        else:
            feedback_parts.append("Sales_Trend_Analysis.dva not found.")

        # ------------------------------------------------------------------
        # 3. Deep Content Inspection (30 points)
        # ------------------------------------------------------------------
        content_verified = False
        moving_average_found = False
        period_found = False
        
        if dva_copied and zipfile.is_zipfile(dva_file_path):
            try:
                with zipfile.ZipFile(dva_file_path, 'r') as z:
                    # OAD .dva files usually contain a 'datamodel' or specific XMLs
                    # We search all text-based files for keywords
                    for filename in z.namelist():
                        if filename.endswith(('.xml', '.json', '.txt')):
                            with z.open(filename) as f:
                                content = f.read().decode('utf-8', errors='ignore')
                                
                                # Check for Moving Average function signature
                                # Common signatures: "movingAverage", "aggRule", "trend"
                                if "movingAverage" in content or "Moving Average" in content:
                                    moving_average_found = True
                                
                                # Check for period 3
                                # This is heuristic; looking for "3" near "period" or in args
                                if moving_average_found and ('"period":3' in content or '<period>3</period>' in content or '3' in content):
                                    # Loose check for 3 if MA is found
                                    period_found = True
            except Exception as e:
                logger.warning(f"Error inspecting DVA content: {e}")

        if moving_average_found:
            score += 20
            feedback_parts.append("Internal metadata confirms Moving Average.")
            if period_found:
                score += 10
                feedback_parts.append("Period configuration appears correct (3).")
        else:
            if dva_copied:
                feedback_parts.append("Could not confirm Moving Average in file metadata.")

        # ------------------------------------------------------------------
        # 4. VLM Trajectory Verification (30 points)
        # ------------------------------------------------------------------
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        vlm_prompt = """
        Review these screenshots of Oracle Analytics Desktop.
        The user task is to create a Line Chart of Sales by Order Date and add a Moving Average trend line (period 3).
        
        Look for:
        1. A Line Chart (not bar, not pie).
        2. Two distinct lines on the chart: 
           - One jagged line (raw data).
           - One smoother line (the trend/moving average).
        3. Access to the 'Analytics' or 'Statistics' pane (left side icons usually).
        4. Any text labels like "Moving Average" or "Trend".
        
        Return JSON:
        {
            "line_chart_visible": boolean,
            "two_series_visible": boolean,
            "moving_average_label": boolean,
            "smooth_trend_line": boolean
        }
        """
        
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=frames + [final_shot] if final_shot else frames
        )
        
        vlm_passed = False
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("line_chart_visible"):
                score += 10
            if parsed.get("two_series_visible") or parsed.get("smooth_trend_line"):
                score += 15
                vlm_passed = True
            if parsed.get("moving_average_label"):
                score += 5
            
            if vlm_passed:
                feedback_parts.append("Visual verification passed: Trend line observed.")
            else:
                feedback_parts.append("Visual verification failed: Trend line not clearly visible.")
        
        # ------------------------------------------------------------------
        # 5. Final Scoring
        # ------------------------------------------------------------------
        # Mandatory: File must exist and VLM or Metadata must confirm content
        passed = (result_data.get("output_exists") and 
                  (moving_average_found or vlm_passed) and 
                  score >= 70)

        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)