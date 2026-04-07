#!/usr/bin/env python3
"""
Verifier for broken_leo_mission_diagnosis@1

Scoring (total 100 pts, pass >= 60):
  - script_modified (10): Script was modified during task window
  - sma_corrected (20): SMA corrected to 550 km altitude range [6880, 6970] km
  - ecc_corrected (15): ECC corrected to near-circular [0.0, 0.015]
  - inc_corrected (25): INC corrected to sun-sync range [97.0, 99.5] deg
  - drag_area_corrected (15): DragArea corrected to realistic range [1.0, 100.0] m^2
  - report_written (10): Diagnosis report written with required fields
  - orbit_propagated (5): GMAT orbit report generated (propagation ran)

Pass condition: score >= 60 AND inc_corrected AND sma_corrected
(INC is the most physically critical parameter for sun-synchronous operation)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_broken_leo_mission_diagnosis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    sma_min = metadata.get('sma_min_km', 6880.0)
    sma_max = metadata.get('sma_max_km', 6970.0)
    ecc_max = metadata.get('ecc_max', 0.015)
    inc_min = metadata.get('inc_min_deg', 97.0)
    inc_max = metadata.get('inc_max_deg', 99.5)
    drag_min = metadata.get('drag_area_min_m2', 1.0)
    drag_max = metadata.get('drag_area_max_m2', 100.0)

    scores = {
        "script_modified": 10,
        "sma_corrected": 20,
        "ecc_corrected": 15,
        "inc_corrected": 25,
        "drag_area_corrected": 15,
        "report_written": 10,
        "orbit_propagated": 5,
    }

    total_score = 0
    feedback = []
    inc_ok = False
    sma_ok = False

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

    # 1. Check script was modified during task window
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_modified"]
        feedback.append("Script modified during task window.")
    else:
        feedback.append("Script not modified (or modification not during task window).")

    # 2. Parse script values from export
    # The export already extracted SMA, ECC, INC, DragArea from the script
    try:
        sma_val = float(task_result.get('script_sma', 0))
    except (ValueError, TypeError):
        sma_val = 0.0

    try:
        ecc_val = float(task_result.get('script_ecc', 1.0))
    except (ValueError, TypeError):
        ecc_val = 1.0

    try:
        inc_val = float(task_result.get('script_inc', 0))
    except (ValueError, TypeError):
        inc_val = 0.0

    # DragArea may use scientific notation (e.g., 0.0001 or 1e-4)
    try:
        drag_val = float(task_result.get('script_drag_area', 0))
    except (ValueError, TypeError):
        drag_val = 0.0

    # 3. Check SMA
    if sma_min <= sma_val <= sma_max:
        total_score += scores["sma_corrected"]
        sma_ok = True
        feedback.append(f"SMA corrected: {sma_val:.2f} km (valid range {sma_min}-{sma_max} km).")
    else:
        feedback.append(f"SMA not corrected: {sma_val:.2f} km (expected {sma_min}-{sma_max} km).")

    # 4. Check ECC
    if 0.0 <= ecc_val <= ecc_max:
        total_score += scores["ecc_corrected"]
        feedback.append(f"ECC corrected: {ecc_val:.5f} (near-circular).")
    else:
        feedback.append(f"ECC not corrected: {ecc_val:.5f} (expected <= {ecc_max}).")

    # 5. Check INC (most critical)
    if inc_min <= inc_val <= inc_max:
        total_score += scores["inc_corrected"]
        inc_ok = True
        feedback.append(f"INC corrected to sun-synchronous: {inc_val:.2f} deg.")
    else:
        feedback.append(f"INC not corrected: {inc_val:.2f} deg (expected {inc_min}-{inc_max} deg for sun-sync).")

    # 6. Check DragArea
    if drag_min <= drag_val <= drag_max:
        total_score += scores["drag_area_corrected"]
        feedback.append(f"DragArea corrected: {drag_val:.4f} m^2.")
    else:
        feedback.append(f"DragArea not corrected: {drag_val} m^2 (expected {drag_min}-{drag_max} m^2).")

    # 7. Check diagnosis report
    report_file = task_result.get('report_file', {})
    report_path = task_result.get('report_path', '/home/ga/GMAT_output/leo_diagnosis_report.txt')
    if isinstance(report_file, dict) and report_file.get('exists'):
        temp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_rpt.name)
            with open(temp_rpt.name, 'r') as f:
                rpt_content = f.read()
            required_fields = ['SMA_corrected_km', 'ECC_corrected', 'INC_corrected_deg',
                                'DragArea_corrected_m2', 'RAAN_drift_degperday']
            fields_found = sum(1 for field in required_fields if field in rpt_content)
            if fields_found >= 3:
                total_score += scores["report_written"]
                feedback.append(f"Diagnosis report written with {fields_found}/5 required fields.")
            else:
                feedback.append(f"Diagnosis report incomplete ({fields_found}/5 fields).")
        except Exception as e:
            feedback.append(f"Could not read diagnosis report: {e}")
        finally:
            if os.path.exists(temp_rpt.name):
                os.unlink(temp_rpt.name)
    else:
        feedback.append("Diagnosis report not found.")

    # 8. Check orbit propagation ran (orbit report exists)
    orbit_file = task_result.get('orbit_report_file', {})
    if isinstance(orbit_file, dict) and orbit_file.get('exists') and orbit_file.get('size', 0) > 100:
        total_score += scores["orbit_propagated"]
        feedback.append("Orbit propagation report generated.")
    else:
        feedback.append("Orbit propagation report not found or empty.")

    # Pass condition: score >= 60 AND inclination corrected AND SMA corrected
    passed = total_score >= 60 and inc_ok and sma_ok

    return {
        "passed": passed,
        "score": min(total_score, 100),
        "feedback": " | ".join(feedback)
    }
