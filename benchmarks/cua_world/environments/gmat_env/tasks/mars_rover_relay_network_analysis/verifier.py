#!/usr/bin/env python3
"""
Verifier for mars_rover_relay_network_analysis@1

The agent must create a Mars-centered mission using GroundStation and ContactLocator,
then determine total relay minutes for two orbiters (MRO and MAVEN).

Scoring (total 100 pts, pass >= 65):
  - script_created (10): Script exists at target path
  - mars_coord_sys (15): Script defines and uses a Mars-centered coordinate system
  - rover_defined (10): GroundStation defined with Mars CentralBody
  - orbiters_defined (15): MRO and MAVEN defined with correct Mars-centric SMA
  - locators_configured (10): ContactLocators defined
  - report_exists (10): relay_summary.txt exists and created during task
  - mro_time_valid (10): mro_total_minutes is physically realistic (~120 mins)
  - maven_time_valid (10): maven_total_minutes is physically realistic (~850+ mins)
  - conclusion_correct (10): primary_relay correctly identifies MAVEN

Pass threshold: >= 65 points AND mars_coord_sys AND conclusion_correct.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mars_rover_relay_network(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    mro_min = metadata.get('mro_expected_min', 30.0)
    mro_max = metadata.get('mro_expected_max', 400.0)
    maven_min = metadata.get('maven_expected_min', 400.0)
    maven_max = metadata.get('maven_expected_max', 6000.0)
    primary_expected = metadata.get('primary_relay_expected', 'MAVEN').upper()

    scores = {
        "script_created": 10,
        "mars_coord_sys": 15,
        "rover_defined": 10,
        "orbiters_defined": 15,
        "locators_configured": 10,
        "report_exists": 10,
        "mro_time_valid": 10,
        "maven_time_valid": 10,
        "conclusion_correct": 10,
    }

    total_score = 0
    feedback = []
    
    # Critical pass flags
    mars_coord_ok = False
    conclusion_ok = False

    # Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # Parse script content for structural checks
    script_path = task_result.get('script_path')
    script_content = ""
    if script_path and isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()
            
            # 2. Check for Mars Coordinate System
            # Must contain "Create CoordinateSystem" and "Origin = Mars" or "CentralBody = Mars"
            has_coord_sys = bool(re.search(r'Create\s+CoordinateSystem', script_content))
            has_mars_origin = bool(re.search(r'\.(Origin|CentralBody)\s*=\s*Mars', script_content, re.IGNORECASE))
            if has_coord_sys and has_mars_origin:
                total_score += scores["mars_coord_sys"]
                mars_coord_ok = True
                feedback.append("Mars-centered CoordinateSystem defined.")
            else:
                feedback.append("Mars-centered CoordinateSystem not properly defined.")

            # 3. Check for Rover (GroundStation)
            has_gs = bool(re.search(r'Create\s+GroundStation', script_content))
            has_mars_gs = bool(re.search(r'\w+\.CentralBody\s*=\s*Mars', script_content, re.IGNORECASE))
            if has_gs and has_mars_gs:
                total_score += scores["rover_defined"]
                feedback.append("GroundStation (rover) defined on Mars.")
            elif has_gs:
                total_score += scores["rover_defined"] // 2
                feedback.append("GroundStation defined but CentralBody not explicitly set to Mars.")
            else:
                feedback.append("GroundStation not found.")

            # 4. Check for Orbiters (SMAs ~3676 and ~6050)
            has_mro_sma = bool(re.search(r'SMA\s*=\s*3676', script_content))
            has_maven_sma = bool(re.search(r'SMA\s*=\s*6050', script_content))
            if has_mro_sma and has_maven_sma:
                total_score += scores["orbiters_defined"]
                feedback.append("Both MRO and MAVEN defined with correct SMAs.")
            elif has_mro_sma or has_maven_sma:
                total_score += scores["orbiters_defined"] // 2
                feedback.append("Only one orbiter correctly defined by SMA.")
            else:
                feedback.append("Correct SMAs for MRO/MAVEN not found.")

            # 5. Check for ContactLocators
            if bool(re.search(r'Create\s+ContactLocator', script_content)):
                total_score += scores["locators_configured"]
                feedback.append("ContactLocator(s) configured.")
            else:
                feedback.append("ContactLocator missing.")
                
        except Exception as e:
            feedback.append(f"Failed to read script file: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Script file not found for content analysis.")

    # 6. Report exists
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('created_during_task'):
        total_score += scores["report_exists"]
        feedback.append("Analysis report generated.")
    else:
        feedback.append("Analysis report not generated.")

    # 7 & 8. Validate computed minutes
    try:
        mro_val = float(task_result.get('mro_total_minutes', 0))
    except (ValueError, TypeError):
        mro_val = 0.0

    try:
        maven_val = float(task_result.get('maven_total_minutes', 0))
    except (ValueError, TypeError):
        maven_val = 0.0

    if mro_min <= mro_val <= mro_max:
        total_score += scores["mro_time_valid"]
        feedback.append(f"MRO time valid: {mro_val} mins.")
    else:
        feedback.append(f"MRO time invalid/missing: {mro_val} mins (expected {mro_min}-{mro_max}).")

    if maven_min <= maven_val <= maven_max:
        total_score += scores["maven_time_valid"]
        feedback.append(f"MAVEN time valid: {maven_val} mins.")
    else:
        feedback.append(f"MAVEN time invalid/missing: {maven_val} mins (expected {maven_min}-{maven_max}).")

    # 9. Conclusion correct
    primary_relay = str(task_result.get('primary_relay', '')).strip().upper()
    if primary_relay == primary_expected:
        total_score += scores["conclusion_correct"]
        conclusion_ok = True
        feedback.append(f"Primary relay correctly identified as {primary_expected}.")
    else:
        feedback.append(f"Primary relay incorrect: '{primary_relay}' (expected '{primary_expected}').")

    # Final Pass Evaluation
    passed = (total_score >= 65) and mars_coord_ok and conclusion_ok

    if passed:
        feedback.insert(0, "SUCCESS: All key criteria met.")
    else:
        feedback.insert(0, "FAILED: Did not meet minimum score or missed critical requirements (mars_coord_sys, conclusion_correct).")

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }