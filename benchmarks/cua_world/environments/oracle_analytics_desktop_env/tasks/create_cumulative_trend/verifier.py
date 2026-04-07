#!/usr/bin/env python3
"""
Verifier for Create Cumulative Trend task in Oracle Analytics Desktop.

Verifies:
1. Workbook file (.dva) exists and was created during the task.
2. Workbook content (XML/JSON inside ZIP) contains "RSUM" (Running Sum) calculation.
3. Visualization uses "Month" granularity and "Product Category".
4. VLM verifies visual appearance (monotonic lines).
"""

import json
import os
import zipfile
import tempfile
import shutil
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_dva_content(dva_path):
    """
    Inspects the .dva file (ZIP archive) for specific Oracle Analytics artifacts.
    Returns a dict of found features.
    """
    findings = {
        "has_rsum": False,
        "has_product_category": False,
        "has_month": False,
        "valid_structure": False
    }
    
    try:
        if not zipfile.is_zipfile(dva_path):
            return findings
            
        with zipfile.ZipFile(dva_path, 'r') as z:
            # DVA files usually contain maindatamodel.xml or similar JSON/XML definitions
            # We look for any text file containing the logic
            file_list = z.namelist()
            findings["valid_structure"] = True
            
            for filename in file_list:
                if filename.endswith('.xml') or filename.endswith('.json') or filename.endswith('.js'):
                    try:
                        with z.open(filename) as f:
                            content = f.read().decode('utf-8', errors='ignore')
                            
                            # Check for Running Sum (RSUM is the function code)
                            if 'RSUM' in content or 'running sum' in content.lower():
                                findings["has_rsum"] = True
                                
                            # Check dimensions
                            if 'Product Category' in content:
                                findings["has_product_category"] = True
                                
                            # Check granularity
                            if 'Month' in content or 'MONTH' in content:
                                findings["has_month"] = True
                    except Exception:
                        continue
                        
    except Exception as e:
        logger.error(f"Error inspecting DVA file: {e}")
        
    return findings

def verify_create_cumulative_trend(traj, env_info, task_info):
    """
    Main verification function.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result_data.get('output_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Workbook file not found. Did you save it as 'Cumulative_Growth_Analysis.dva'?"}

    score += 10 # File exists
    feedback_parts.append("Workbook saved.")

    if created_during:
        score += 10 # Fresh file
    else:
        feedback_parts.append("Warning: File timestamp indicates it wasn't modified during this session.")

    # 2. Retrieve and Inspect DVA File
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.dva')
    dva_findings = {}
    try:
        copy_from_env(result_data.get('file_path'), temp_dva.name)
        dva_findings = check_dva_content(temp_dva.name)
    except Exception as e:
        feedback_parts.append(f"Failed to inspect workbook content: {e}")
    finally:
        if os.path.exists(temp_dva.name):
            os.unlink(temp_dva.name)

    # Scoring based on findings
    if dva_findings.get("has_rsum"):
        score += 40
        feedback_parts.append("Running Sum calculation detected.")
    else:
        feedback_parts.append("Running Sum calculation NOT detected in workbook.")

    if dva_findings.get("has_product_category"):
        score += 10
        feedback_parts.append("Product Category dimension detected.")

    if dva_findings.get("has_month"):
        score += 10
        feedback_parts.append("Month granularity detected.")

    # 3. VLM Verification
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots from Oracle Analytics Desktop.
    The user is attempting to create a Cumulative Revenue Growth chart.
    
    Check for:
    1. A Line Chart visualization.
    2. Multiple lines of different colors (indicating Product Categories).
    3. The lines are strictly INCREASING over time (Monotonic). 
       - Normal sales charts go up and down.
       - Cumulative/Running Sum charts only go up (or stay flat).
    4. X-axis shows monthly dates.
    
    Does the final result look like a cumulative trend chart?
    """
    
    vlm_result = query_vlm(
        prompt=vlm_prompt,
        images=frames + [final_screen] if final_screen else frames
    )
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        # Simple keyword heuristic on VLM analysis if structural parsing isn't available
        analysis = vlm_result.get('answer', '').lower() + str(vlm_result.get('parsed', '')).lower()
        
        if "increasing" in analysis or "cumulative" in analysis or "upward" in analysis:
            vlm_score += 10
            feedback_parts.append("Visuals confirm cumulative trend.")
        if "line" in analysis and "color" in analysis:
            vlm_score += 10
            
    score += vlm_score

    # Final Pass Check
    # Must have RSUM (programmatic) OR (VLM confirms strictly increasing AND file exists)
    # Programmatic RSUM check is the gold standard here.
    passed = (score >= 70) and (dva_findings.get("has_rsum") or vlm_score >= 15)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }