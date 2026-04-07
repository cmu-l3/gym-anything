#!/usr/bin/env python3
"""
Verifier for create_profit_status_breakdown task.

Verifies:
1. DVA file creation and validity (zip structure).
2. "Profit Status" calculation existence and logic (CASE WHEN ... >= 0).
3. Stacked Bar Chart existence with correct dimensions.
4. Semantic coloring (Red/Green) via VLM.
"""

import json
import os
import zipfile
import tempfile
import shutil
import re
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_profit_status_breakdown(traj, env_info, task_info):
    """
    Verify the Oracle Analytics Desktop Profit Status task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'Profit_Status_Analysis.dva')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve and Analyze Result JSON & DVA File
    # ------------------------------------------------------------------
    temp_dir = tempfile.mkdtemp()
    try:
        # Get result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # Basic File Checks
        if not result_data.get("output_exists"):
            return {"passed": False, "score": 0, "feedback": "Output DVA file not found."}
            
        score += 10 # File exists
        if result_data.get("file_created_during_task"):
            score += 10 # Created during session
        else:
            feedback_parts.append("Warning: File timestamp indicates it wasn't modified during this session.")

        # Get DVA File
        dva_local_path = os.path.join(temp_dir, expected_filename)
        try:
            copy_from_env(result_data["output_path"], dva_local_path)
        except Exception as e:
            feedback_parts.append(f"Could not copy DVA file for inspection: {str(e)}")
            dva_local_path = None

        # ------------------------------------------------------------------
        # 2. Inspect DVA Content (Programmatic)
        # ------------------------------------------------------------------
        dva_valid = False
        calculation_found = False
        chart_found = False
        
        if dva_local_path and zipfile.is_zipfile(dva_local_path):
            dva_valid = True
            try:
                with zipfile.ZipFile(dva_local_path, 'r') as z:
                    # Search XML/JSON files for specific keywords
                    # OAD stores metadata in datamodel files or layout xmls
                    content_str = ""
                    for filename in z.namelist():
                        if filename.endswith(".xml") or filename.endswith(".json"):
                            try:
                                with z.open(filename) as f:
                                    content_str += f.read().decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Check for Calculation Logic
                    # Looking for "Profit Status" and "CASE" logic
                    if "Profit Status" in content_str:
                        score += 10
                        calculation_found = True
                        
                    # Check for logic details (flexible matching)
                    if re.search(r"CASE.*WHEN.*Profit.*>=.*0.*THEN", content_str, re.IGNORECASE):
                        score += 15
                        feedback_parts.append("Calculation logic verified.")
                    elif calculation_found:
                        feedback_parts.append("Calculation name found, but logic could not be strictly verified in XML.")

                    # Check for Visualization
                    # Look for "bar" and "stacked"
                    if "bar" in content_str.lower() and "stacked" in content_str.lower():
                        score += 15
                        chart_found = True
                        feedback_parts.append("Stacked Bar chart detected.")
                    
                    # Check Dimensions (Region, Count)
                    if "Region" in content_str and ("Count" in content_str or "Records" in content_str):
                        score += 10
                        feedback_parts.append("Correct dimensions detected in metadata.")

            except Exception as e:
                feedback_parts.append(f"Error analyzing DVA structure: {str(e)}")
        
        if not dva_valid and dva_local_path:
             feedback_parts.append("Output file is not a valid DVA/ZIP archive.")

        # ------------------------------------------------------------------
        # 3. VLM Verification (Visual & Semantic)
        # ------------------------------------------------------------------
        # Use trajectory to confirm steps and final screenshot for colors
        final_screenshot = get_final_screenshot(traj)
        trajectory_frames = sample_trajectory_frames(traj, n=3)
        
        vlm_passed = False
        if final_screenshot:
            prompt = """
            You are verifying an Oracle Analytics Desktop task.
            Goal: A Stacked Bar Chart titled 'Regional Profitability Mix' showing 'Profit Status' (Profitable vs Loss).
            
            Check the following in the screenshot:
            1. Is there a stacked bar chart?
            2. Are the bars split into two colors?
            3. Is one segment Green and the other Red?
            4. Does the title say 'Regional Profitability Mix'?
            5. Are the X-axis labels geographic regions (e.g., East, West, Central)?
            
            Return JSON:
            {
                "is_stacked_bar": boolean,
                "has_red_green_colors": boolean,
                "title_correct": boolean,
                "regions_axis": boolean,
                "confidence": 0-10
            }
            """
            
            vlm_result = query_vlm(prompt=prompt, image=final_screenshot)
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("is_stacked_bar"):
                    score += 10
                if parsed.get("has_red_green_colors"):
                    score += 10 # Critical semantic check
                    feedback_parts.append("Semantic coloring (Red/Green) verified.")
                if parsed.get("title_correct"):
                    score += 5
                if parsed.get("regions_axis"):
                    score += 5
                
                vlm_passed = True
            else:
                feedback_parts.append("VLM verification failed to process.")

        # Trajectory check for calculation editor
        if trajectory_frames:
            traj_prompt = "Do these screenshots show the user entering a formula in a calculation editor, specifically a CASE statement?"
            traj_result = query_vlm(prompt=traj_prompt, images=trajectory_frames)
            # We treat this as supporting evidence but don't strictly score it if final file is good.

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    # Final Pass Logic
    # Must have created file + calculation found + visual chart confirmation
    passed = (result_data.get("output_exists") and 
              result_data.get("file_created_during_task") and 
              calculation_found and 
              score >= 70)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }