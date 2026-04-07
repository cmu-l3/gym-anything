#!/usr/bin/env python3
"""
Verifier for configure_search_action task.

Verifies:
1. Workbook file (Product_Search_Tool.dva) exists and was saved.
2. The DVA file contains a Data Action definition with correct parameters (Google URL).
3. Trajectory analysis confirms the user accessed the Data Actions menu/context menu.
"""

import json
import os
import zipfile
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_search_action(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'Product_Search_Tool.dva')
    
    score = 0
    feedback = []
    
    # =========================================================
    # 1. Retrieve Task Result JSON
    # =========================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Workbook file not found. Did you save it as 'Product_Search_Tool'?"}
    
    score += 10
    feedback.append("Workbook file exists.")

    # =========================================================
    # 2. Inspect DVA File Content (Data Action Verification)
    # =========================================================
    dva_verified = False
    url_correct = False
    action_found = False
    
    if result_data.get('dva_file_available'):
        temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.zip') # DVA is a zip
        try:
            copy_from_env("/tmp/Product_Search_Tool.dva", temp_dva.name)
            
            with zipfile.ZipFile(temp_dva.name, 'r') as z:
                # Search for metadata files (usually JSON or XML in datamodel or root)
                # We scan all text files for the Data Action signature
                file_list = z.namelist()
                content_found = ""
                
                for filename in file_list:
                    if filename.endswith('.json') or filename.endswith('.xml'):
                        try:
                            with z.open(filename) as f:
                                content = f.read().decode('utf-8', errors='ignore')
                                # Look for Data Action patterns
                                if "Search Product" in content:
                                    content_found += content
                        except:
                            continue

                if "Search Product" in content_found:
                    action_found = True
                    score += 30
                    feedback.append("Data Action 'Search Product' found in workbook metadata.")
                    
                    # Check for URL configuration
                    # Pattern look for google.com and parameter binding
                    if "google.com" in content_found and "Product Name" in content_found:
                        url_correct = True
                        score += 30 # High weight for correct logic
                        feedback.append("Data Action URL correctly configured with Google and Product Name parameter.")
                    else:
                        feedback.append("Data Action found but URL or Parameter seems incorrect.")
                else:
                    feedback.append("Could not find 'Search Product' action in workbook metadata.")

        except Exception as e:
            feedback.append(f"Error inspecting DVA file: {str(e)}")
        finally:
            if os.path.exists(temp_dva.name):
                os.unlink(temp_dva.name)
    else:
        feedback.append("DVA file could not be retrieved for inspection.")

    # =========================================================
    # 3. VLM Trajectory Verification
    # =========================================================
    # We want to see if they opened the Data Actions dialog or Context Menu
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user using Oracle Analytics Desktop.
    The goal was to create a table and add a "Search Product" Data Action (right-click menu option).
    
    Look for:
    1. A Table visualization showing Product names.
    2. The "Data Actions" dialog box being open.
    3. A context menu (right-click menu) showing "Search Product".
    4. Any indication of URL configuration (google.com).
    
    Output JSON:
    {
        "table_visible": true/false,
        "data_actions_dialog_seen": true/false,
        "context_menu_action_seen": true/false,
        "reasoning": "..."
    }
    """
    
    try:
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('table_visible'):
            score += 10
            feedback.append("Table visualization confirmed visually.")
            
        if parsed.get('data_actions_dialog_seen') or parsed.get('context_menu_action_seen'):
            score += 20
            feedback.append("Visual confirmation of Data Action configuration/usage.")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if programmatic check passed, we are good.
        if url_correct:
            score += 20 # Give benefit of doubt if file is perfect
            feedback.append("VLM skipped, but file verification passed.")

    # =========================================================
    # Final Scoring
    # =========================================================
    passed = score >= 70 and action_found
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }