#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import logging
import shutil
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_segment_comparison(traj, env_info, task_info):
    """
    Verifies the segment comparison task for Oracle Analytics Desktop.
    
    Strategy:
    1. Basic File Checks: .dva file created, timestamp correct, size > 0.
    2. Deep Content Inspection: Extract .dva (zip) and inspect metadata for calculated measures.
    3. Visual Verification: VLM checks chart title, type (grouped bar), and visible data.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filepath = metadata.get('expected_filepath', r"C:\Users\Docker\Documents\segment_comparison.dva")
    
    score = 0
    feedback_parts = []
    
    # Temporary directory for processing
    with tempfile.TemporaryDirectory() as temp_dir:
        result_json_path = os.path.join(temp_dir, "task_result.json")
        dva_local_path = os.path.join(temp_dir, "segment_comparison.dva")
        
        # 1. Fetch Result JSON
        try:
            # Note: Path must match export_result.ps1
            copy_from_env(r"C:\Users\Docker\AppData\Local\Temp\task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
            
        # 2. Check File Existence & Timestamp (20 points)
        if result_data.get("output_exists") and result_data.get("file_created_during_task"):
            score += 20
            feedback_parts.append("DVA file created successfully.")
            
            # 3. Fetch and Inspect DVA Content (40 points)
            try:
                copy_from_env(expected_filepath, dva_local_path)
                
                if zipfile.is_zipfile(dva_local_path):
                    found_corp_calc = False
                    found_cons_calc = False
                    found_case_logic = False
                    
                    with zipfile.ZipFile(dva_local_path, 'r') as z:
                        # Iterate through files to find XML/JSON definitions
                        # OAD .dva structure usually contains datamodel files
                        for filename in z.namelist():
                            try:
                                with z.open(filename) as f:
                                    content = f.read().decode('utf-8', errors='ignore')
                                    
                                    # Check for Calculation Names
                                    if "Corporate Revenue" in content:
                                        found_corp_calc = True
                                    if "Consumer Revenue" in content:
                                        found_cons_calc = True
                                        
                                    # Check for Logic (CASE WHEN)
                                    # Note: XML escapes might exist, e.g., CASE&quot;
                                    if "CASE" in content and "WHEN" in content:
                                        found_case_logic = True
                            except:
                                continue
                    
                    if found_corp_calc:
                        score += 15
                        feedback_parts.append("Found 'Corporate Revenue' calculation.")
                    if found_cons_calc:
                        score += 15
                        feedback_parts.append("Found 'Consumer Revenue' calculation.")
                    if found_case_logic:
                        score += 10
                        feedback_parts.append("Verified CASE WHEN logic usage.")
                else:
                    feedback_parts.append("Exported file is not a valid DVA package.")
            except Exception as e:
                feedback_parts.append(f"Failed to inspect DVA file content: {e}")
        else:
            feedback_parts.append("Result file not found or not created during task.")

    # 4. VLM Verification (40 points)
    # We use trajectory frames to ensure they actually used the UI
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    if final_img:
        frames.append(final_img)
        
    vlm_prompt = """
    You are verifying an Oracle Analytics Desktop task.
    Goal: Create two calculated measures ('Corporate Revenue', 'Consumer Revenue') and display them in a Grouped Bar Chart by Product Category.
    
    Examine the screenshots for:
    1. A Bar Chart that has 'Product Category' on the X-axis.
    2. Two distinct bars (different colors) for each category (Grouped/Clustered bars).
    3. The title 'Corporate vs Consumer Revenue by Product Category'.
    4. Evidence of the calculation editor being used (e.g., CASE WHEN formula).
    
    Output JSON:
    {
        "chart_visible": boolean,
        "is_grouped_bar": boolean,
        "title_correct": boolean,
        "calculation_editor_seen": boolean,
        "confidence": float (0-1)
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get('success'):
        analysis = vlm_result.get('parsed', {})
        if analysis.get('chart_visible'):
            score += 10
        if analysis.get('is_grouped_bar'):
            score += 10
        if analysis.get('title_correct'):
            score += 10
        if analysis.get('calculation_editor_seen'):
            score += 10
        
        feedback_parts.append(f"Visual verification: Chart={analysis.get('chart_visible')}, Grouped={analysis.get('is_grouped_bar')}")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }