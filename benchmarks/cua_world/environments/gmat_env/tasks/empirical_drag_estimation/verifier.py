#!/usr/bin/env python3
"""
Verifier for empirical_drag_estimation@1

Evaluates if the agent successfully used GMAT's DifferentialCorrector to solve for
the drag coefficient (Cd) that matches a 30-day SMA decay profile.

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script was created and saved
  - spacecraft_configured (15): DryMass, DragArea, and initial SMA set correctly
  - drag_configured (15): JacchiaRoberts atmosphere and F107=150 configured
  - dc_logic_present (20): Target, Vary (Cd), and Achieve (SMA) used in script
  - result_file_exists (10): estimated_cd.txt exists
  - cd_value_reasonable (10): Extracted Cd is mathematically plausible [1.5, 4.0]
  - cd_value_accurate (20): Extracted Cd is within ±0.15 of the true simulation (~2.65)

Pass Condition: score >= 60 AND dc_logic_present AND cd_value_reasonable
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_empirical_drag_estimation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_cd = metadata.get('target_cd_value', 2.65)
    cd_tol = metadata.get('cd_tolerance', 0.15)

    scores = {
        "script_created": 10,
        "spacecraft_configured": 15,
        "drag_configured": 15,
        "dc_logic_present": 20,
        "result_file_exists": 10,
        "cd_value_reasonable": 10,
        "cd_value_accurate": 20,
    }

    total_score = 0
    feedback = []
    dc_logic_ok = False
    cd_value_ok = False

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

    # 1. Check script exists
    if task_result.get('script_exists') and task_result.get('script_created_during_task'):
        total_score += scores["script_created"]
        feedback.append("GMAT script created successfully.")
    else:
        feedback.append("GMAT script missing or not created during task.")

    # 2. Analyze script content (Physics configuration)
    script_content = ""
    if task_result.get('script_exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env("/tmp/agent_script.script", temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Spacecraft configuration check
            has_mass = bool(re.search(r'DryMass\s*=\s*1430', script_content))
            has_area = bool(re.search(r'DragArea\s*=\s*10\.5', script_content))
            has_sma = bool(re.search(r'SMA\s*=\s*6760', script_content))

            if has_mass and has_area and has_sma:
                total_score += scores["spacecraft_configured"]
                feedback.append("Spacecraft physical properties configured correctly.")
            elif has_mass or has_area or has_sma:
                total_score += scores["spacecraft_configured"] // 2
                feedback.append("Spacecraft properties partially configured.")
            else:
                feedback.append("Spacecraft physics properties missing.")

            # Atmosphere configuration check
            has_atm = bool(re.search(r'AtmosphereModel\s*=\s*JacchiaRoberts', script_content))
            has_f107 = bool(re.search(r'F107\s*=\s*150', script_content))

            if has_atm and has_f107:
                total_score += scores["drag_configured"]
                feedback.append("JacchiaRoberts atmosphere and solar flux configured.")
            elif has_atm or has_f107:
                total_score += scores["drag_configured"] // 2
                feedback.append("Drag model partially configured.")
            else:
                feedback.append("Drag model not properly configured.")

            # DC Logic check
            has_target = "Target" in script_content
            has_vary = bool(re.search(r'Vary\s+.*Cd', script_content, re.IGNORECASE))
            has_achieve = bool(re.search(r'Achieve\s+.*SMA', script_content, re.IGNORECASE))
            
            if has_target and has_vary and has_achieve:
                total_score += scores["dc_logic_present"]
                dc_logic_ok = True
                feedback.append("Differential Corrector targeting logic (Vary Cd, Achieve SMA) is present.")
            else:
                feedback.append("Missing required DC logic elements (Target/Vary/Achieve).")

        except Exception as e:
            logger.warning(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Check result file and CD value
    if task_result.get('result_file_exists'):
        total_score += scores["result_file_exists"]
        
        # Extract Cd value from the content
        content = task_result.get('cd_file_content', '')
        # Match any floating point number or integer
        matches = re.findall(r'([0-9]+\.[0-9]+|[0-9]+)', content)
        
        extracted_cd = None
        if matches:
            try:
                # Get the last number found if there are multiple, or just the first
                # Usually it's just a single number if they followed instructions
                extracted_cd = float(matches[0])
            except ValueError:
                pass

        if extracted_cd is not None:
            if 1.5 <= extracted_cd <= 4.0:
                total_score += scores["cd_value_reasonable"]
                cd_value_ok = True
                feedback.append(f"Reasonable Cd value extracted: {extracted_cd}")
                
                # Accuracy check
                if abs(extracted_cd - target_cd) <= cd_tol:
                    total_score += scores["cd_value_accurate"]
                    feedback.append(f"Cd value is highly accurate (within tolerance of {target_cd}).")
                else:
                    feedback.append(f"Cd value is outside strict accuracy tolerance ({target_cd} ± {cd_tol}).")
            else:
                feedback.append(f"Extracted Cd value ({extracted_cd}) is not physically plausible for this body.")
        else:
            feedback.append("Result file exists but no numeric Cd value could be parsed.")
    else:
        feedback.append("Result file estimated_cd.txt was not found.")

    # Determine pass/fail
    key_criteria_met = dc_logic_ok and cd_value_ok
    passed = (total_score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }