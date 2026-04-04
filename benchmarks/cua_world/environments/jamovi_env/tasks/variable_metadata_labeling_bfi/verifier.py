#!/usr/bin/env python3
"""
Verifier for variable_metadata_labeling_bfi task.

Verifies:
1. .omv file creation
2. Variable metadata inside the .omv file (Nominal type, specific labels)
3. Analysis existence (T-Test)
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_variable_metadata_labeling_bfi(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load basic result info
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic checks
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file BFI_Metadata.omv not found."}
    
    if not result.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task."}

    # Analyze OMV content
    score = 10  # Base score for saving file
    feedback = ["File saved."]
    
    # Copy OMV file
    omv_path = task_info.get('metadata', {}).get('expected_output_path', '/home/ga/Documents/Jamovi/BFI_Metadata.omv')
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
    try:
        copy_from_env(omv_path, temp_omv.name)
        
        # OMV is a ZIP file. Extract and inspect metadata.
        # Jamovi 1.x/2.x structure: 'metadata.json' or 'xdata.json' contains variable definitions
        # Analysis structure: folders like '01 ttestis'
        
        with zipfile.ZipFile(temp_omv.name, 'r') as z:
            namelist = z.namelist()
            
            # 1. Check for T-Test Analysis
            # Look for folder or file indicating ttestIS
            has_ttest = any('ttestIS' in name or 'ttestis' in name.lower() for name in namelist)
            
            # Also check the 'index.html' or 'analysis' definitions if possible, 
            # but folder existence is a strong proxy in Jamovi OMV structure.
            if has_ttest:
                score += 15
                feedback.append("T-Test analysis found.")
            else:
                feedback.append("T-Test analysis NOT found in project.")

            # 2. Check Variable Metadata
            # Usually in xdata.json or metadata.json
            meta_content = None
            if 'xdata.json' in namelist:
                with z.open('xdata.json') as f:
                    meta_content = json.load(f)
            elif 'metadata.json' in namelist:
                 with z.open('metadata.json') as f:
                    meta_content = json.load(f)
            
            if not meta_content:
                return {"passed": False, "score": score, "feedback": "Could not read Jamovi metadata from OMV file."}
            
            # Find dataset definitions
            # Structure varies slightly by version, but usually:
            # { "data": { "fields": [ ... ] } } or similar
            
            fields = []
            # Deep search for 'fields' list
            def find_fields(obj):
                if isinstance(obj, dict):
                    if 'fields' in obj and isinstance(obj['fields'], list):
                        return obj['fields']
                    for k, v in obj.items():
                        res = find_fields(v)
                        if res: return res
                return None

            fields = find_fields(meta_content)
            
            if not fields:
                # Fallback: sometimes fields are directly in a list under a key like 'variables'
                fields = meta_content.get('fields', [])

            if not fields:
                 return {"passed": False, "score": score, "feedback": "Could not locate variable definitions in metadata."}

            # Verify 'gender'
            gender_field = next((f for f in fields if f.get('name') == 'gender'), None)
            if gender_field:
                # Check Measure Type
                # Jamovi uses 'nominal', 'ordinal', 'continuous', 'id'
                mtype = gender_field.get('measureType', '').lower()
                if mtype == 'nominal':
                    score += 20
                    feedback.append("'gender' set to Nominal.")
                else:
                    feedback.append(f"'gender' is {mtype}, expected Nominal.")

                # Check Labels/Levels
                # Typically stored in 'levels' or similar
                # Format often: [ { "value": 1, "label": "Male" }, ... ]
                levels = gender_field.get('levels', [])
                
                # Normalize levels structure check
                # Sometimes it's a list of objects, sometimes simple values if no labels
                
                label_male_found = False
                label_female_found = False
                
                for lvl in levels:
                    # lvl might be { "value": 1, "label": "Male" }
                    if isinstance(lvl, dict):
                        val = str(lvl.get('value', ''))
                        lbl = lvl.get('label', '')
                        if val == '1' and lbl.lower() == 'male':
                            label_male_found = True
                        if val == '2' and lbl.lower() == 'female':
                            label_female_found = True
                
                if label_male_found:
                    score += 20
                    feedback.append("Label 'Male' applied.")
                else:
                    feedback.append("Label 'Male' for value 1 NOT found.")
                    
                if label_female_found:
                    score += 20
                    feedback.append("Label 'Female' applied.")
                else:
                    feedback.append("Label 'Female' for value 2 NOT found.")

            else:
                feedback.append("Variable 'gender' not found in dataset.")

            # Verify Continuous vars (A1-A5)
            continuous_vars = ['A1', 'A2', 'A3', 'A4', 'A5']
            correct_vars = 0
            for var_name in continuous_vars:
                f = next((f for f in fields if f.get('name') == var_name), None)
                if f and f.get('measureType', '').lower() == 'continuous':
                    correct_vars += 1
            
            if correct_vars == 5:
                score += 15
                feedback.append("All A1-A5 variables set to Continuous.")
            else:
                score += int((correct_vars / 5) * 15)
                feedback.append(f"{correct_vars}/5 variables (A1-A5) set to Continuous.")

    except Exception as e:
        logger.error(f"Error parsing OMV: {e}")
        return {"passed": False, "score": score, "feedback": f"Error verifying file content: {e}"}
    finally:
        if os.path.exists(temp_omv.name):
            os.unlink(temp_omv.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }