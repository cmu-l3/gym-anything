#!/usr/bin/env python3
"""
Verifier for geo_stationkeeping_budget@1

Checks that the agent set up a physically correct GEO stationkeeping simulation,
propagated it, and properly estimated Delta-V budgets from the results.

Scoring (total 100 pts, pass >= 60):
  - script_created (8)
  - spacecraft_params (7)
  - earth_gravity_order (10)
  - third_body_sun (5)
  - third_body_moon (5)
  - srp_enabled (5)
  - propagation_30day (5)
  - orbit_data_generated (5)
  - report_written (5)
  - inc_growth_valid (12)
  - lon_drift_direction (8)
  - lon_drift_rate_valid (5)
  - ns_deltav_valid (10)
  - ew_deltav_valid (5)
  - total_deltav_valid (5)

Pass condition: score >= 60 AND earth_gravity_order met AND inc_growth_valid met
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_geo_stationkeeping_budget(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    inc_min = metadata.get('inc_growth_min', 0.5)
    inc_max = metadata.get('inc_growth_max', 1.2)
    lon_min = metadata.get('lon_drift_min', 0.05)
    lon_max = metadata.get('lon_drift_max', 2.0)
    ns_min = metadata.get('ns_dv_min', 35.0)
    ns_max = metadata.get('ns_dv_max', 65.0)
    ew_min = metadata.get('ew_dv_min', 0.1)
    ew_max = metadata.get('ew_dv_max', 10.0)
    total_min = metadata.get('total_dv_min', 36.0)
    total_max = metadata.get('total_dv_max', 75.0)
    deg_min = metadata.get('gravity_degree_min', 12)

    scores = {
        "script_created": 8,
        "spacecraft_params": 7,
        "earth_gravity_order": 10,
        "third_body_sun": 5,
        "third_body_moon": 5,
        "srp_enabled": 5,
        "propagation_30day": 5,
        "orbit_data_generated": 5,
        "report_written": 5,
        "inc_growth_valid": 12,
        "lon_drift_direction": 8,
        "lon_drift_rate_valid": 5,
        "ns_deltav_valid": 10,
        "ew_deltav_valid": 5,
        "total_deltav_valid": 5
    }

    total_score = 0
    feedback = []
    
    gravity_ok = False
    inc_growth_ok = False

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

    # Check script file
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # Check orbit data generation
    if task_result.get('orbit_data_generated', False):
        total_score += scores["orbit_data_generated"]
        feedback.append("Orbit data report generated.")
    else:
        feedback.append("No orbit data report generated.")

    # Analyze script content
    script_path = task_result.get('script_path', '')
    if script_path and isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Spacecraft params
            has_sma = bool(re.search(r'SMA\s*=\s*42164', script_content))
            has_mass = bool(re.search(r'DryMass\s*=\s*3200', script_content))
            has_srp = bool(re.search(r'SRPArea\s*=\s*42', script_content))
            if has_sma and has_mass and has_srp:
                total_score += scores["spacecraft_params"]
                feedback.append("Spacecraft parameters properly configured.")
            else:
                feedback.append("Spacecraft parameters (SMA/Mass/SRPArea) incorrect or missing.")

            # Gravity Order
            degree_match = re.search(r'Degree\s*=\s*(\d+)', script_content, re.IGNORECASE)
            order_match = re.search(r'Order\s*=\s*(\d+)', script_content, re.IGNORECASE)
            if degree_match and order_match:
                if int(degree_match.group(1)) >= deg_min and int(order_match.group(1)) >= deg_min:
                    total_score += scores["earth_gravity_order"]
                    gravity_ok = True
                    feedback.append(f"Gravity order >= {deg_min} configured.")
                else:
                    feedback.append(f"Gravity order too low ({degree_match.group(1)}x{order_match.group(1)}).")
            else:
                feedback.append("Gravity order not explicitly set (defaults to 4x4).")

            # Third Bodies
            if re.search(r'PointMasses\s*=\s*\{[^}]*Sun[^}]*\}', script_content, re.IGNORECASE):
                total_score += scores["third_body_sun"]
                feedback.append("Sun configured in PointMasses.")
            else:
                feedback.append("Sun missing from PointMasses.")

            if re.search(r'PointMasses\s*=\s*\{[^}]*(Luna|Moon)[^}]*\}', script_content, re.IGNORECASE):
                total_score += scores["third_body_moon"]
                feedback.append("Moon configured in PointMasses.")
            else:
                feedback.append("Moon missing from PointMasses.")

            # SRP enabled
            if re.search(r'SRP\s*=\s*On', script_content, re.IGNORECASE):
                total_score += scores["srp_enabled"]
                feedback.append("SRP enabled in force model.")
            else:
                feedback.append("SRP not explicitly enabled.")

            # 30-day propagation
            if re.search(r'ElapsedDays\s*=\s*30', script_content, re.IGNORECASE):
                total_score += scores["propagation_30day"]
                feedback.append("Propagating for 30 days.")
            else:
                feedback.append("Did not propagate for exactly 30 days.")

        except Exception as e:
            feedback.append(f"Error parsing script: {str(e)}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # Analyze budget report
    report_file = task_result.get('report_file', {})
    report_path = task_result.get('report_path', '')
    if report_path and isinstance(report_file, dict) and report_file.get('exists'):
        total_score += scores["report_written"]
        feedback.append("Stationkeeping budget report written.")

        temp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_rpt.name)
            with open(temp_rpt.name, 'r', encoding='utf-8', errors='ignore') as f:
                rpt_content = f.read()

            def extract_val(pattern):
                match = re.search(pattern, rpt_content, re.IGNORECASE)
                if match:
                    try:
                        return float(match.group(1))
                    except ValueError:
                        pass
                return None

            inc_growth = extract_val(r'INC_growth_rate_degperyear:\s*([0-9]*\.?[0-9e+-]+)')
            lon_drift = extract_val(r'LON_drift_rate_degperyear:\s*([0-9]*\.?[0-9e+-]+)')
            ns_dv = extract_val(r'NS_deltav_msperyear:\s*([0-9]*\.?[0-9e+-]+)')
            ew_dv = extract_val(r'EW_deltav_msperyear:\s*([0-9]*\.?[0-9e+-]+)')
            total_dv = extract_val(r'total_deltav_msperyear:\s*([0-9]*\.?[0-9e+-]+)')

            # INC growth
            if inc_growth is not None and inc_min <= inc_growth <= inc_max:
                total_score += scores["inc_growth_valid"]
                inc_growth_ok = True
                feedback.append(f"INC growth valid: {inc_growth:.3f} deg/yr.")
            else:
                feedback.append(f"INC growth invalid or missing: {inc_growth} deg/yr.")

            # LON drift dir
            if re.search(r'LON_drift_direction:\s*Eastward', rpt_content, re.IGNORECASE):
                total_score += scores["lon_drift_direction"]
                feedback.append("LON drift direction identified as Eastward.")
            else:
                feedback.append("LON drift direction missing or not Eastward.")

            # LON drift
            if lon_drift is not None and lon_min <= lon_drift <= lon_max:
                total_score += scores["lon_drift_rate_valid"]
                feedback.append(f"LON drift valid: {lon_drift:.3f} deg/yr.")
            else:
                feedback.append(f"LON drift invalid or missing: {lon_drift} deg/yr.")

            # NS dV
            if ns_dv is not None and ns_min <= ns_dv <= ns_max:
                total_score += scores["ns_deltav_valid"]
                feedback.append(f"N-S Delta-V valid: {ns_dv:.2f} m/s/yr.")
            else:
                feedback.append(f"N-S Delta-V invalid or missing: {ns_dv} m/s/yr.")

            # EW dV
            if ew_dv is not None and ew_min <= ew_dv <= ew_max:
                total_score += scores["ew_deltav_valid"]
                feedback.append(f"E-W Delta-V valid: {ew_dv:.2f} m/s/yr.")
            else:
                feedback.append(f"E-W Delta-V invalid or missing: {ew_dv} m/s/yr.")

            # Total dV
            if total_dv is not None and total_min <= total_dv <= total_max:
                # Also check self-consistency
                if ns_dv is not None and ew_dv is not None:
                    if abs(total_dv - (ns_dv + ew_dv)) < 2.0:
                        total_score += scores["total_deltav_valid"]
                        feedback.append(f"Total Delta-V valid and consistent: {total_dv:.2f} m/s/yr.")
                    else:
                        feedback.append("Total Delta-V is not consistent with NS + EW sum.")
                else:
                    total_score += scores["total_deltav_valid"]
                    feedback.append(f"Total Delta-V valid: {total_dv:.2f} m/s/yr.")
            else:
                feedback.append(f"Total Delta-V invalid or missing: {total_dv} m/s/yr.")

        except Exception as e:
            feedback.append(f"Error parsing budget report: {str(e)}")
        finally:
            if os.path.exists(temp_rpt.name):
                os.unlink(temp_rpt.name)
    else:
        feedback.append("Stationkeeping budget report not created during task window.")

    is_passed = (total_score >= 60) and gravity_ok and inc_growth_ok

    if is_passed:
        feedback.append("SUCCESS: Required physical conditions met and score >= 60.")
    else:
        feedback.append("FAILED: Score < 60 or missing required physical fidelity (Gravity/INC).")

    return {
        "passed": is_passed,
        "score": total_score,
        "feedback": "\n".join(feedback)
    }