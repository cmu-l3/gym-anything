#!/usr/bin/env python3
"""
Verifier for define_blade_structural_props task.
"""

import json
import tempfile
import os
import re

def verify_blade_structural_props(traj, env_info, task_info):
    """
    Verifies that the agent created a QBlade project with specific structural properties.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    target_mass = metadata.get('target_mass_kg', 212.5)
    mass_tolerance = metadata.get('mass_tolerance', 2.5)
    
    # 1. Get JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Files Created (20 pts) ---
    if result.get('project_exists') and result.get('report_exists'):
        score += 20
        feedback_parts.append("Project and report files created")
    elif result.get('project_exists'):
        score += 10
        feedback_parts.append("Project file created, but report missing")
    else:
        feedback_parts.append("Project file missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Anti-Gaming (Timestamp) (10 pts) ---
    if result.get('files_created_during_task'):
        score += 10
        feedback_parts.append("Files created during task session")
    else:
        feedback_parts.append("Files appear to be old (pre-dating task)")
        # Severe penalty for anti-gaming violation
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 3: Reported Mass Accuracy (30 pts) ---
    reported_mass_str = result.get('reported_mass', "")
    try:
        reported_mass = float(reported_mass_str)
        if abs(reported_mass - target_mass) <= mass_tolerance:
            score += 30
            feedback_parts.append(f"Reported mass {reported_mass} kg is correct (Target: {target_mass})")
        else:
            feedback_parts.append(f"Reported mass {reported_mass} kg is incorrect (Expected ~{target_mass})")
    except ValueError:
        feedback_parts.append("Could not parse numeric mass from report file")

    # --- Criterion 4: Project Content Verification (40 pts) ---
    # We need to analyze the WPA file. QBlade .wpa files are typically XML or text-based.
    temp_wpa = tempfile.NamedTemporaryFile(delete=False, suffix='.wpa')
    project_valid = False
    
    try:
        copy_from_env(result['project_path'], temp_wpa.name)
        with open(temp_wpa.name, 'r', errors='ignore') as f:
            content = f.read()
            
        # Check for Blade Name
        if "StructBlade10" in content:
            score += 5
            feedback_parts.append("Blade name 'StructBlade10' found")
            project_valid = True
        else:
            feedback_parts.append("Blade name 'StructBlade10' not found in project")

        # Check for Structural Values
        # The WPA format varies, but usually stores values in plain text.
        # We look for the specific mass/stiffness numbers in proximity or existence.
        # Values: Mass=[40, 20, 5], Stiffness=[10000000, 5000000, 1000000]
        # Stiffness 1e7 might be stored as 10000000 or 1.000000e+07
        
        found_masses = 0
        if "40" in content and "20" in content and "5" in content:
             # Weak check, but better than nothing without a full XML parser
             found_masses = 1 
        
        # More robust check: Look for specific XML tags if QBlade uses them, 
        # or just high confidence string matching for the large numbers
        found_stiffness = 0
        if "10000000" in content or "1.000000e+07" in content:
            found_stiffness += 1
        if "5000000" in content or "5.000000e+06" in content:
            found_stiffness += 1
        
        if project_valid:
            if found_masses:
                score += 15
                feedback_parts.append("Mass distribution values found")
            else:
                feedback_parts.append("Mass values not clearly identified in project file")
                
            if found_stiffness >= 2:
                score += 20
                feedback_parts.append("Stiffness distribution values found")
            else:
                feedback_parts.append("Stiffness values incomplete/missing in project file")

    except Exception as e:
        feedback_parts.append(f"Failed to analyze project file content: {e}")
    finally:
        if os.path.exists(temp_wpa.name):
            os.unlink(temp_wpa.name)

    # --- Pass Threshold ---
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }