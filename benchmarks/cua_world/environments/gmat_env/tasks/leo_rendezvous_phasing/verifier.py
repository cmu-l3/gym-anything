#!/usr/bin/env python3
"""
Verifier for leo_rendezvous_phasing@1

Agent must design a two-impulse phasing maneuver to bring CHASER from 100 km
behind CHIEF to 5 km trailing in the same 450 km orbit.

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window
  - two_spacecraft (15): Both CHIEF and CHASER defined in script
  - two_burns (15): Two ImpulsiveBurn maneuvers in script
  - propagation_logic (10): Propagate commands present
  - results_written (10): Results file with required fields
  - deltav1_valid (10): First burn in valid range [1, 100] m/s
  - deltav2_valid (10): Second burn in valid range [1, 100] m/s
  - phasing_time_valid (10): Phasing time in [1, 48] hours
  - separation_achieved (10): Final separation <= 8 km
  - altitude_restored (10): CHASER final altitude within 5 km of 450 km

Pass condition: score >= 60 AND two_spacecraft AND two_burns
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_leo_rendezvous_phasing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_alt = metadata.get('target_altitude_km', 450.0)
    sep_tol = metadata.get('separation_tolerance_km', 8.0)
    alt_tol = metadata.get('altitude_tolerance_km', 5.0)
    dv_min = metadata.get('deltav_min_mps', 1.0)
    dv_max = metadata.get('deltav_max_mps', 100.0)
    phase_min = metadata.get('phasing_time_min_hours', 1.0)
    phase_max = metadata.get('phasing_time_max_hours', 48.0)

    scores = {
        "script_created": 10,
        "two_spacecraft": 15,
        "two_burns": 15,
        "propagation_logic": 10,
        "results_written": 10,
        "deltav1_valid": 10,
        "deltav2_valid": 10,
        "phasing_time_valid": 10,
        "separation_achieved": 10,
        "altitude_restored": 10,
    }

    total_score = 0
    feedback = []
    two_sc_ok = False
    two_burns_ok = False

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

    # 2. Two spacecraft in script
    has_chief = task_result.get('has_chief_spacecraft', False)
    has_chaser = task_result.get('has_chaser_spacecraft', False)
    if has_chief and has_chaser:
        total_score += scores["two_spacecraft"]
        two_sc_ok = True
        feedback.append("Both CHIEF and CHASER spacecraft defined.")
    elif has_chief or has_chaser:
        total_score += scores["two_spacecraft"] // 2
        feedback.append("Only one spacecraft (CHIEF or CHASER) found.")
    else:
        feedback.append("Neither CHIEF nor CHASER found in script.")

    # Also check via script content for more thorough verification
    script_path = task_result.get('script_path', '/home/ga/Documents/missions/rendezvous_phasing.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Count ImpulsiveBurn creations
            burn_count = len(re.findall(r'Create\s+ImpulsiveBurn', script_content))
            if burn_count >= 2:
                total_score += scores["two_burns"]
                two_burns_ok = True
                feedback.append(f"Two ImpulsiveBurn maneuvers found ({burn_count} total).")
            elif burn_count == 1:
                total_score += scores["two_burns"] // 3
                feedback.append("Only one ImpulsiveBurn found (need two for phasing).")
            else:
                # Check for Maneuver command
                if re.search(r'\bManeuver\b', script_content):
                    total_score += scores["two_burns"] // 3
                    feedback.append("Maneuver command found but no ImpulsiveBurn Create.")
                else:
                    feedback.append("No ImpulsiveBurn or Maneuver found in script.")

            # Check Propagate commands
            prop_count = len(re.findall(r'\bPropagate\b', script_content))
            if prop_count >= 2:
                total_score += scores["propagation_logic"]
                feedback.append(f"Propagation commands found ({prop_count}).")
            elif prop_count == 1:
                total_score += scores["propagation_logic"] // 2
                feedback.append("Only one Propagate command (expected at least 2).")
            else:
                feedback.append("No Propagate commands found.")

        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Results file
    results_file = task_result.get('results_file', {})
    results_path = task_result.get('results_path', '/home/ga/GMAT_output/rendezvous_results.txt')
    results_rerun = task_result.get('results_file_rerun', results_file)
    effective_results = results_rerun if isinstance(results_rerun, dict) and results_rerun.get('exists') else results_file

    if isinstance(effective_results, dict) and effective_results.get('exists'):
        temp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(results_path, temp_rpt.name)
            with open(temp_rpt.name, 'r') as f:
                rpt = f.read()
            required = ['DeltaV1_mps', 'DeltaV2_mps', 'PhasingTime_hours',
                        'FinalSeparation_km', 'CHASER_final_altitude_km']
            found = sum(1 for r in required if r in rpt)
            if found >= 3:
                total_score += scores["results_written"]
                feedback.append(f"Results file written with {found}/5 fields.")
            else:
                feedback.append(f"Results file incomplete ({found}/5 fields).")
        except Exception as e:
            feedback.append(f"Could not read results file: {e}")
        finally:
            if os.path.exists(temp_rpt.name):
                os.unlink(temp_rpt.name)
    else:
        feedback.append("Results file not found.")

    # 4. Validate numerical outputs
    def safe_float(v, default=0.0):
        try:
            return float(v)
        except (ValueError, TypeError):
            return default

    dv1 = safe_float(task_result.get('deltav1_mps', 0))
    dv2 = safe_float(task_result.get('deltav2_mps', 0))
    phase_time = safe_float(task_result.get('phasing_time_hours', 0))
    sep = safe_float(task_result.get('final_separation_km', 999))
    alt = safe_float(task_result.get('chaser_final_altitude_km', 0))

    if dv_min <= dv1 <= dv_max:
        total_score += scores["deltav1_valid"]
        feedback.append(f"DeltaV1 valid: {dv1:.2f} m/s.")
    elif dv1 > 0:
        feedback.append(f"DeltaV1 out of range: {dv1:.2f} m/s (expected {dv_min}-{dv_max} m/s).")
    else:
        feedback.append("DeltaV1 missing or zero.")

    if dv_min <= dv2 <= dv_max:
        total_score += scores["deltav2_valid"]
        feedback.append(f"DeltaV2 valid: {dv2:.2f} m/s.")
    elif dv2 > 0:
        feedback.append(f"DeltaV2 out of range: {dv2:.2f} m/s (expected {dv_min}-{dv_max} m/s).")
    else:
        feedback.append("DeltaV2 missing or zero.")

    if phase_min <= phase_time <= phase_max:
        total_score += scores["phasing_time_valid"]
        feedback.append(f"Phasing time valid: {phase_time:.2f} hours.")
    elif phase_time > 0:
        feedback.append(f"Phasing time out of range: {phase_time:.2f} hours (expected {phase_min}-{phase_max} h).")
    else:
        feedback.append("Phasing time missing or zero.")

    if 0 < sep <= sep_tol:
        total_score += scores["separation_achieved"]
        feedback.append(f"Final separation achieved: {sep:.2f} km (within {sep_tol} km).")
    elif sep > 0:
        feedback.append(f"Final separation too large: {sep:.2f} km (target <= {sep_tol} km).")
    else:
        feedback.append("Final separation missing or zero.")

    if alt > 0 and abs(alt - target_alt) <= alt_tol:
        total_score += scores["altitude_restored"]
        feedback.append(f"CHASER altitude restored: {alt:.2f} km (target {target_alt} ± {alt_tol} km).")
    elif alt > 0:
        feedback.append(f"CHASER altitude off: {alt:.2f} km (target {target_alt} ± {alt_tol} km).")
    else:
        feedback.append("CHASER final altitude missing.")

    passed = total_score >= 60 and two_sc_ok and two_burns_ok

    return {
        "passed": passed,
        "score": min(total_score, 100),
        "feedback": " | ".join(feedback)
    }
