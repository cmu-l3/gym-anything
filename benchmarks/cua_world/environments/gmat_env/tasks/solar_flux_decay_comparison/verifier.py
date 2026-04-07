#!/usr/bin/env python3
"""
Verifier for solar_flux_decay_comparison@1

Agent must simulate 60-day orbital decay under 3 solar flux scenarios and produce
a comparative analysis showing physically correct trends.

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window
  - three_scenarios_present (20): Script contains 3 different F10.7 values
  - drag_force_model (10): JacchiaRoberts or MSISE86 atmosphere model used
  - analysis_written (10): Analysis file with required fields
  - sma_ordering (15): Final SMAs correctly ordered: Active < Moderate < Quiet
  - decay_quiet_valid (10): Quiet sun decay in expected range [0.1, 5.0] km
  - decay_moderate_valid (10): Moderate sun decay in expected range [1.0, 20.0] km
  - decay_active_valid (10): Active sun decay in expected range [5.0, 80.0] km
  - ratio_valid (5): Active/Quiet decay ratio in expected range [3, 50]

Pass condition: score >= 60 AND three_scenarios_present AND sma_ordering
(physically impossible for active sun to decay less than quiet sun)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_solar_flux_decay_comparison(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    initial_sma = metadata.get('initial_sma_km', 6971.14)
    decay_q_min = metadata.get('decay_quiet_min_km', 0.1)
    decay_q_max = metadata.get('decay_quiet_max_km', 5.0)
    decay_m_min = metadata.get('decay_moderate_min_km', 1.0)
    decay_m_max = metadata.get('decay_moderate_max_km', 20.0)
    decay_a_min = metadata.get('decay_active_min_km', 5.0)
    decay_a_max = metadata.get('decay_active_max_km', 80.0)
    ratio_min = metadata.get('ratio_active_to_quiet_min', 3.0)
    ratio_max = metadata.get('ratio_active_to_quiet_max', 50.0)

    scores = {
        "script_created": 10,
        "three_scenarios_present": 20,
        "drag_force_model": 10,
        "analysis_written": 10,
        "sma_ordering": 15,
        "decay_quiet_valid": 10,
        "decay_moderate_valid": 10,
        "decay_active_valid": 10,
        "ratio_valid": 5,
    }

    total_score = 0
    feedback = []
    three_scenarios_ok = False
    ordering_ok = False

    # Load task result
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

    # 2. Analyze script for 3 scenarios
    script_path = task_result.get('script_path', '/home/ga/Documents/missions/solar_flux_study.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Count distinct F10.7 values
            f107_values = set(re.findall(r'F107\s*=\s*([0-9]+)', script_content))
            # Remove duplicates and check we have 3 distinct values covering low/mid/high
            if len(f107_values) >= 3:
                vals = sorted([int(v) for v in f107_values])
                # Must have one below 100, one around 150, one above 200
                has_low = any(v < 100 for v in vals)
                has_high = any(v > 200 for v in vals)
                if has_low and has_high:
                    total_score += scores["three_scenarios_present"]
                    three_scenarios_ok = True
                    feedback.append(f"3 solar flux scenarios present: F10.7 values = {sorted(vals)}.")
                else:
                    total_score += scores["three_scenarios_present"] // 2
                    feedback.append(f"3 F10.7 values found but don't span quiet-moderate-active: {vals}.")
            elif len(f107_values) == 2:
                total_score += scores["three_scenarios_present"] // 4
                feedback.append(f"Only 2 F10.7 values found (expected 3): {f107_values}.")
            else:
                feedback.append(f"Less than 2 F10.7 values found: {f107_values}.")

            # Check drag atmosphere model
            if re.search(r'AtmosphereModel\s*=\s*(JacchiaRoberts|MSISE86|NRLMSISE00)', script_content):
                total_score += scores["drag_force_model"]
                feedback.append("Drag atmosphere model (JR/MSISE) configured.")
            elif "Drag" in script_content and "ForceModel" in script_content:
                total_score += scores["drag_force_model"] // 2
                feedback.append("Drag force model present (atmosphere model not verified).")
            else:
                feedback.append("Drag atmosphere model not found in script.")

        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Analysis file
    analysis_file = task_result.get('analysis_file', {})
    analysis_path = task_result.get('analysis_path', '/home/ga/GMAT_output/solar_flux_analysis.txt')
    # Prefer rerun results
    analysis_rerun = task_result.get('analysis_file_rerun', analysis_file)
    effective_analysis = analysis_rerun if isinstance(analysis_rerun, dict) and analysis_rerun.get('exists') else analysis_file

    if isinstance(effective_analysis, dict) and effective_analysis.get('exists'):
        required = ['Scenario_1_QuietSun_SMA_final_km', 'Scenario_2_ModerateSun_SMA_final_km',
                    'Scenario_3_ActiveSun_SMA_final_km', 'SMA_decay_quiet_km',
                    'Decay_ratio_active_to_quiet']
        temp_a = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(analysis_path, temp_a.name)
            with open(temp_a.name, 'r') as f:
                analysis_text = f.read()
            found = sum(1 for r in required if r in analysis_text)
            if found >= 3:
                total_score += scores["analysis_written"]
                feedback.append(f"Analysis report written with {found}/5 required fields.")
            else:
                feedback.append(f"Analysis report incomplete ({found}/5 fields).")
        except Exception as e:
            feedback.append(f"Could not read analysis file: {e}")
        finally:
            if os.path.exists(temp_a.name):
                os.unlink(temp_a.name)
    else:
        feedback.append("Analysis file not found.")

    # 4. Check numerical values from export
    def safe_float(v, default=0.0):
        try:
            return float(v)
        except (ValueError, TypeError):
            return default

    sma_q = safe_float(task_result.get('sma_final_quiet_km', 0))
    sma_m = safe_float(task_result.get('sma_final_moderate_km', 0))
    sma_a = safe_float(task_result.get('sma_final_active_km', 0))
    decay_q = safe_float(task_result.get('decay_quiet_km', 0))
    decay_m = safe_float(task_result.get('decay_moderate_km', 0))
    decay_a = safe_float(task_result.get('decay_active_km', 0))
    ratio = safe_float(task_result.get('ratio_active_to_quiet', 0))

    # If decays are missing but SMAs are present, compute decays
    if decay_q == 0.0 and sma_q > 0:
        decay_q = initial_sma - sma_q
    if decay_m == 0.0 and sma_m > 0:
        decay_m = initial_sma - sma_m
    if decay_a == 0.0 and sma_a > 0:
        decay_a = initial_sma - sma_a

    # Check SMA ordering: Active must decay more than Moderate, Moderate more than Quiet
    if sma_q > 0 and sma_m > 0 and sma_a > 0:
        if sma_a < sma_m < sma_q:
            total_score += scores["sma_ordering"]
            ordering_ok = True
            feedback.append(f"SMA ordering correct: Active({sma_a:.2f}) < Moderate({sma_m:.2f}) < Quiet({sma_q:.2f}) km.")
        else:
            feedback.append(f"SMA ordering incorrect: Active={sma_a:.2f}, Moderate={sma_m:.2f}, Quiet={sma_q:.2f} km.")
    elif decay_a > 0 and decay_m > 0 and decay_q > 0:
        if decay_a > decay_m > decay_q:
            total_score += scores["sma_ordering"]
            ordering_ok = True
            feedback.append(f"Decay ordering correct: Active({decay_a:.2f}) > Moderate({decay_m:.2f}) > Quiet({decay_q:.2f}) km.")
        else:
            feedback.append(f"Decay ordering incorrect.")
    else:
        feedback.append("Could not verify SMA ordering (values missing).")

    # Decay range checks
    if decay_q_min <= decay_q <= decay_q_max:
        total_score += scores["decay_quiet_valid"]
        feedback.append(f"Quiet sun decay valid: {decay_q:.3f} km.")
    elif decay_q > 0:
        feedback.append(f"Quiet sun decay out of range: {decay_q:.3f} km (expected {decay_q_min}-{decay_q_max} km).")
    else:
        feedback.append("Quiet sun decay missing or zero.")

    if decay_m_min <= decay_m <= decay_m_max:
        total_score += scores["decay_moderate_valid"]
        feedback.append(f"Moderate sun decay valid: {decay_m:.3f} km.")
    elif decay_m > 0:
        feedback.append(f"Moderate sun decay out of range: {decay_m:.3f} km (expected {decay_m_min}-{decay_m_max} km).")
    else:
        feedback.append("Moderate sun decay missing or zero.")

    if decay_a_min <= decay_a <= decay_a_max:
        total_score += scores["decay_active_valid"]
        feedback.append(f"Active sun decay valid: {decay_a:.3f} km.")
    elif decay_a > 0:
        feedback.append(f"Active sun decay out of range: {decay_a:.3f} km (expected {decay_a_min}-{decay_a_max} km).")
    else:
        feedback.append("Active sun decay missing or zero.")

    # Compute ratio if not in file
    if ratio == 0.0 and decay_q > 0 and decay_a > 0:
        ratio = decay_a / decay_q

    if ratio_min <= ratio <= ratio_max:
        total_score += scores["ratio_valid"]
        feedback.append(f"Active/Quiet decay ratio valid: {ratio:.2f}.")
    elif ratio > 0:
        feedback.append(f"Active/Quiet decay ratio out of range: {ratio:.2f} (expected {ratio_min}-{ratio_max}).")
    else:
        feedback.append("Active/Quiet ratio missing.")

    passed = total_score >= 60 and three_scenarios_ok and ordering_ok

    return {
        "passed": passed,
        "score": min(total_score, 100),
        "feedback": " | ".join(feedback)
    }
