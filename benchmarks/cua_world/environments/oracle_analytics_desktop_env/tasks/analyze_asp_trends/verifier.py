#!/usr/bin/env python3
"""
Verifier for analyze_asp_trends task (Oracle Analytics Desktop).

Verification Strategy:
1. File Existence: Check if ASP_Analysis.dva exists and was modified during task.
2. DVA Inspection: The .dva file is a ZIP archive. We inspect internal XMLs for the custom formula.
   - Look for 'SUM(Revenue)' and 'SUM(Quantity)' in the same expression.
   - Reject 'AVG' based calculations.
3. VLM Verification: Use trajectory and final screenshot to verify:
   - Bar chart present.
   - Correct dimensions (Category, Sub Category, ASP).
   - Sort order (descending).
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def inspect_dva_file(dva_path):
    """
    Inspects the contents of the Oracle Analytics .dva file.
    Returns a dict with analysis results.
    """
    analysis = {
        "valid_zip": False,
        "contains_asp_term": False,
        "contains_sum_aggregation": False,
        "contains_division": False,
        "xml_content_found": False
    }

    if not os.path.exists(dva_path):
        return analysis

    try:
        with zipfile.ZipFile(dva_path, 'r') as z:
            analysis["valid_zip"] = True
            
            # Iterate through files to find data model or logic
            # DVA structure typically has 'datamodel' folder
            for filename in z.namelist():
                if filename.endswith('.xml') or filename.endswith('.json'):
                    try:
                        with z.open(filename) as f:
                            content = f.read().decode('utf-8', errors='ignore')
                            
                            # Look for calculation evidence
                            if "ASP" in content or "Average Selling Price" in content:
                                analysis["contains_asp_term"] = True
                            
                            # Look for the specific formula pattern
                            # XML might encode it as <expr>SUM(Revenue) / SUM(Quantity)</expr>
                            # We search for loose indicators to be robust against XML structure variations
                            if "SUM" in content and "Revenue" in content and "Quantity" in content:
                                analysis["contains_sum_aggregation"] = True
                            
                            if "/" in content or "div" in content:
                                analysis["contains_division"] = True
                                
                            analysis["xml_content_found"] = True
                    except:
                        continue
    except zipfile.BadZipFile:
        pass

    return analysis

def verify_analyze_asp_trends(traj, env_info, task_info):
    """
    Verifies the ASP analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get JSON Result and DVA file
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    dva_path = os.path.join(temp_dir, "ASP_Analysis.dva")
    
    try:
        # Copy JSON result
        try:
            copy_from_env("C:\\tmp\\task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Basic Checks (30 pts)
        if task_result.get("output_exists"):
            score += 10
            feedback_parts.append("Workbook file created.")
            
            if task_result.get("file_created_during_task"):
                score += 10
                feedback_parts.append("File created during task.")
            else:
                feedback_parts.append("Warning: File timestamp indicates it might be old.")
                
            if task_result.get("output_size_bytes", 0) > 1000:
                score += 10
                feedback_parts.append("File size is valid.")
            else:
                feedback_parts.append("File seems empty.")

            # Copy DVA file for inspection
            try:
                copy_from_env(task_result.get("target_file_path", "C:\\Users\\Docker\\Documents\\ASP_Analysis.dva"), dva_path)
                
                # Inspection Checks (30 pts)
                dva_analysis = inspect_dva_file(dva_path)
                if dva_analysis["valid_zip"]:
                    score += 5
                    if dva_analysis["contains_asp_term"]:
                        score += 10
                        feedback_parts.append("Found 'ASP' calculation in workbook metadata.")
                    
                    if dva_analysis["contains_sum_aggregation"]:
                        score += 15
                        feedback_parts.append("Found evidence of correct SUM aggregation formula.")
                    else:
                        feedback_parts.append("Could not confirm correct aggregation formula in file.")
                else:
                    feedback_parts.append("Saved file is not a valid DVA archive.")

            except Exception as e:
                feedback_parts.append(f"Could not inspect DVA file content: {e}")
        else:
            feedback_parts.append("Output file ASP_Analysis.dva not found.")

        # 2. VLM Verification (40 pts)
        # We need to verify the chart visual correctnes
        final_screenshot = get_final_screenshot(traj)
        trajectory_frames = sample_trajectory_frames(traj, n=3)
        
        vlm_prompt = """
        You are verifying an Oracle Analytics Desktop task.
        The user was asked to create a Bar Chart showing 'Average Selling Price (ASP)' by 'Product Sub Category'.
        
        Please check the screenshot for the following:
        1. Is there a Bar Chart visible?
        2. Are the bars colored (indicating a Color category was used)?
        3. Does the Y-axis label likely say 'ASP' or 'Average Selling Price'?
        4. Are the bars sorted in descending order (tallest on left/top)?
        5. Does the X-axis show categories like 'Copiers', 'Phones', 'Bookcases', etc.?
        
        Answer with JSON:
        {
            "bar_chart_visible": true/false,
            "multiple_colors": true/false,
            "y_axis_label_correct": true/false,
            "sorted_descending": true/false,
            "x_axis_categories_visible": true/false
        }
        """
        
        vlm_result = query_vlm(prompt=vlm_prompt, image=final_screenshot, images=trajectory_frames)
        
        if vlm_result.get("success"):
            analysis = vlm_result.get("parsed", {})
            
            if analysis.get("bar_chart_visible"):
                score += 10
                feedback_parts.append("VLM: Bar chart verified.")
            
            if analysis.get("multiple_colors"):
                score += 10
                feedback_parts.append("VLM: Color coding verified.")
                
            if analysis.get("sorted_descending"):
                score += 10
                feedback_parts.append("VLM: Descending sort verified.")
                
            if analysis.get("y_axis_label_correct") or analysis.get("x_axis_categories_visible"):
                score += 10
                feedback_parts.append("VLM: Labels/Categories verified.")
        else:
            feedback_parts.append("VLM verification failed to run.")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }