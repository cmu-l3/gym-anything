#!/usr/bin/env python3
"""
Verifier for repeat_groundtrack_design@1

Evaluates if the agent successfully designed a repeat ground track orbit based
on the provided mission requirements (16-day / 233-revolution repeat, sun-sync).

Scoring Breakdown (100 points max, Pass threshold: 60):
  - script_created: 8
  - spacecraft_defined: 7
  - sma_correct: 20
  - inc_correct: 20
  - ecc_valid: 5
  - force_model_adequate: 8
  - propagation_16days: 7
  - report_written: 10
  - longitude_drift_valid: 10
  - raan_rate_valid: 5

Pass condition: score >= 60 AND sma_correct AND inc_correct.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_repeat_groundtrack_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    sma_min = metadata.get('sma_min_km', 7070.0)
    sma_max = metadata.get('sma_max_km', 7100.0)
    inc_min = metadata.get('inc_min_deg', 98.0)
    inc_max = metadata.get('inc_max_deg', 98.5)
    ecc_max = metadata.get('ecc_max', 0.002)
    drift_max = metadata.get('max_longitude_drift_deg', 2.0)
    raan_rate_min = metadata.get('min_raan_rate_degperday', 0.93)
    raan_rate_max = metadata.get('max_raan_rate_degperday', 1.04)

    scores = {
        "script_created": 8,
        "spacecraft_defined": 7,
        "sma_correct": 20,
        "inc_correct": 20,
        "ecc_valid": 5,
        "force_model_adequate": 8,
        "propagation_16days": 7,
        "report_written": 10,
        "longitude_drift_valid": 10,
        "raan_rate_valid": 5,
    }

    total_score = 0
    feedback = []
    
    # Track critical items
    sma_ok = False
    inc_ok = False

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

    # 1. Script Creation
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Parse GMAT Script
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/earthmapper3_orbit.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Spacecraft check
            if re.search(r'Create\s+Spacecraft', script_content, re.IGNORECASE):
                total_score += scores["spacecraft_defined"]
                feedback.append("Spacecraft defined in script.")
            else:
                feedback.append("No Spacecraft definition found in script.")

            # Extract SMA
            sma_match = re.search(r'\.SMA\s*=\s*([0-9.]+)', script_content, re.IGNORECASE)
            if sma_match:
                sma_val = float(sma_match.group(1))
                if sma_min <= sma_val <= sma_max:
                    total_score += scores["sma_correct"]
                    sma_ok = True
                    feedback.append(f"SMA valid: {sma_val} km.")
                else:
                    feedback.append(f"SMA invalid: {sma_val} km (Expected {sma_min}-{sma_max}).")
            else:
                feedback.append("SMA not found in script.")

            # Extract INC
            inc_match = re.search(r'\.INC\s*=\s*([0-9.]+)', script_content, re.IGNORECASE)
            if inc_match:
                inc_val = float(inc_match.group(1))
                if inc_min <= inc_val <= inc_max:
                    total_score += scores["inc_correct"]
                    inc_ok = True
                    feedback.append(f"INC valid: {inc_val} deg.")
                else:
                    feedback.append(f"INC invalid: {inc_val} deg (Expected {inc_min}-{inc_max}).")
            else:
                feedback.append("INC not found in script.")

            # Extract ECC
            ecc_match = re.search(r'\.ECC\s*=\s*([0-9.]+)', script_content, re.IGNORECASE)
            if ecc_match:
                ecc_val = float(ecc_match.group(1))
                if 0.0 <= ecc_val <= ecc_max:
                    total_score += scores["ecc_valid"]
                    feedback.append(f"ECC valid: {ecc_val}.")
                else:
                    feedback.append(f"ECC invalid: {ecc_val} (Expected <= {ecc_max}).")
            else:
                feedback.append("ECC not found in script.")

            # Force model check
            drag_present = bool(re.search(r'\.Drag\.', script_content, re.IGNORECASE) or re.search(r'AtmosphereModel', script_content, re.IGNORECASE))
            gravity_deg = 0
            deg_match = re.search(r'\.Degree\s*=\s*([0-9]+)', script_content, re.IGNORECASE)
            if deg_match:
                gravity_deg = int(deg_match.group(1))
            
            if drag_present and gravity_deg >= 2:
                total_score += scores["force_model_adequate"]
                feedback.append(f"Force model adequate (Drag included, Gravity Degree={gravity_deg}).")
            else:
                feedback.append(f"Force model inadequate. Drag present: {drag_present}, Gravity Degree: {gravity_deg}.")

            # Propagation duration check
            days_match = re.search(r'\.ElapsedDays\s*=\s*([0-9.]+)', script_content, re.IGNORECASE)
            secs_match = re.search(r'\.ElapsedSecs\s*=\s*([0-9.]+)', script_content, re.IGNORECASE)
            if (days_match and float(days_match.group(1)) == 16) or (secs_match and float(secs_match.group(1)) == 1382400):
                total_score += scores["propagation_16days"]
                feedback.append("Propagation configured for 16 days.")
            elif re.search(r'233', script_content):  # 233 revolutions backup check
                total_score += scores["propagation_16days"]
                feedback.append("Propagation configured for 233 revolutions (~16 days).")
            else:
                feedback.append("Propagation duration does not equal 16 days.")

        except Exception as e:
            feedback.append(f"Error parsing script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("GMAT script file not found.")

    # 3. Parse Results Report
    results_file = task_result.get('results_file', {})
    results_path = task_result.get('results_path', '/home/ga/GMAT_output/groundtrack_design_results.txt')
    
    if isinstance(results_file, dict) and results_file.get('exists'):
        total_score += scores["report_written"]
        feedback.append("Results report file found.")
        
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(results_path, temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()

            # Parse longitude drift
            drift_match = re.search(r'longitude_drift_deg:\s*([0-9.\-]+)', report_content, re.IGNORECASE)
            if drift_match:
                drift_val = abs(float(drift_match.group(1)))
                if drift_val <= drift_max:
                    total_score += scores["longitude_drift_valid"]
                    feedback.append(f"Longitude drift valid: {drift_val} deg (<= {drift_max}).")
                else:
                    feedback.append(f"Longitude drift too high: {drift_val} deg.")
            else:
                feedback.append("longitude_drift_deg not found in report.")

            # Parse RAAN rate
            raan_match = re.search(r'sun_sync_RAAN_rate_degperday:\s*([0-9.\-]+)', report_content, re.IGNORECASE)
            if raan_match:
                raan_val = float(raan_match.group(1))
                if raan_rate_min <= raan_val <= raan_rate_max:
                    total_score += scores["raan_rate_valid"]
                    feedback.append(f"RAAN rate valid: {raan_val} deg/day.")
                else:
                    feedback.append(f"RAAN rate invalid: {raan_val} deg/day (Expected {raan_rate_min}-{raan_rate_max}).")
            else:
                feedback.append("sun_sync_RAAN_rate_degperday not found in report.")

        except Exception as e:
            feedback.append(f"Error parsing report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback.append("Results report file not found.")

    # Final Pass Evaluation
    passed = (total_score >= 60) and sma_ok and inc_ok
    
    if not passed and total_score >= 60:
        feedback.append("FAILED: Met score threshold, but missed critical SMA or INC values.")
        
    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback)
    }