#!/usr/bin/env python3
"""
Verifier for fuel_cell_stability_spc task.

Verifies:
1. PBIX file creation and validity.
2. DAX Measure existence: Global_Mean_Voltage, UCL, LCL.
3. DAX Logic: Checks for 'ALL' or 'REMOVEFILTERS' keywords implies correct global context.
4. Visuals: Line chart presence with correct bindings.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_fuel_cell_stability(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence (15 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 15
        feedback.append("Report saved successfully.")
    elif result.get('file_exists'):
        score += 5
        feedback.append("Report exists but timestamp predates task (did you save?).")
    else:
        return {"passed": False, "score": 0, "feedback": "No report file found on Desktop."}

    # 2. Data Model Verification (40 pts)
    # We check the extracted strings from the DataModel binary
    dm_strings = result.get('datamodel_strings', '')
    
    required_measures = ['Global_Mean_Voltage', 'UCL', 'LCL']
    measures_found = 0
    
    for m in required_measures:
        # Check for measure name definition pattern (often appears as name in model)
        if m in dm_strings:
            measures_found += 1
    
    if measures_found == 3:
        score += 20
        feedback.append("All required measures (Mean, UCL, LCL) found in model.")
    elif measures_found > 0:
        score += 10
        feedback.append(f"Found {measures_found}/3 required measures.")
    else:
        feedback.append("No required measures found in data model.")

    # Check for DAX logic keywords for GLOBAL context
    # Looking for ALL( or REMOVEFILTERS( or ALLEXCEPT(
    # Note: Strings dump might separate function names, but usually logic is somewhat contiguous
    logic_keywords = ['ALL', 'REMOVEFILTERS', 'CALCULATE']
    logic_found = sum(1 for k in logic_keywords if k in dm_strings)
    
    if logic_found >= 2:
        score += 20
        feedback.append("Correct DAX patterns (CALCULATE/ALL) detected for global measures.")
    else:
        feedback.append("Warning: Could not confirm use of ALL/REMOVEFILTERS for global context.")

    # 3. Visualization Verification (45 pts)
    layout = result.get('layout_content', {})
    visuals_valid = False
    
    # Traverse layout structure
    # Sections -> VisualContainers -> Config -> SingleVisual -> visualType
    try:
        sections = layout.get('sections', [])
        for section in sections:
            # Check page name if possible, though strict naming isn't critical if visual is right
            page_name = section.get('displayName', '')
            
            visuals = section.get('visualContainers', [])
            for vis in visuals:
                config_str = vis.get('config', '{}')
                # Config is a JSON string inside the JSON object
                try:
                    config = json.loads(config_str)
                    single_vis = config.get('singleVisual', {})
                    vis_type = single_vis.get('visualType', '')
                    
                    if vis_type == 'lineChart':
                        # Check projections (data fields)
                        projections = single_vis.get('projections', {})
                        # We expect 'Category' (X) and 'Y' (Values)
                        y_axis = projections.get('Y', [])
                        
                        # We need at least 2 series (Voltage + Mean) or 4 (Voltage+Mean+UCL+LCL)
                        if len(y_axis) >= 3:
                            visuals_valid = True
                            score += 45
                            feedback.append("Line chart found with multiple data series (Voltage + Limits).")
                            break
                        elif len(y_axis) >= 1:
                            score += 20
                            feedback.append("Line chart found but missing some limit lines.")
                            visuals_valid = True # Partial credit
                except:
                    continue
            if visuals_valid: break
    except Exception as e:
        feedback.append(f"Error parsing report layout: {str(e)}")

    if not visuals_valid:
        feedback.append("No valid Control Chart (lineChart) found.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }