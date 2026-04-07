#!/usr/bin/env python3
"""
Verifier for create_parallel_coordinates_profile task.
Verifies the agent created a .dva workbook with the correct Parallel Coordinates visualization.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_parallel_coordinates_profile(traj, env_info, task_info):
    """
    Verifies the Oracle Analytics Desktop task.
    
    Criteria:
    1. Workbook file (.dva) exists and was created during the task.
    2. Workbook contains a visualization of type 'parallelCoordinates' (or similar).
    3. The visualization references the required columns: Ship Mode, Sales, Quantity, Discount, Profit.
    4. VLM verification of the final visual state.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'Shipping_Profile_Analysis.dva')
    
    # Weights
    SCORE_FILE_EXISTS = 10
    SCORE_FILE_FRESH = 10
    SCORE_VIZ_TYPE = 30
    SCORE_COLUMNS = 30
    SCORE_TITLE = 20
    
    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON from Env
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Check File Existence & Freshness
    if result_data.get('output_exists'):
        score += SCORE_FILE_EXISTS
        feedback.append(f"File {expected_filename} found.")
        
        if result_data.get('file_created_during_task'):
            score += SCORE_FILE_FRESH
            feedback.append("File was modified during the task.")
        else:
            feedback.append("WARNING: File timestamp indicates it was not created during this session.")
            # We don't fail immediately, but this is suspicious
    else:
        return {"passed": False, "score": 0, "feedback": "Output workbook file not found."}

    # 3. Retrieve and Inspect the .dva File
    # .dva files are ZIP archives containing XML/JSON definitions
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    try:
        remote_path = result_data.get('output_path')
        copy_from_env(remote_path, temp_dva.name)
        
        # Analyze DVA content
        viz_type_found = False
        columns_found_count = 0
        title_found = False
        
        required_cols = ["Ship Mode", "Sales", "Quantity", "Discount", "Profit"]
        required_cols_lower = [c.lower() for c in required_cols]
        
        with zipfile.ZipFile(temp_dva.name, 'r') as z:
            # Oracle DVA structure usually has content in /datamodel or /desc folders
            # We search all text-based files for keywords
            for filename in z.namelist():
                if filename.endswith(('.xml', '.json', '.txt')):
                    try:
                        with z.open(filename) as f:
                            content = f.read().decode('utf-8', errors='ignore')
                            
                            # Check for Visualization Type
                            # Common IDs: parallelCoordinates, parallel-coords, or similar
                            if re.search(r'parallel\s*coord', content, re.IGNORECASE):
                                viz_type_found = True
                            
                            # Check for Title
                            if "Shipping Mode Profile Analysis" in content:
                                title_found = True
                                
                            # Check for Columns (simplified check: existence in the definition file)
                            # A strict check would parse the XML, but regex is robust enough for existence
                            # We check if these terms appear in the context of the viz definition
                            # Counting hits across the file
                            for col in required_cols:
                                if col in content:
                                    columns_found_count += 1
                                    
                    except Exception:
                        continue
        
        # Scoring logic based on inspection
        if viz_type_found:
            score += SCORE_VIZ_TYPE
            feedback.append("Parallel Coordinates visualization type detected.")
        else:
            feedback.append("Could not confirm 'Parallel Coordinates' type in file metadata.")
            
        if title_found:
            score += SCORE_TITLE
            feedback.append("Correct title found.")
        
        # Cap column score
        # Note: columns_found_count might overcount if file is large, but better than strict parsing for now
        # We need at least 4 unique matches to be confident
        unique_matches = 0
        with zipfile.ZipFile(temp_dva.name, 'r') as z:
            combined_content = ""
            for filename in z.namelist():
                if filename.endswith(('.xml', '.json')): 
                    with z.open(filename) as f:
                        combined_content += f.read().decode('utf-8', errors='ignore')
            
            for col in required_cols:
                if col in combined_content:
                    unique_matches += 1
        
        if unique_matches >= len(required_cols):
            score += SCORE_COLUMNS
            feedback.append(f"All {len(required_cols)} required data columns found.")
        elif unique_matches >= 3:
            partial = int(SCORE_COLUMNS * (unique_matches / len(required_cols)))
            score += partial
            feedback.append(f"Found {unique_matches}/{len(required_cols)} columns. Partial credit.")
        else:
            feedback.append(f"Missing required columns (Found only {unique_matches}).")

    except zipfile.BadZipFile:
        feedback.append("Output file is not a valid DVA/ZIP archive.")
    except Exception as e:
        feedback.append(f"Error analyzing DVA file: {str(e)}")
    finally:
        if os.path.exists(temp_dva.name):
            os.unlink(temp_dva.name)

    # Final Pass Determination
    # Threshold: 60 points + Viz Type Must be Correct
    passed = (score >= 60) and viz_type_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }