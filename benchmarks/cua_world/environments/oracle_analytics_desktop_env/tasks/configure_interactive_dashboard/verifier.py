#!/usr/bin/env python3
"""
Verifier for configure_interactive_dashboard task.

Uses a combination of:
1. File Inspection: Unzipping the .dva (JSON/XML) to verify visualization configuration.
2. VLM Verification: Analyzing the trajectory to confirm the user interface interaction (filter selection).
"""

import json
import os
import zipfile
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- VLM Helpers ---

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")
    return None

def verify_configure_interactive_dashboard(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the agent created a dashboard with a Bar Chart and Table,
    configured the Bar Chart as a filter, and selected 'East' to filter the table.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Scoring weights
    SCORE_FILE_EXISTS = 10
    SCORE_VISUALIZATIONS_CREATED = 30
    SCORE_INTERACTIVITY_CONFIGURED = 20  # Verified via file or VLM
    SCORE_SELECTION_STATE = 20          # Verified via VLM
    SCORE_FILTERING_EFFECT = 20         # Verified via VLM
    
    score = 0
    feedback_parts = []
    
    # --- Step 1: File Verification ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    dva_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.dva')
    
    try:
        # Get result JSON
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        output_exists = result_data.get("output_exists", False)
        created_during_task = result_data.get("file_created_during_task", False)
        output_path = result_data.get("output_path", "")

        if output_exists and created_during_task:
            score += SCORE_FILE_EXISTS
            feedback_parts.append("Workbook saved successfully.")
            
            # Copy the actual .dva file for deep inspection
            try:
                # OAD .dva files are ZIPs containing XML/JSON definitions
                copy_from_env(output_path, dva_temp.name)
                
                with zipfile.ZipFile(dva_temp.name, 'r') as z:
                    # List files to find definition
                    filenames = z.namelist()
                    # Usually contains a main datamodel file or similar
                    # We look for indications of 2 visualizations
                    content_found = False
                    vis_count = 0
                    
                    # Heuristic: Read known metadata files (structure varies by version, usually xml or json)
                    # We'll just scan all text-based files for keywords if specific path unknown
                    for fname in filenames:
                        if fname.endswith('.xml') or fname.endswith('.json'):
                            try:
                                content = z.read(fname).decode('utf-8', errors='ignore')
                                if "bar" in content.lower():
                                    vis_count += 0.5 # Partial credit for finding vis types
                                if "table" in content.lower():
                                    vis_count += 0.5
                                if "useasfilter" in content.lower() or "masterdetail" in content.lower():
                                    score += SCORE_INTERACTIVITY_CONFIGURED
                                    feedback_parts.append("Interactivity configuration detected in file.")
                                    content_found = True
                            except:
                                pass
                    
                    if vis_count >= 1:
                        score += SCORE_VISUALIZATIONS_CREATED
                        feedback_parts.append("Visualizations detected in workbook file.")
                    
            except Exception as e:
                logger.warning(f"Failed to inspect DVA file: {e}")
                feedback_parts.append("Could not inspect workbook internals.")
        else:
            feedback_parts.append("Workbook file not found or not saved during task.")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(dva_temp.name):
            os.unlink(dva_temp.name)

    # --- Step 2: VLM Verification (Trajectory) ---
    # We check if the agent actually selected "East" and if the table updated
    
    from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames
    
    final_img = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=4)
    all_images = frames + ([final_img] if final_img else [])

    if all_images and query_vlm:
        prompt = """
        You are verifying an Oracle Analytics Desktop task.
        The goal was to create a Dashboard with a 'Regional Sales Summary' (Bar Chart) and 'Order Details' (Table).
        Crucially, the user should have clicked the 'East' bar to filter the table.

        Look at the FINAL image (the last in the sequence) and the progression:
        1. Are there two visualizations (Bar Chart and Table)?
        2. Is the 'East' bar in the chart highlighted or selected?
        3. Does the table look filtered? (e.g., showing fewer rows than a full dataset, or specifically showing East-related cities/customers)?
        4. Do you see the 'Use as Filter' icon active (often a funnel shape)?

        Respond in JSON:
        {
            "two_visualizations_visible": true/false,
            "east_selected": true/false,
            "table_appears_filtered": true/false,
            "use_as_filter_icon_active": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_res = _vlm_query(query_vlm, prompt, images=all_images)
        
        if vlm_res:
            if vlm_res.get("two_visualizations_visible"):
                # If file check failed, we can give points here
                if score < (SCORE_FILE_EXISTS + SCORE_VISUALIZATIONS_CREATED):
                    score += SCORE_VISUALIZATIONS_CREATED
                    feedback_parts.append("Visualizations confirmed via screenshot.")

            if vlm_res.get("east_selected"):
                score += SCORE_SELECTION_STATE
                feedback_parts.append("'East' region selection confirmed.")
            else:
                feedback_parts.append("'East' region does not appear selected.")

            if vlm_res.get("table_appears_filtered"):
                score += SCORE_FILTERING_EFFECT
                feedback_parts.append("Table appears filtered correctly.")
            
            # Bonus points / fallback for interaction config if file check failed
            if vlm_res.get("use_as_filter_icon_active") and "Interactivity configuration detected" not in feedback_parts:
                score += SCORE_INTERACTIVITY_CONFIGURED
                feedback_parts.append("Filter interaction visual confirmed.")

    # Cap score at 100
    score = min(score, 100)
    
    # Pass logic: Needs file + visuals or strong visual evidence of completion
    passed = score >= 60 and ("Workbook saved successfully" in feedback_parts or "Visualizations confirmed via screenshot" in feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }