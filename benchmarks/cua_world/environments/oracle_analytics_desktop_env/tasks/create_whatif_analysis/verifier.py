#!/usr/bin/env python3
"""
Verifier for create_whatif_analysis task in Oracle Analytics Desktop.

Verifies:
1. 'Discount_Simulation.dva' exists and was created during the task.
2. The DVA file (ZIP) contains definitions for:
   - A Parameter named 'Discount_Rate' (default 10)
   - A Calculation named 'Simulated Revenue' involving the parameter
3. VLM verification of the Table visualization showing the comparison.
"""

import json
import os
import zipfile
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_whatif_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'Discount_Simulation.dva')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path C:\tmp\task_result.json maps to the container path used by copy_from_env
        # We assume copy_from_env handles the abstraction or we use the posix path if mounted via docker
        # Typically for Windows containers, copy_from_env might need the absolute path inside the guest.
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (30 points)
    if result.get('output_exists'):
        score += 15
        feedback_parts.append("Workbook file saved.")
        if result.get('file_created_during_task'):
            score += 15
            feedback_parts.append("File created during task session.")
        else:
            feedback_parts.append("Warning: File timestamp indicates it was not created during this session.")
    else:
        feedback_parts.append("Expected workbook file not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # 3. Inspect DVA Content (40 points)
    # Copy the actual .dva file for inspection
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.dva')
    dva_path = result.get('output_path', 'C:\\Users\\Docker\\Documents\\Discount_Simulation.dva')
    
    try:
        copy_from_env(dva_path, temp_dva.name)
        
        # DVA is a ZIP file. We search its text content for keywords.
        # We don't need to parse perfect XML, just ensure the definitions exist.
        param_found = False
        calc_found = False
        default_val_found = False
        
        if zipfile.is_zipfile(temp_dva.name):
            with zipfile.ZipFile(temp_dva.name, 'r') as z:
                # Iterate through all XML/JSON files in the archive
                for filename in z.namelist():
                    if filename.endswith('.xml') or filename.endswith('.json') or filename.endswith('.txt'):
                        try:
                            content = z.read(filename).decode('utf-8', errors='ignore')
                            
                            # Check for Parameter definition
                            if "Discount_Rate" in content:
                                param_found = True
                                # Loose check for default value 10 near the parameter
                                if "10" in content and ("default" in content.lower() or "value" in content.lower()):
                                    default_val_found = True
                            
                            # Check for Calculation logic
                            if "Simulated Revenue" in content:
                                # Check if formula involves subtraction/multiplication logic roughly matching
                                # sales * (1 - discount/100)
                                if "Sales" in content and "*" in content and "-" in content:
                                    calc_found = True
                        except:
                            continue
        
        if param_found:
            score += 15
            feedback_parts.append("Parameter 'Discount_Rate' found in metadata.")
        else:
            feedback_parts.append("Parameter 'Discount_Rate' NOT found in workbook metadata.")
            
        if calc_found:
            score += 15
            feedback_parts.append("Calculation 'Simulated Revenue' found in metadata.")
        else:
            feedback_parts.append("Calculation logic missing or malformed.")

        if default_val_found:
            score += 10
            feedback_parts.append("Parameter default value seems correct (10).")
            
    except Exception as e:
        feedback_parts.append(f"Failed to inspect workbook content: {str(e)}")
    finally:
        if os.path.exists(temp_dva.name):
            os.unlink(temp_dva.name)

    # 4. VLM Verification (30 points)
    # Check visual evidence of the Table and Values
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        vlm_prompt = """
        You are verifying an Oracle Analytics Desktop task.
        Goal: Create a table showing 'Product Category', 'Sales', and 'Simulated Revenue'.
        Simulated Revenue should be a calculation based on a parameter (Discount_Rate = 10), so the values in 'Simulated Revenue' must be approximately 10% lower than 'Sales'.
        
        Look at the final screenshot:
        1. Is there a Table visualization?
        2. Are there columns for Sales and Simulated Revenue?
        3. Do the values in Simulated Revenue look smaller than Sales? (e.g., if Sales is 1000, Simulated should be ~900).
        4. Is there a parameter control visible (optional but good)?
        
        Answer with JSON: {"table_visible": bool, "columns_correct": bool, "values_logic_correct": bool, "feedback": str}
        """
        
        vlm_result = query_vlm(prompt=vlm_prompt, image=final_screenshot)
        
        if vlm_result and vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            if parsed.get('table_visible'):
                score += 10
            if parsed.get('columns_correct'):
                score += 10
            if parsed.get('values_logic_correct'):
                score += 10
            feedback_parts.append(f"VLM Analysis: {parsed.get('feedback', 'Visuals checked.')}")
        else:
            feedback_parts.append("VLM verification failed to process image.")
            # Fallback: if file checks passed, give partial credit for VLM to avoid zeroing out valid work due to VLM error
            if score >= 60:
                score += 10
                feedback_parts.append("Awarding fallback points for VLM due to technical error.")

    # Final logic
    passed = score >= 70 and param_found and calc_found
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }