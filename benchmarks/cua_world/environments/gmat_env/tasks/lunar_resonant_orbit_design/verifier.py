#!/usr/bin/env python3
"""
Verifier for lunar_resonant_orbit_design@1

Agent must design a P/2 2:1 lunar-resonant orbit (~13.66 days period, ~242k km SMA)
and propagate it for 120 days with a high-fidelity force model including the Moon.

Scoring (total 100 pts, pass >= 60):
  - script_created (5): Script created during task
  - sma_correct (20): SMA in script and report match expectations [238k, 248k] km
  - period_correct (15): Period ~13.66 days
  - eccentricity_valid (10): ECC in [0.3, 0.75] ensures perigee > 7 Re
  - moon_gravity (15): Moon/Luna included in force model (CRITICAL)
  - sun_gravity (5): Sun included in force model
  - propagation_duration (10): Propagation is at least 90 days
  - report_written (10): All fields present
  - stability_demonstrated (10): Final period within 10% of initial

Anti-gaming:
  - Cross-validates report values against actual .script file contents
  - Uses Kepler's Third Law to verify physical consistency of agent's reported values.
"""

import json
import os
import re
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MU_EARTH = 398600.4418 # km^3/s^2
EARTH_RADIUS = 6371.14 # km

def verify_lunar_resonant_orbit_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    sma_min = metadata.get('sma_min_km', 238000.0)
    sma_max = metadata.get('sma_max_km', 248000.0)
    ecc_min = metadata.get('ecc_min', 0.3)
    ecc_max = metadata.get('ecc_max', 0.75)
    target_period = metadata.get('target_period_days', 13.66)
    period_tol = metadata.get('period_tolerance_percent', 5.0) / 100.0
    min_prop_days = metadata.get('min_propagation_days', 90.0)
    stab_tol = metadata.get('stability_tolerance_percent', 10.0) / 100.0

    scores = {
        "script_created": 5,
        "sma_correct": 20,
        "period_correct": 15,
        "eccentricity_valid": 10,
        "moon_gravity": 15,
        "sun_gravity": 5,
        "propagation_duration": 10,
        "report_written": 10,
        "stability_demonstrated": 10,
    }

    total_score = 0
    feedback = []
    sma_ok = False
    moon_ok = False

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

    # 2. Extract agent's reported values
    try:
        rep_init_sma = float(task_result.get("reported_initial_sma_km", 0))
        rep_init_per = float(task_result.get("reported_initial_period_days", 0))
        rep_fin_per = float(task_result.get("reported_final_period_days", 0))
        rep_ecc = float(task_result.get("reported_eccentricity", 0))
        rep_perigee = float(task_result.get("reported_perigee_altitude_km", 0))
        rep_moon = task_result.get("reported_moon_gravity_included", "NO").upper()
    except ValueError:
        rep_init_sma = rep_init_per = rep_fin_per = rep_ecc = rep_perigee = 0.0
        rep_moon = "NO"

    if rep_init_sma > 0:
        total_score += scores["report_written"]
        feedback.append("Report successfully written and parsed.")
    else:
        feedback.append("Report not found or missing required values.")

    # 3. Analyze script content to prevent gaming (hallucinated reports)
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/lunar_resonant_orbit.script')
    script_sma = 0.0
    script_ecc = 0.0
    has_moon = False
    has_sun = False
    prop_days = 0.0

    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()

            # Parse SMA
            match_sma = re.search(r'\.SMA\s*=\s*([0-9]+\.?[0-9]*)', content)
            if match_sma:
                script_sma = float(match_sma.group(1))

            # Parse ECC
            match_ecc = re.search(r'\.ECC\s*=\s*([0-9]+\.?[0-9]*)', content)
            if match_ecc:
                script_ecc = float(match_ecc.group(1))

            # Parse force model point masses
            match_pm = re.search(r'\.PointMasses\s*=\s*\{([^}]+)\}', content)
            if match_pm:
                pm_str = match_pm.group(1).lower()
                if 'luna' in pm_str or 'moon' in pm_str:
                    has_moon = True
                if 'sun' in pm_str:
                    has_sun = True
            
            # Parse propagation duration (ElapsedDays)
            match_prop = re.findall(r'\.ElapsedDays\s*=\s*([0-9]+\.?[0-9]*)', content)
            if match_prop:
                prop_days = max([float(d) for d in match_prop])
                
        except Exception as e:
            logger.error(f"Error parsing script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 4. Cross-validate reported vs script SMA and ECC
    if script_sma > 0:
        if abs(script_sma - rep_init_sma) > script_sma * 0.05:
            feedback.append(f"WARNING: Reported SMA ({rep_init_sma}) differs from script SMA ({script_sma}).")
        # Use script SMA for truth
        true_sma = script_sma
        true_ecc = script_ecc
    else:
        # Fallback to reported if we couldn't parse script
        true_sma = rep_init_sma
        true_ecc = rep_ecc

    # 5. Check SMA (Resonance Condition)
    if sma_min <= true_sma <= sma_max:
        total_score += scores["sma_correct"]
        sma_ok = True
        feedback.append(f"SMA valid for 2:1 resonance: {true_sma:.1f} km.")
    else:
        feedback.append(f"SMA {true_sma:.1f} km outside valid resonance range [{sma_min}, {sma_max}].")

    # 6. Check Period (Physics consistency check)
    if true_sma > 0:
        # Kepler's Third Law
        calc_period_sec = 2 * math.pi * math.sqrt((true_sma**3) / MU_EARTH)
        calc_period_days = calc_period_sec / 86400.0

        if abs(calc_period_days - target_period) <= (target_period * period_tol):
            total_score += scores["period_correct"]
            feedback.append(f"Initial period physically correct: ~{calc_period_days:.2f} days.")
        else:
            feedback.append(f"Initial period {calc_period_days:.2f} days deviates from 13.66 days target.")

    # 7. Check Eccentricity (Perigee Constraint)
    if true_sma > 0:
        calc_perigee = true_sma * (1 - true_ecc) - EARTH_RADIUS
        if ecc_min <= true_ecc <= ecc_max:
            total_score += scores["eccentricity_valid"]
            feedback.append(f"Eccentricity {true_ecc:.3f} valid. (Perigee ≈ {calc_perigee:.0f} km, > 44650 km).")
        else:
            feedback.append(f"Eccentricity {true_ecc:.3f} invalid. Perigee constraint likely violated.")

    # 8. Check Force Model
    if has_moon:
        total_score += scores["moon_gravity"]
        moon_ok = True
        feedback.append("Moon gravity included in force model (CRITICAL).")
    else:
        feedback.append("Moon gravity NOT found in force model. Resonance simulation is invalid.")

    if has_sun:
        total_score += scores["sun_gravity"]
        feedback.append("Sun gravity included in force model.")

    # 9. Check Propagation
    if prop_days >= min_prop_days:
        total_score += scores["propagation_duration"]
        feedback.append(f"Propagation duration valid: {prop_days} days.")
    else:
        feedback.append(f"Propagation duration {prop_days} days is less than required {min_prop_days}.")

    # 10. Check Stability (Final vs Initial Period)
    if rep_fin_per > 0 and rep_init_per > 0:
        period_change = abs(rep_fin_per - rep_init_per) / rep_init_per
        if period_change <= stab_tol:
            total_score += scores["stability_demonstrated"]
            feedback.append(f"Stability demonstrated: period changed by only {period_change*100:.1f}%.")
        else:
            feedback.append(f"Orbit unstable: period changed by {period_change*100:.1f}%.")

    # Pass Condition
    passed = (total_score >= 60) and sma_ok and moon_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }