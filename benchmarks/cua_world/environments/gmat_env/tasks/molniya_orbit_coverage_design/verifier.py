#!/usr/bin/env python3
"""
Verifier for molniya_orbit_coverage_design@1

Evaluates if the agent properly designed a Molniya orbit by:
1. Setting the correct Keplerian elements (SMA, ECC, INC, AOP).
2. Applying the critical inclination (~63.4 deg) required to freeze AOP.
3. Using a high-fidelity force model (J2+, drag, SRP) to observe real perturbations.
4. Exporting the correct analysis metrics to a report.

Scoring (total 100 pts, pass >= 60):
  - script_created (5)
  - report_exists (5)
  - sma_correct (15): ~26554 km for 12-hour period
  - ecc_correct (10): ~0.74 for ~500km perigee
  - inc_critical (20): ~63.4 deg (CRITICAL FOR AOP STABILITY)
  - aop_correct (10): ~270 deg
  - force_model_gravity (10): Degree/Order >= 4 configured
  - force_model_drag (5): AtmosphereModel configured
  - aop_drift_valid (10): Drift < 5 deg over 30 days
  - apogee_valid (5): Apogee > 35,000 km
  - period_valid (5): Period ~12 hours

Pass condition: score >= 60 AND inc_critical
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_float(val, default=-1.0):
    try:
        return float(val)
    except (ValueError, TypeError):
        return default

def verify_molniya_orbit_coverage_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    sma_min = metadata.get('sma_min_km', 26400.0)
    sma_max = metadata.get('sma_max_km', 26800.0)
    ecc_min = metadata.get('ecc_min', 0.70)
    ecc_max = metadata.get('ecc_max', 0.78)
    inc_min = metadata.get('inc_min_deg', 62.9)
    inc_max = metadata.get('inc_max_deg', 63.9)
    aop_min = metadata.get('aop_min_deg', 265.0)
    aop_max = metadata.get('aop_max_deg', 275.0)
    aop_drift_max = metadata.get('aop_drift_max_deg', 5.0)
    apogee_min = metadata.get('apogee_min_km', 35000.0)
    period_min = metadata.get('period_min_hours', 11.9)
    period_max = metadata.get('period_max_hours', 12.1)

    scores = {
        "script_created": 5,
        "report_exists": 5,
        "sma_correct": 15,
        "ecc_correct": 10,
        "inc_critical": 20,
        "aop_correct": 10,
        "force_model_gravity": 10,
        "force_model_drag": 5,
        "aop_drift_valid": 10,
        "apogee_valid": 5,
        "period_valid": 5
    }

    total_score = 0
    feedback = []
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

    # 1. Script & Report existence
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('created_during_task'):
        total_score += scores["report_exists"]
        feedback.append("Analysis report created during task window.")
    else:
        feedback.append("Analysis report not created during task window.")

    # 2. Parse GMAT Script for elements & force model (Fallback/Verification)
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/molniya_mission.script')
    script_sma, script_ecc, script_inc, script_aop = -1.0, -1.0, -1.0, -1.0
    gravity_ok, drag_ok = False, False

    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Parse elements
            m_sma = re.search(r'SMA\s*=\s*([0-9]+\.?[0-9]*)', script_content)
            m_ecc = re.search(r'ECC\s*=\s*([0-9]+\.?[0-9]*)', script_content)
            m_inc = re.search(r'INC\s*=\s*([0-9]+\.?[0-9]*)', script_content)
            m_aop = re.search(r'AOP\s*=\s*([0-9]+\.?[0-9]*)', script_content)

            if m_sma: script_sma = float(m_sma.group(1))
            if m_ecc: script_ecc = float(m_ecc.group(1))
            if m_inc: script_inc = float(m_inc.group(1))
            if m_aop: script_aop = float(m_aop.group(1))

            # Parse force model
            if re.search(r'GravityField\.Earth\.(Degree|Order)\s*=\s*([4-9]|[1-9][0-9]+)', script_content) or \
               re.search(r'JGM[23]\.cof|EGM96\.cof', script_content):
                gravity_ok = True
                total_score += scores["force_model_gravity"]
                feedback.append("High-fidelity gravity model configured.")
            else:
                feedback.append("High-fidelity gravity model (Degree >= 4) not found.")

            if re.search(r'Drag\.AtmosphereModel\s*=', script_content):
                drag_ok = True
                total_score += scores["force_model_drag"]
                feedback.append("Atmosphere drag model configured.")
            else:
                feedback.append("Atmosphere drag model not found.")

        except Exception as e:
            logger.warning(f"Error parsing script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Retrieve values from report export
    report_sma = parse_float(task_result.get('report_sma_km'))
    report_ecc = parse_float(task_result.get('report_ecc'))
    report_inc = parse_float(task_result.get('report_inc_deg'))
    report_aop = parse_float(task_result.get('report_aop_initial_deg'))
    report_drift = parse_float(task_result.get('report_aop_drift_deg'))
    report_apogee = parse_float(task_result.get('report_apogee_km'))
    report_period = parse_float(task_result.get('report_period_hours'))

    # Use script values as fallback if report parsing failed
    sma = report_sma if report_sma != -1.0 else script_sma
    ecc = report_ecc if report_ecc != -1.0 else script_ecc
    inc = report_inc if report_inc != -1.0 else script_inc
    aop = report_aop if report_aop != -1.0 else script_aop

    # 4. Score Orbital Elements
    if sma_min <= sma <= sma_max:
        total_score += scores["sma_correct"]
        feedback.append(f"SMA correct: {sma} km (12-hour period).")
    elif sma != -1.0:
        feedback.append(f"SMA incorrect: {sma} km (expected {sma_min}-{sma_max} km).")

    if ecc_min <= ecc <= ecc_max:
        total_score += scores["ecc_correct"]
        feedback.append(f"ECC correct: {ecc} (~500km perigee).")
    elif ecc != -1.0:
        feedback.append(f"ECC incorrect: {ecc} (expected {ecc_min}-{ecc_max}).")

    if inc_min <= inc <= inc_max:
        total_score += scores["inc_critical"]
        inc_ok = True
        feedback.append(f"Critical inclination used: {inc} deg.")
    elif inc != -1.0:
        feedback.append(f"Inclination incorrect: {inc} deg (expected ~63.4 deg for AOP freeze).")

    if aop_min <= aop <= aop_max:
        total_score += scores["aop_correct"]
        feedback.append(f"AOP correct: {aop} deg (apogee over Northern Hemisphere).")
    elif aop != -1.0:
        feedback.append(f"AOP incorrect: {aop} deg (expected 270 deg).")

    # 5. Score Report Metrics (AOP Drift, Apogee, Period)
    if report_drift != -1.0:
        if report_drift <= aop_drift_max:
            total_score += scores["aop_drift_valid"]
            feedback.append(f"AOP drift valid: {report_drift} deg (< 5 deg constraint).")
        else:
            feedback.append(f"AOP drift exceeds constraint: {report_drift} deg.")

    if report_apogee != -1.0:
        if report_apogee >= apogee_min:
            total_score += scores["apogee_valid"]
            feedback.append(f"Apogee altitude valid: {report_apogee} km.")
        else:
            feedback.append(f"Apogee altitude too low: {report_apogee} km.")

    if report_period != -1.0:
        if period_min <= report_period <= period_max:
            total_score += scores["period_valid"]
            feedback.append(f"Period valid: {report_period} hours.")
        else:
            feedback.append(f"Period incorrect: {report_period} hours.")

    # Determine passing status
    # Must meet 60 points AND must have identified the critical inclination (the core physics requirement)
    passed = (total_score >= 60) and inc_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }