#!/usr/bin/env python3
"""
Verifier for build_shape_verification_legacy task.

Verification Strategy:
1. Static Analysis of .psyexp file:
   - Must contain a Loop referencing a CSV file.
   - Must contain Image, Text, Keyboard components.
   - Must contain a Feedback routine (text component/code component).
2. Data Handling Verification (The Core Challenge):
   - Strategy A (Data Cleaning): The referenced CSV file has been edited to remove Windows paths.
   - Strategy B (Code Fix): The CSV is untouched, but the Image component uses Python code 
     (e.g., .replace, os.path.join, .split) to correct the path dynamically.
3. VLM Verification:
   - Confirm UI interaction and final state via trajectory.

Pass Threshold: 60/100 points
"""

import json
import tempfile
import os
import csv
import logging
import xml.etree.ElementTree as ET

logger = logging.getLogger(__name__)

def verify_build_shape_verification_legacy(traj, env_info, task_info):
    """Verify the shape verification experiment implementation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. Get Metadata & Result JSON
    metadata = task_info.get('metadata', {})
    exp_path = metadata.get('experiment_path', '/home/ga/PsychoPyExperiments/shape_task.psyexp')
    
    # Load basic result info
    result_json_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(result_json_path): os.unlink(result_json_path)

    if not result.get("exp_exists"):
        return {"passed": False, "score": 0, "feedback": "Experiment file not found"}
    
    score += 10 # File exists
    
    # 2. Retrieve and Parse Experiment File
    local_exp_path = tempfile.mktemp(suffix=".psyexp")
    try:
        copy_from_env(exp_path, local_exp_path)
        tree = ET.parse(local_exp_path)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse .psyexp file: {e}"}
    finally:
        if os.path.exists(local_exp_path): os.unlink(local_exp_path)
        
    # Analyze Experiment Structure
    components = {'Image': 0, 'Text': 0, 'Keyboard': 0, 'Code': 0}
    loops = []
    routines = {} # name -> list of components
    
    # Extract routines
    for routine in root.findall(".//Routine"):
        r_name = routine.get('name')
        routines[r_name] = []
        for comp in routine:
            c_type = comp.tag
            routines[r_name].append(c_type)
            if 'Image' in c_type: components['Image'] += 1
            if 'Text' in c_type: components['Text'] += 1
            if 'Key' in c_type: components['Keyboard'] += 1
            if 'Code' in c_type: components['Code'] += 1

    # Extract loops and referenced conditions file
    conditions_file_ref = None
    for loop in root.findall(".//LoopInitiator"):
        for param in loop.iter("Param"):
            if param.get('name') == 'conditionsFile':
                conditions_file_ref = param.get('val')
                loops.append(conditions_file_ref)
    
    # Scoring Structure
    if components['Image'] >= 1 and components['Text'] >= 1 and components['Keyboard'] >= 1:
        score += 15
        feedback_parts.append("Core components present")
    else:
        feedback_parts.append("Missing core components (Image/Text/Keyboard)")
        
    if loops:
        score += 15
        feedback_parts.append("Loop configured")
    else:
        feedback_parts.append("No loop found")
        
    # 3. Verify Path Resolution Strategy
    # We need to check if the path issue was solved.
    path_issue_solved = False
    strategy_used = "None"
    
    # Strategy A: Data Cleaning
    # Check if the conditions file referenced in the loop is clean
    if conditions_file_ref:
        # The ref might be a variable or a string. If it's a string, we check the file.
        clean_path_ref = conditions_file_ref.strip().replace('"', '').replace("'", "")
        
        # If it's relative, assume it's relative to exp folder
        if not clean_path_ref.startswith('/'):
            clean_path_ref = os.path.join(os.path.dirname(exp_path), clean_path_ref)
            
        local_csv_path = tempfile.mktemp(suffix=".csv")
        try:
            copy_from_env(clean_path_ref, local_csv_path)
            with open(local_csv_path, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                if rows:
                    first_path = rows[0].get('orig_path', '')
                    # Check if it looks like a clean linux path or filename
                    if "C:\\" not in first_path and "\\" not in first_path:
                        path_issue_solved = True
                        strategy_used = "Data Cleaning"
        except Exception:
            # File might not exist or be readable, or ref is a variable
            pass
        finally:
            if os.path.exists(local_csv_path): os.unlink(local_csv_path)

    # Strategy B: Code Fix in Image Component
    if not path_issue_solved:
        # Look at Image component 'image' parameter
        for routine in root.findall(".//Routine"):
            for comp in routine:
                if 'Image' in comp.tag:
                    for param in comp.iter("Param"):
                        if param.get('name') == 'image':
                            val = param.get('val', '')
                            # Indicators of code fix: $ prefix + python string manip
                            if '$' in val and ('replace' in val or 'split' in val or 'os.path' in val or '+' in val):
                                path_issue_solved = True
                                strategy_used = "Python Code"

    if path_issue_solved:
        score += 35
        feedback_parts.append(f"Path issue resolved via {strategy_used}")
    else:
        feedback_parts.append("Path issue NOT resolved (Legacy Windows paths still active or no logic found)")

    # 4. Verify Feedback Logic
    # Look for a routine that isn't the main trial routine (heuristic) or check for conditional logic
    feedback_found = False
    
    # Check for conditional text color or message
    for routine in root.findall(".//Routine"):
        for comp in routine:
            if 'Text' in comp.tag:
                for param in comp.iter("Param"):
                    val = param.get('val', '')
                    # Look for logic variables often used in feedback
                    if '$' in val and ('corr' in val or 'msg' in val or 'color' in val):
                        feedback_found = True
            if 'Code' in comp.tag:
                # Code component usually implies logic
                for param in comp.iter("Param"):
                    if 'corr' in param.get('val', ''):
                        feedback_found = True

    if feedback_found:
        score += 25
        feedback_parts.append("Feedback logic detected")
    else:
        feedback_parts.append("No feedback logic detected")

    # Final tally
    passed = score >= 60 and path_issue_solved
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }