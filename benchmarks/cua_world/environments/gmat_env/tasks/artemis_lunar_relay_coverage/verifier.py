#!/usr/bin/env python3
"""
Verifier for artemis_lunar_relay_coverage@1

The agent must design a highly elliptical lunar orbit with a 12-hour period,
centered on the Moon, and evaluate its contact time with a lunar ground station.

Scoring (total 100 pts, pass >= 70):
  - script_created (10): Script was created during the task window.
  - spacecraft_lunar_centric (10): The script configures the Spacecraft's CentralBody as Luna.
  - groundstation_lunar (15): A GroundStation is present and centered on Luna.
  - contact_locator_present (15): A ContactLocator is configured linking SC and GroundStation.
  - summary_file_created (10): The summary text file is properly formatted.
  - sma_correct (15): Computed SMA is within 5 km of 6144.46 km.
  - inc_ecc_correct (10): ECC (0.6) and INC (85.0) are correct in the report.
  - contact_time_valid (15): The reported max continuous contact is between 8.0 and 10.5 hours.

Pass condition: Score >= 70 AND sma_correct AND contact_time_valid.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_artemis_lunar_relay(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_sma = metadata.get('expected_sma_km', 6144.46)
    sma_tol = metadata.get('sma_tolerance_km', 5.0)
    expected_ecc = metadata.get('expected_ecc', 0.60)
    expected_inc = metadata.get('expected_inc_deg', 85.0)
    contact_min = metadata.get('contact_hours_min', 8.0)
    contact_max = metadata.get('contact_hours_max', 10.5)

    scores = {
        "script_created": 10,
        "spacecraft_lunar_centric": 10,
        "groundstation_lunar": 15,
        "contact_locator_present": 15,
        "summary_file_created": 10,
        "sma_correct": 15,
        "inc_ecc_correct": 10,
        "contact_time_valid": 15,
    }

    total_score = 0
    feedback = []
    sma_ok = False
    contact_ok = False

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
        feedback.append("Script not created or not modified during task window.")

    # 2. Summary file created
    summary_file = task_result.get('summary_file', {})
    if isinstance(summary_file, dict) and summary_file.get('created_during_task'):
        total_score += scores["summary_file_created"]
        feedback.append("Summary file created during task window.")
    else:
        feedback.append("Summary file not created during task window.")

    # 3. Read summary fields
    try:
        sma_val = float(task_result.get('summary_sma', 0))
    except (ValueError, TypeError):
        sma_val = 0.0

    try:
        ecc_val = float(task_result.get('summary_ecc', 0))
    except (ValueError, TypeError):
        ecc_val = 0.0

    try:
        inc_val = float(task_result.get('summary_inc', 0))
    except (ValueError, TypeError):
        inc_val = 0.0

    try:
        contact_val = float(task_result.get('summary_contact', 0))
    except (ValueError, TypeError):
        contact_val = 0.0

    # 4. Check SMA Correctness
    if abs(sma_val - expected_sma) <= sma_tol:
        total_score += scores["sma_correct"]
        sma_ok = True
        feedback.append(f"SMA correct: {sma_val:.2f} km (expected ~{expected_sma:.2f} km).")
    else:
        feedback.append(f"SMA incorrect: {sma_val:.2f} km (expected ~{expected_sma:.2f} km).")

    # 5. Check INC and ECC Correctness
    if abs(ecc_val - expected_ecc) <= 0.001 and abs(inc_val - expected_inc) <= 0.1:
        total_score += scores["inc_ecc_correct"]
        feedback.append(f"ECC and INC values match requirements.")
    else:
        feedback.append(f"ECC or INC values incorrect. Got ECC: {ecc_val}, INC: {inc_val}.")

    # 6. Check Contact Time
    if contact_min <= contact_val <= contact_max:
        total_score += scores["contact_time_valid"]
        contact_ok = True
        feedback.append(f"Contact time realistic: {contact_val:.2f} hours.")
    else:
        feedback.append(f"Contact time unrealistic or incorrect: {contact_val:.2f} hours (expected {contact_min}-{contact_max} hrs).")

    # 7. Deep Analysis of the GMAT Script
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/artemis_relay.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()
                
            # Check Spacecraft CentralBody
            if re.search(r'Create\s+Spacecraft', script_content) and re.search(r'\.\s*CoordinateSystem\s*=\s*\w+Luna\w*', script_content, re.IGNORECASE) or re.search(r'\w+\.CentralBody\s*=\s*Luna', script_content, re.IGNORECASE):
                total_score += scores["spacecraft_lunar_centric"]
                feedback.append("Spacecraft configured with Lunar CentralBody/CoordinateSystem.")
            else:
                feedback.append("Spacecraft not correctly configured for Lunar orbit.")

            # Check GroundStation CentralBody
            if re.search(r'Create\s+GroundStation', script_content):
                # Look for CentralBody = Luna within GroundStation defs
                if re.search(r'\w+\.CentralBody\s*=\s*Luna', script_content, re.IGNORECASE):
                    total_score += scores["groundstation_lunar"]
                    feedback.append("GroundStation is Lunar-centric.")
                else:
                    feedback.append("GroundStation present but not centered on Luna.")
            else:
                feedback.append("No GroundStation found in the script.")

            # Check ContactLocator
            if re.search(r'Create\s+ContactLocator', script_content):
                total_score += scores["contact_locator_present"]
                feedback.append("ContactLocator found in the script.")
            else:
                feedback.append("ContactLocator not found in the script.")

        except Exception as e:
            feedback.append(f"Failed to read/parse script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    passed = (total_score >= 70) and sma_ok and contact_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }