#!/usr/bin/env python3
"""
Verifier for tandem_sar_helix_formation@1

Evaluates the setup of a J2-invariant relative orbit using mathematical calculations
and physical stability verification from the resulting simulation.

Scoring (total 100 pts, pass >= 70):
  - script_created (10)
  - two_spacecraft_defined (10)
  - sma_inc_identical (15) - Critical for J2-invariance
  - ecc_calculated (15) - Radial baseline math
  - raan_calculated (15) - Cross-track baseline math
  - report_generated (15) - Output file verification
  - physics_stable_drift (20) - Max distance bounded < 3km, Min > 0.4km, no secular drift
"""

import json
import os
import re
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_orbital_element(script_content, sc_name, element_name):
    """Utility to extract an orbital element value from GMAT script using regex."""
    pattern = re.compile(rf'{sc_name}\.{element_name}\s*=\s*([0-9\.\-eE\+]+)', re.IGNORECASE)
    match = pattern.search(script_content)
    if match:
        try:
            return float(match.group(1))
        except ValueError:
            pass
    return None


def verify_tandem_sar_helix_formation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_chief_sma = metadata.get('expected_chief_sma', 6892.14)
    expected_chief_inc = metadata.get('expected_chief_inc', 97.4)
    expected_deputy_ecc = metadata.get('expected_deputy_ecc', 0.0000725)
    expected_deputy_raan = metadata.get('expected_deputy_raan', 45.02096)
    tol_sma = metadata.get('tolerance_sma_km', 0.001)
    tol_inc = metadata.get('tolerance_inc_deg', 0.0001)
    tol_ecc = metadata.get('tolerance_ecc', 0.000005)
    tol_raan = metadata.get('tolerance_raan_deg', 0.0005)
    max_drift = metadata.get('max_drift_distance_km', 3.0)
    min_drift = metadata.get('min_drift_distance_km', 0.4)

    scores = {
        "script_created": 10,
        "two_spacecraft_defined": 10,
        "sma_inc_identical": 15,
        "ecc_calculated": 15,
        "raan_calculated": 15,
        "report_generated": 15,
        "physics_stable_drift": 20
    }

    total_score = 0
    feedback = []
    sma_inc_ok = False
    physics_ok = False

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

    # 2. Two spacecraft defined
    if task_result.get('has_chief') and task_result.get('has_deputy'):
        total_score += scores["two_spacecraft_defined"]
        feedback.append("Chief and Deputy spacecraft defined.")
    else:
        feedback.append("Missing Chief or Deputy definition in script.")

    script_path = task_result.get('script_path', '/home/ga/GMAT_output/tandem_formation.script')
    
    # Analyze Script Content
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Find spacecraft names (assumed Chief and Deputy, or variations)
            chief_name = "Chief" if re.search(r'Create\s+Spacecraft\s+Chief', script_content, re.IGNORECASE) else None
            deputy_name = "Deputy" if re.search(r'Create\s+Spacecraft\s+Deputy', script_content, re.IGNORECASE) else None

            # Fallback if agent named them differently, take first two spacecraft
            if not chief_name or not deputy_name:
                sc_matches = re.findall(r'Create\s+Spacecraft\s+(\w+)', script_content, re.IGNORECASE)
                if len(sc_matches) >= 2:
                    chief_name = sc_matches[0]
                    deputy_name = sc_matches[1]

            if chief_name and deputy_name:
                c_sma = extract_orbital_element(script_content, chief_name, 'SMA')
                c_inc = extract_orbital_element(script_content, chief_name, 'INC')
                d_sma = extract_orbital_element(script_content, deputy_name, 'SMA')
                d_inc = extract_orbital_element(script_content, deputy_name, 'INC')
                d_ecc = extract_orbital_element(script_content, deputy_name, 'ECC')
                d_raan = extract_orbital_element(script_content, deputy_name, 'RAAN')

                # 3. SMA & INC identical Check
                if (c_sma is not None and d_sma is not None and 
                    c_inc is not None and d_inc is not None):
                    if (abs(c_sma - d_sma) <= tol_sma and abs(c_inc - d_inc) <= tol_inc and
                        abs(c_sma - expected_chief_sma) <= 1.0):
                        total_score += scores["sma_inc_identical"]
                        sma_inc_ok = True
                        feedback.append("SMA and INC are correctly matched for J2 invariance.")
                    else:
                        feedback.append(f"SMA or INC mismatch (Chief: {c_sma}/{c_inc}, Deputy: {d_sma}/{d_inc}).")
                else:
                    feedback.append("Could not extract SMA/INC values from script.")

                # 4. ECC calculated correctly
                if d_ecc is not None and abs(d_ecc - expected_deputy_ecc) <= tol_ecc:
                    total_score += scores["ecc_calculated"]
                    feedback.append(f"Deputy ECC accurately calculated ({d_ecc}).")
                elif d_ecc is not None:
                    feedback.append(f"Deputy ECC incorrect (Found: {d_ecc}, Expected: ~{expected_deputy_ecc}).")
                else:
                    feedback.append("Could not extract Deputy ECC.")

                # 5. RAAN calculated correctly
                if d_raan is not None and abs(d_raan - expected_deputy_raan) <= tol_raan:
                    total_score += scores["raan_calculated"]
                    feedback.append(f"Deputy RAAN accurately calculated ({d_raan}).")
                elif d_raan is not None:
                    feedback.append(f"Deputy RAAN incorrect (Found: {d_raan}, Expected: ~{expected_deputy_raan}).")
                else:
                    feedback.append("Could not extract Deputy RAAN.")

        except Exception as e:
            logger.error(f"Error reading script file: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 6. Check report generated
    report_file = task_result.get('report_file_rerun', task_result.get('report_file', {}))
    report_path = task_result.get('report_path', '/home/ga/GMAT_output/formation_state.txt')
    
    distances = []
    if isinstance(report_file, dict) and report_file.get('exists') and report_file.get('size', 0) > 0:
        total_score += scores["report_generated"]
        feedback.append("Report file generated.")
        
        # 7. Physical Stability Verification (Anti-Gaming)
        temp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_rpt.name)
            with open(temp_rpt.name, 'r') as f:
                lines = f.readlines()
                
            for line in lines:
                parts = line.strip().split()
                # Expecting at least 7 columns (ElapsedDays + 6 cartesian)
                if len(parts) >= 7:
                    try:
                        # Fallback parsing - grab the last 6 floats which should be coordinates
                        coords = [float(x) for x in parts[-6:]]
                        cx, cy, cz, dx, dy, dz = coords
                        
                        dist = math.sqrt((cx-dx)**2 + (cy-dy)**2 + (cz-dz)**2)
                        distances.append(dist)
                    except ValueError:
                        continue
                        
            if len(distances) > 10:
                max_d = max(distances)
                min_d = min(distances)
                
                # Check for secular drift: compare average distance of first 10% vs last 10%
                tenth = max(1, len(distances) // 10)
                avg_start = sum(distances[:tenth]) / tenth
                avg_end = sum(distances[-tenth:]) / tenth
                
                # Drift limit (if it drifted away by more than 10%, it's unstable)
                drift_ratio = abs(avg_end - avg_start) / avg_start if avg_start > 0 else 0
                
                if max_d <= max_drift and min_d >= min_drift and drift_ratio < 0.15:
                    total_score += scores["physics_stable_drift"]
                    physics_ok = True
                    feedback.append(f"Helix physics proven stable (Max Dist: {max_d:.2f}km, Min Dist: {min_d:.2f}km, No Secular Drift).")
                else:
                    feedback.append(f"Physics unstable: Max={max_d:.2f}km, Min={min_d:.2f}km, Drift={drift_ratio:.1%}.")
            else:
                feedback.append("Report file did not contain enough valid data rows for stability check.")
                
        except Exception as e:
            feedback.append(f"Error parsing report file: {e}")
        finally:
            if os.path.exists(temp_rpt.name):
                os.unlink(temp_rpt.name)
    else:
        feedback.append("Report file not generated or empty.")

    passed = total_score >= 70 and sma_inc_ok and physics_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }