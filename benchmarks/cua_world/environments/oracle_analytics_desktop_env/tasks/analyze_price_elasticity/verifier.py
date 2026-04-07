#!/usr/bin/env python3
"""
Verifier for Oracle Analytics Desktop Task: Analyze Price Elasticity.

Verifies:
1. DVA workbook file creation.
2. Internal DVA structure (calculation, filter, visualization).
3. VLM Trajectory analysis for workflow confirmation.
"""

import json
import os
import zipfile
import tempfile
import shutil
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_price_elasticity(traj, env_info, task_info):
    """
    Verifies the Price Elasticity task.
    
    Strategy:
    1. Retrieve `task_result.json` from the Windows environment.
    2. If the DVA file exists, retrieve it and unzip it.
    3. Grep the unzipped XML/JSON contents for:
       - Calculation formula "Sales" / "Quantity"
       - Filter value "Technology"
       - Chart type "scatter"
       - Trend line configuration
    4. Use VLM on trajectory frames to verify the workflow steps (Calculated Item editor, Filter interaction).
    """
    
    # 1. Setup and dependencies
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 2. Retrieve Result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result_json)
        with open(temp_result_json, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json):
            os.unlink(temp_result_json)
            
    # 3. Evaluate Basic File Criteria
    output_exists = result_data.get('output_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("Workbook file saved.")
        if created_during:
            score += 10
            feedback_parts.append("Workbook created during task.")
        else:
            feedback_parts.append("Workbook timestamp pre-dates task (re-used old file?).")
    else:
        feedback_parts.append("Workbook file not found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # 4. Deep Inspection of DVA File
    dva_content_score = 0
    dva_feedback = []
    
    temp_dva_path = tempfile.NamedTemporaryFile(delete=False, suffix='.zip').name
    extract_dir = tempfile.mkdtemp()
    
    try:
        # Copy DVA file from container
        copy_from_env("C:\\Users\\Docker\\Documents\\Price_Elasticity.dva", temp_dva_path)
        
        # Unzip DVA (it is a zip archive)
        if zipfile.is_zipfile(temp_dva_path):
            with zipfile.ZipFile(temp_dva_path, 'r') as zip_ref:
                zip_ref.extractall(extract_dir)
            
            # Recursive search for strings in all text/xml files
            found_calculation = False
            found_filter = False
            found_scatter = False
            found_trend = False
            
            # Strings to search for
            # Oracle Analytics XMLs often encode formulas. We look for fragments.
            # "Sales" and "Quantity" in close proximity, or specific XML tags
            
            for root, dirs, files in os.walk(extract_dir):
                for file in files:
                    if file.endswith(('.xml', '.json', '.txt', '.xslt')):
                        try:
                            with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as f:
                                content = f.read()
                                
                                # Check for Calculation: Sales / Quantity
                                # The internal representation might be complex, but usually contains the column names and operator
                                if "Sales" in content and "Quantity" in content:
                                    # Very naive check, but robust for existence
                                    found_calculation = True
                                
                                # Check for Filter: Technology
                                if "Technology" in content:
                                    found_filter = True
                                    
                                # Check for Scatter plot
                                if "scatter" in content.lower():
                                    found_scatter = True
                                
                                # Check for Trend line
                                if "trend" in content.lower() or "regression" in content.lower():
                                    found_trend = True
                        except:
                            continue

            # Scoring based on findings
            if found_calculation:
                dva_content_score += 25
                dva_feedback.append("Calculation logic detected.")
            else:
                dva_feedback.append("Could not confirm calculation logic in file.")
                
            if found_filter:
                dva_content_score += 20
                dva_feedback.append("Filter for 'Technology' detected.")
            else:
                dva_feedback.append("Filter 'Technology' not found in file.")
                
            if found_scatter:
                dva_content_score += 15
                dva_feedback.append("Scatter plot configuration detected.")
            else:
                dva_feedback.append("Scatter plot configuration not found.")
            
            if found_trend:
                dva_content_score += 15
                dva_feedback.append("Trend line configuration detected.")
            else:
                dva_feedback.append("Trend line configuration not found.")
                
    except Exception as e:
        dva_feedback.append(f"Error inspecting DVA file: {str(e)}")
    finally:
        if os.path.exists(temp_dva_path):
            os.unlink(temp_dva_path)
        if os.path.exists(extract_dir):
            shutil.rmtree(extract_dir)

    score += dva_content_score
    feedback_parts.extend(dva_feedback)

    # 5. VLM Verification (Fallback/Confirm)
    # We check if the agent actually did the visual steps
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of Oracle Analytics Desktop.
        I am looking for evidence of the following workflow:
        1. A filter bar or panel showing "Technology".
        2. A scatter plot (dots/points) on the canvas.
        3. A line (trend line) drawn through the points.
        4. Axis labels showing "Unit Price" or "Quantity".
        
        Output JSON:
        {
            "has_scatter_plot": boolean,
            "has_trend_line": boolean,
            "has_technology_filter": boolean,
            "confidence": 0.0-1.0
        }
        """
        
        try:
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            parsed = vlm_result.get('parsed', {})
            
            vlm_score = 0
            if parsed.get('has_scatter_plot'): vlm_score += 2
            if parsed.get('has_trend_line'): vlm_score += 2
            if parsed.get('has_technology_filter'): vlm_score += 1
            
            # Add up to 5 points bonus/confirmation
            if score < 95 and vlm_score > 0:
                score += vlm_score
                feedback_parts.append(f"VLM confirmed visual elements (Bonus +{vlm_score}).")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Final result
    # Pass threshold: 75 (Need mostly everything correct)
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }