#!/usr/bin/env python3
"""
Verifier for blend_sales_targets task in Oracle Analytics Desktop.

Verification Strategy:
1. File-based: Validate .dva file exists, was created during task, and is a valid ZIP (DVA format).
2. Content-based: Inspect DVA internal XMLs for "Regional_Targets" dataset and "Region"/"Target" fields.
3. VLM-based: Verify trajectory shows data blending UI (Data Diagram) and final chart with comparison.

Scoring:
- DVA File exists and created during task: 20 pts
- DVA contains correct data sources (internal inspection): 30 pts
- VLM Trajectory (Process - Blending/Joining): 25 pts
- VLM Visual (Final Chart - Comparison): 25 pts
"""

import json
import os
import zipfile
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_blend_sales_targets(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define score components
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON and DVA File
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.zip') # DVA is a zip
    
    try:
        # Get JSON
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        # Get DVA File if it exists
        dva_path = result_data.get('dva_path', "C:\\Users\\Docker\\Documents\\Regional_Performance.dva")
        if result_data.get('output_exists'):
            try:
                copy_from_env(dva_path, temp_dva.name)
                dva_downloaded = True
            except Exception as e:
                dva_downloaded = False
                logger.warning(f"Could not download DVA file: {e}")
        else:
            dva_downloaded = False

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    # --- CRITERION 1: File Existence & Timestamp (20 pts) ---
    if result_data.get('output_exists'):
        if result_data.get('file_created_during_task'):
            score += 20
            feedback_parts.append("Workbook saved successfully during task.")
        else:
            score += 5
            feedback_parts.append("Workbook exists but timestamp indicates it wasn't modified during this session.")
    else:
        feedback_parts.append("Workbook 'Regional_Performance.dva' not found.")

    # --- CRITERION 2: DVA Content Inspection (30 pts) ---
    # We check if the DVA contains reference to 'Regional_Targets' inside its internal structure
    content_verified = False
    if dva_downloaded:
        try:
            with zipfile.ZipFile(temp_dva.name, 'r') as z:
                # DVA structure is complex, but we can search for strings in XML/JSON files
                file_list = z.namelist()
                found_target_source = False
                found_blending = False
                
                # Iterate through internal files (usually in /datamodel or /connections)
                for filename in file_list:
                    if filename.endswith('.xml') or filename.endswith('.json'):
                        try:
                            with z.open(filename) as f:
                                content = f.read().decode('utf-8', errors='ignore')
                                # Check for the CSV filename or dataset name
                                if "Regional_Targets" in content:
                                    found_target_source = True
                                # Check for Region and Target fields being used together
                                if "Region" in content and "Target" in content:
                                    found_blending = True
                        except:
                            continue
                
                if found_target_source:
                    score += 15
                    feedback_parts.append("Internal metadata confirms 'Regional_Targets' data source.")
                else:
                    feedback_parts.append("Could not find 'Regional_Targets' in workbook metadata.")

                if found_blending:
                    score += 15
                    content_verified = True
                    feedback_parts.append("Internal metadata confirms usage of Region and Target fields.")
        except zipfile.BadZipFile:
            feedback_parts.append("Saved file is not a valid DVA/ZIP archive.")
        finally:
            if os.path.exists(temp_dva.name): os.unlink(temp_dva.name)

    # --- CRITERION 3: VLM Process Verification (25 pts) ---
    # Did the agent show the Data Diagram / Join screen?
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        process_prompt = """
        Review these screenshots of a user working in Oracle Analytics Desktop.
        I am looking for evidence of 'Data Blending' or 'Joining'.
        
        Look for:
        1. A 'Data Diagram' view showing two bubbles/nodes connected by a line (representing a join).
        2. A 'Join' configuration dialog matching columns (e.g., Region = Region).
        3. The user uploading or selecting 'Regional_Targets.csv'.
        
        Answer JSON:
        {
            "data_blending_seen": true/false,
            "csv_upload_seen": true/false,
            "description": "what you see"
        }
        """
        process_result = query_vlm(images=frames, prompt=process_prompt)
        if process_result and process_result.get('parsed', {}).get('data_blending_seen'):
            score += 25
            feedback_parts.append("Visual evidence of data blending/joining workflow.")
        elif process_result and process_result.get('parsed', {}).get('csv_upload_seen'):
            score += 15
            feedback_parts.append("Visual evidence of CSV upload, but join step unclear.")
        else:
            feedback_parts.append("No visual evidence of data blending workflow.")

    # --- CRITERION 4: VLM Final Result Verification (25 pts) ---
    # Does the chart show comparison?
    final_img = get_final_screenshot(traj)
    if final_img:
        visual_prompt = """
        Analyze the chart in this screenshot.
        The goal is a 'Actual vs Target' comparison by Region.
        
        Check for:
        1. A chart (Bar, Combo, or Line) with 'Region' (Central, East, South, West) on one axis.
        2. TWO measures being displayed (e.g., 'Revenue' AND 'Target'). This often looks like paired bars, or a bar + line.
        3. The values should be in the millions (e.g., 5M, 8M).
        
        Answer JSON:
        {
            "chart_visible": true/false,
            "comparison_visible": true/false,
            "regions_visible": true/false
        }
        """
        visual_result = query_vlm(image=final_img, prompt=visual_prompt)
        parsed_vis = visual_result.get('parsed', {}) if visual_result else {}
        
        if parsed_vis.get('comparison_visible'):
            score += 25
            feedback_parts.append("Final chart clearly shows comparison of two measures.")
        elif parsed_vis.get('chart_visible'):
            score += 10
            feedback_parts.append("Chart created, but comparison of Revenue vs Target is not clearly visible.")
        else:
            feedback_parts.append("No valid visualization found in final screen.")

    # Final logic
    passed = score >= 70 and content_verified
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }