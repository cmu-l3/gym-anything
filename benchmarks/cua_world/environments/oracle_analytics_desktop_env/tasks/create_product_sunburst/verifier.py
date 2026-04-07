#!/usr/bin/env python3
"""
Verifier for create_product_sunburst task.

Verification Strategy:
1. File Verification (Primary):
   - Check if Product_Hierarchy.dva exists and was created during the task.
   - Inspect internal XML/JSON of the .dva (it's a zip) to confirm:
     - Visualization type is 'sunburst'.
     - Hierarchical columns (Category, Sub Category) are present.
     - Metrics (Sales, Profit) are mapped correctly (Size, Color).
     - Filter excludes 'Office Supplies'.

2. VLM Verification (Secondary):
   - Analyze trajectory to ensure proper workflow (drag-and-drop actions).
   - Analyze final screenshot to verify:
     - Sunburst chart shape (radial).
     - Two distinct rings (hierarchy).
     - Absence of 'Office Supplies' (visual check of legend/labels).

"""

import json
import os
import tempfile
import zipfile
import logging
import shutil
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_product_sunburst(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Retrieve Result Data
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy result JSON: {e}")
        result_data = {}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic checks
    output_exists = result_data.get('output_exists', False)
    file_created = result_data.get('file_created_during_task', False)
    
    score = 0
    feedback_parts = []
    
    if output_exists:
        score += 10
        feedback_parts.append("Workbook file saved")
        if file_created:
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("File timestamp indicates old file (not created now)")
    else:
        feedback_parts.append("Workbook file 'Product_Hierarchy.dva' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ================================================================
    # 2. Inspect DVA File Content (Deep Verification)
    # ================================================================
    dva_valid = False
    chart_config_correct = False
    filter_correct = False
    
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    extract_dir = tempfile.mkdtemp()
    
    try:
        # Copy .dva file
        remote_path = result_data.get('output_path', r"C:\Users\Docker\Documents\Product_Hierarchy.dva")
        # Handle Windows path separation in copy_from_env if needed, usually string literal works
        copy_from_env(remote_path, temp_dva.name)
        
        # Unzip DVA
        with zipfile.ZipFile(temp_dva.name, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
            dva_valid = True
            
        # Inspect DataModel or Visualization XML/JSON
        # Structure varies by version, usually looking for datamodel/ or similar
        # We search for keywords in all text files if structure is unknown
        
        found_sunburst = False
        found_sales = False
        found_profit = False
        found_hierarchy = False
        found_filter = False
        
        for root, dirs, files in os.walk(extract_dir):
            for file in files:
                if file.endswith(('.xml', '.json', '.js')):
                    path = os.path.join(root, file)
                    try:
                        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                            content = f.read().lower()
                            
                            # Check chart type
                            if 'sunburst' in content or 'radialtree' in content:
                                found_sunburst = True
                                
                            # Check Metrics
                            if 'sales' in content and 'profit' in content:
                                found_sales = True
                                found_profit = True
                                
                            # Check Hierarchy columns
                            if 'product category' in content and 'product sub category' in content:
                                found_hierarchy = True
                                
                            # Check Filter (Exclusion of Office Supplies)
                            # Logic: might see "Office Supplies" in a suppression/filter list
                            if 'office supplies' in content and ('filter' in content or 'exclude' in content or 'notIn' in content):
                                found_filter = True
                    except:
                        pass
        
        if found_sunburst:
            score += 20
            feedback_parts.append("Verified Sunburst chart type in metadata")
        else:
            feedback_parts.append("Could not verify Sunburst chart type in metadata")

        if found_sales and found_profit:
            score += 20
            feedback_parts.append("Verified Sales and Profit metrics")
        
        if found_hierarchy:
            score += 10
            feedback_parts.append("Verified Hierarchy columns")
            
        if found_filter:
            score += 10
            feedback_parts.append("Verified 'Office Supplies' exclusion filter")
        else:
            feedback_parts.append("Could not verify filter in metadata (checking visual)")

    except Exception as e:
        logger.error(f"DVA inspection failed: {e}")
        feedback_parts.append("Failed to inspect workbook metadata")
    finally:
        if os.path.exists(temp_dva.name):
            os.unlink(temp_dva.name)
        shutil.rmtree(extract_dir, ignore_errors=True)

    # ================================================================
    # 3. VLM Verification (Visual Check)
    # ================================================================
    
    # Get Final Screenshot
    final_screenshot = get_final_screenshot(traj)
    
    # Get Trajectory Frames
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying an Oracle Analytics Desktop task.
    Goal: Create a Sunburst chart (radial hierarchy) showing Sales and Profit, EXCLUDING 'Office Supplies'.
    
    Analyze the final screenshot and trajectory:
    1. Is there a Sunburst chart visible? (Circular/Radial chart with concentric rings)
    2. Does the chart have 2 rings? (Inner for Category, Outer for Sub-Category)
    3. Are there different colors? (Indicating Profit metric)
    4. Are there distinct sector sizes? (Indicating Sales metric)
    5. FILTER CHECK: Look at the legend or the chart labels. Do you see 'Office Supplies'? 
       - If you see ONLY 'Technology' and 'Furniture' (or similar), the filter is CORRECT.
       - If you see 'Office Supplies', the filter is MISSING.
    
    Respond in JSON:
    {
        "sunburst_visible": true/false,
        "two_rings_visible": true/false,
        "office_supplies_present": true/false,
        "title_visible": true/false
    }
    """
    
    vlm_result = query_vlm(
        prompt=vlm_prompt,
        images=frames + [final_screenshot] if final_screenshot else frames
    )
    
    vlm_passed = False
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('sunburst_visible'):
            score += 10 # Extra visual confirmation
            if not found_sunburst: # If metadata failed, give credit here
                score += 10 
            feedback_parts.append("Visual confirmation of Sunburst chart")
            
        if parsed.get('two_rings_visible'):
            score += 5
            
        if not parsed.get('office_supplies_present'):
            score += 5
            if not found_filter: # If metadata failed
                score += 10
            feedback_parts.append("Visual confirmation: Office Supplies excluded")
        else:
            feedback_parts.append("Visual check failed: Office Supplies still visible")
            
        vlm_passed = True

    # Final Score Calc
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }