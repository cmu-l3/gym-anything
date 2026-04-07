#!/usr/bin/env python3
"""
Verifier for sample_return_eei_targeting@1

Scoring (total 100 pts, pass >= 75):
  - script_created (10): Script created during task window.
  - initial_state_correct (10): Initial state parameters (X, VX) match spec in the script.
  - targeting_structure (20): DifferentialCorrector / Target / Vary / Achieve logic present.
  - stopping_condition (15): Stopping condition (Altitude = 120) found in the script.
  - radper_achieved (20): Achieved RadPer is 6418.14 +/- 1.0 km (from report).
  - inc_achieved (15): Achieved INC is 45.0 +/- 0.1 deg (from report).
  - report_generated (10): Report file generated with Delta-V value.

Pass condition: score >= 75 AND targeting_structure AND radper_achieved.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sample_return_eei_targeting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Load result json
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

    scores = {
        "script_created": 10,
        "initial_state_correct": 10,
        "targeting_structure": 20,
        "stopping_condition": 15,
        "radper_achieved": 20,
        "inc_achieved": 15,
        "report_generated": 10
    }

    total_score = 0
    feedback = []
    targeting_ok = False
    radper_ok = False

    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    script_path = task_result.get('script_path', '/home/ga/Documents/missions/tcm4_targeting.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check initial state
            has_x = bool(re.search(r'X\s*=\s*280000\.0?', script_content))
            has_vx = bool(re.search(r'VX\s*=\s*-1\.8', script_content))
            if has_x and has_vx:
                total_score += scores["initial_state_correct"]
                feedback.append("Initial state parameters found in script.")
            else:
                feedback.append("Initial state parameters (X, VX) missing or incorrect in script.")

            # Check targeting structure
            if ("Target" in script_content and "Vary" in script_content and 
                "Achieve" in script_content and "EndTarget" in script_content):
                total_score += scores["targeting_structure"]
                targeting_ok = True
                feedback.append("Targeting structure (Target/Vary/Achieve/EndTarget) present.")
            else:
                feedback.append("Targeting structure incomplete.")

            # Check stopping condition
            if bool(re.search(r'Altitude\s*=\s*120\.0?', script_content)):
                total_score += scores["stopping_condition"]
                feedback.append("Stopping condition (Altitude = 120) found.")
            else:
                feedback.append("Stopping condition (Altitude = 120) not found.")
        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Script file does not exist.")

    # Check report file
    report_file = task_result.get('report_file', {})
    report_path = task_result.get('report_path', '/home/ga/GMAT_output/tcm4_targeting_results.txt')
    if isinstance(report_file, dict) and report_file.get('exists'):
        temp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_rpt.name)
            with open(temp_rpt.name, 'r', encoding='utf-8', errors='ignore') as f:
                rpt_content = f.read()

            radper_match = re.search(r'Achieved_RadPer_km:\s*([0-9]+\.?[0-9]*)', rpt_content)
            inc_match = re.search(r'Achieved_INC_deg:\s*([0-9]+\.?[0-9]*)', rpt_content)
            dv_match = re.search(r'Total_Required_DeltaV_mps:\s*([0-9]+\.?[0-9]*)', rpt_content)

            if dv_match:
                total_score += scores["report_generated"]
                feedback.append(f"Report contains Delta-V: {dv_match.group(1)}.")
            else:
                feedback.append("Report missing Total_Required_DeltaV_mps.")

            if radper_match:
                radper_val = float(radper_match.group(1))
                if abs(radper_val - 6418.14) <= 1.0:
                    total_score += scores["radper_achieved"]
                    radper_ok = True
                    feedback.append(f"Achieved RadPer is correct: {radper_val} km.")
                else:
                    feedback.append(f"Achieved RadPer is incorrect: {radper_val} km (expected ~6418.14).")
            else:
                feedback.append("Report missing Achieved_RadPer_km.")

            if inc_match:
                inc_val = float(inc_match.group(1))
                if abs(inc_val - 45.0) <= 0.1:
                    total_score += scores["inc_achieved"]
                    feedback.append(f"Achieved INC is correct: {inc_val} deg.")
                else:
                    feedback.append(f"Achieved INC is incorrect: {inc_val} deg (expected ~45.0).")
            else:
                feedback.append("Report missing Achieved_INC_deg.")
        except Exception as e:
            feedback.append(f"Error reading report: {e}")
        finally:
            if os.path.exists(temp_rpt.name):
                os.unlink(temp_rpt.name)
    else:
        feedback.append("Report file does not exist.")

    passed = (total_score >= 75) and targeting_ok and radper_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }