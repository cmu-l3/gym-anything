#!/usr/bin/env python3
"""
Verifier for create_radar_seasonality task in Oracle Analytics Desktop.

Criteria:
1. 'Seasonality_Analysis.dva' file exists (20 pts)
2. File was created/modified during task execution (10 pts)
3. Internal DVA structure contains 'radar' visualization type (30 pts)
4. Internal DVA structure references 'Order Date'/'Month' and 'Revenue' (20 pts)
5. VLM Trajectory Verification: Visible Radar chart on screen (20 pts)
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

def verify_create_radar_seasonality(traj, env_info, task_info):
    """
    Verifies the Radar Chart task by inspecting the .dva file structure 
    and using VLM for visual confirmation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Get JSON Result from Container
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Windows path inside container usually mapped to local path or accessed via copy
        # The export script saved to C:\tmp\task_result.json
        # Docker copy usually handles the OS path conversion if configured correctly
        copy_from_env("C:\\tmp\\task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 2. Evaluate File Existence & Timestamp
    if result_data.get("output_exists"):
        score += 20
        feedback_parts.append("Workbook file 'Seasonality_Analysis.dva' found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    if result_data.get("file_created_during_task"):
        score += 10
        feedback_parts.append("File saved during task session.")
    else:
        feedback_parts.append("Warning: File timestamp indicates it wasn't saved during this session.")

    # 3. Inspect DVA Content (Deep Verification)
    # .dva files are ZIPs. We need to copy the .dva out and inspect it.
    dva_path = result_data.get("output_path", "C:\\Users\\Docker\\Documents\\Seasonality_Analysis.dva")
    local_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    
    try:
        copy_from_env(dva_path, local_dva.name)
        
        with zipfile.ZipFile(local_dva.name, 'r') as z:
            # List files to find relevant XML/JSON definitions
            # Structure typically includes datamodel or visualization XMLs
            content_files = z.namelist()
            
            # Search for visualization definitions (usually in xml files)
            found_radar = False
            found_revenue = False
            found_month = False
            found_category = False
            
            # Iterate through text-based files in the archive
            for filename in content_files:
                if filename.endswith('.xml') or filename.endswith('.json') or filename.endswith('.txt'):
                    try:
                        with z.open(filename) as f:
                            content = f.read().decode('utf-8', errors='ignore')
                            
                            # Check for Visualization Type
                            # Oracle Analytics internal ID for radar might be 'radar', 'spider', 'polar'
                            # or 'plugin:radar'
                            if re.search(r'radar|spider|polar', content, re.IGNORECASE):
                                found_radar = True
                            
                            # Check for Columns
                            if re.search(r'Revenue|Sales', content, re.IGNORECASE):
                                found_revenue = True
                            if re.search(r'Month|Order Date', content, re.IGNORECASE):
                                found_month = True
                            if re.search(r'Product Category', content, re.IGNORECASE):
                                found_category = True
                    except Exception:
                        continue

            if found_radar:
                score += 30
                feedback_parts.append("Internal metadata confirms Radar/Spider visualization type.")
            else:
                feedback_parts.append("Could not confirm Radar visualization type in file metadata.")
                
            if found_revenue and found_month:
                score += 20
                feedback_parts.append("Internal metadata confirms required data columns (Revenue, Month).")
            else:
                feedback_parts.append("Missing required data columns in metadata.")

    except Exception as e:
        logger.error(f"Failed to inspect DVA content: {e}")
        feedback_parts.append(f"Failed to inspect workbook content: {e}")
    finally:
        if os.path.exists(local_dva.name):
            os.unlink(local_dva.name)

    # 4. VLM Verification (Visual Confirmation)
    # Check trajectory for visual evidence of the chart
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    vlm_prompt = """
    Analyze these screenshots from Oracle Analytics Desktop.
    I am looking for a specific chart type: A Radar Chart (also called Spider Chart or Web Chart).
    It looks like a polygon or web with axes radiating from a center point.
    
    1. Do you see a Radar/Spider chart in any screenshot?
    2. Are there multiple colored lines/shapes (indicating categories)?
    3. Can you see date/month labels around the outside?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result.get('success'):
        # Heuristic: if VLM is confident, award points
        # Using a keyword check on the reasoning if structured parsing isn't available
        response_text = vlm_result.get('parsed', {}).get('response', '') or str(vlm_result)
        
        if "yes" in response_text.lower() and ("radar" in response_text.lower() or "spider" in response_text.lower()):
            score += 20
            feedback_parts.append("VLM confirms visual presence of Radar chart.")
        else:
            feedback_parts.append("VLM did not clearly identify a Radar chart.")
    else:
        feedback_parts.append("VLM verification skipped/failed.")

    passed = score >= 80  # Strict threshold requiring correct file type + visual or metadata confirmation

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }