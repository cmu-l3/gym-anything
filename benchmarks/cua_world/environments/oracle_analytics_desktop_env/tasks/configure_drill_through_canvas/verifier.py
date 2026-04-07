#!/usr/bin/env python3
"""
Verifier for configure_drill_through_canvas task in Oracle Analytics Desktop.

Verifies:
1. Workbook creation and saving (.dva file)
2. Existence of two canvases (Summary, Details)
3. Configuration of Data Action (Drill to Details)
4. Visualization types and columns
5. VLM confirmation of workflow
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_drill_through_canvas(traj, env_info, task_info):
    """
    Verify the OAD drill-through task using file inspection and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_action = metadata.get('expected_action_name', 'Drill to Details')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # --------------------------------------------------------------------------
    # 1. Retrieve Task Result JSON
    # --------------------------------------------------------------------------
    task_result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task result metadata"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic checks
    if task_result.get('output_exists'):
        score += 10
        feedback_parts.append("Workbook file saved")
    else:
        return {"passed": False, "score": 0, "feedback": "Workbook 'Drill_Through_Analysis.dva' not found"}

    if task_result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File saved during task session")
    else:
        feedback_parts.append("File timestamp indicates it wasn't saved during this session")

    # --------------------------------------------------------------------------
    # 2. Inspect Workbook Content (Unzip .dva)
    # --------------------------------------------------------------------------
    # .dva files are ZIP archives containing JSON/XML definitions of the project
    dva_content_valid = False
    action_found = False
    canvases_found = []
    
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.dva')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\Drill_Through_Analysis.dva", temp_dva.name)
        
        if zipfile.is_zipfile(temp_dva.name):
            with zipfile.ZipFile(temp_dva.name, 'r') as z:
                # Search for main project definition files
                # OAD structure usually has a datamodel or search for JSONs
                file_list = z.namelist()
                
                # Read text content to find keywords (robust against specific internal path changes)
                content_text = ""
                for filename in file_list:
                    if filename.endswith('.json') or filename.endswith('.xml'):
                        try:
                            with z.open(filename) as f:
                                content_text += f.read().decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check for Data Action
                if expected_action in content_text:
                    action_found = True
                    score += 30
                    feedback_parts.append(f"Data Action '{expected_action}' configuration found in workbook")
                
                # Check for Canvases
                if "Summary" in content_text:
                    canvases_found.append("Summary")
                if "Details" in content_text:
                    canvases_found.append("Details")
                
                if len(canvases_found) == 2:
                    score += 20
                    feedback_parts.append("Both 'Summary' and 'Details' canvases found")
                elif len(canvases_found) == 1:
                    score += 10
                    feedback_parts.append(f"Only '{canvases_found[0]}' canvas found")
                
                dva_content_valid = True
        else:
            feedback_parts.append("Saved file is not a valid OAD workbook (invalid zip)")
            
    except Exception as e:
        logger.error(f"Failed to inspect DVA file: {e}")
        feedback_parts.append(f"Error inspecting workbook file: {str(e)}")
    finally:
        if os.path.exists(temp_dva.name):
            os.unlink(temp_dva.name)

    # --------------------------------------------------------------------------
    # 3. VLM Verification (Trajectory Analysis)
    # --------------------------------------------------------------------------
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    all_images = frames + ([final_img] if final_img else [])

    if all_images:
        prompt = """
        Review these screenshots of a user working in Oracle Analytics Desktop.
        Target Workflow:
        1. Create a Bar Chart on a 'Summary' canvas.
        2. Create a Table on a 'Details' canvas.
        3. Create a 'Data Action' or 'Drill' interaction to link them.
        4. Use the drill (context menu -> Drill to Details).
        
        Answer the following in JSON:
        {
            "summary_chart_seen": boolean,
            "details_table_seen": boolean,
            "data_action_menu_seen": boolean (Did you see a context menu with 'Drill to Details' or similar?),
            "final_view_filtered": boolean (Does the final view look like a filtered list/table?),
            "confidence": 0-10
        }
        """
        
        try:
            vlm_res = query_vlm(images=all_images, prompt=prompt)
            if vlm_res and 'result' in vlm_res:
                # Parse JSON from result if needed, assuming query_vlm returns dict or string
                # This depends on the specific VLM interface helper provided in env
                # We'll assume vlm_res is the dictionary response
                parsed = json.loads(vlm_res['result']) if isinstance(vlm_res['result'], str) else vlm_res['result']
                
                vlm_score = 0
                if parsed.get('summary_chart_seen'): vlm_score += 5
                if parsed.get('details_table_seen'): vlm_score += 5
                if parsed.get('data_action_menu_seen'): vlm_score += 10
                if parsed.get('final_view_filtered'): vlm_score += 10
                
                score += vlm_score
                feedback_parts.append(f"VLM Analysis: {vlm_score}/30 points")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # If VLM fails, we rely on file checks, but we can't give full points
            feedback_parts.append("VLM verification skipped (system error)")

    # --------------------------------------------------------------------------
    # Final Scoring
    # --------------------------------------------------------------------------
    # Max possible without VLM: 70
    # Max possible with VLM: 100
    
    passed = score >= 70 and action_found and dva_content_valid
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }