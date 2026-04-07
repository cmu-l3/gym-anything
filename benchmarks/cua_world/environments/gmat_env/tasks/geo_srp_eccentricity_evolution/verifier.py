#!/usr/bin/env python3
"""
Verifier for geo_srp_eccentricity_evolution@1

Agent must simulate a GEO satellite for 1 year with SRP enabled, measure the
eccentricity vector evolution, and extract key metrics matching orbital mechanics.

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window
  - geo_orbit_correct (10): SMA ~42164.17 km configured in script
  - srp_enabled (15): SRP force model enabled
  - srp_area_correct (10): SRPArea=45.0 and Cr=1.2 configured
  - third_body_present (5): Sun and/or Moon point masses added
  - drag_disabled (5): Atmospheric drag explicitly off or not configured
  - report_generated (10): Orbit report file has >100 lines (successful propagation)
  - analysis_written (10): Analysis report generated with >4 required fields
  - max_ecc_valid (10): Max eccentricity in [0.0003, 0.005] (proving SRP effect)
  - ecc_period_valid (10): Oscillation period in [340, 390] days
  - sma_stable (5): Final SMA within 10 km of 42164.17 km

Pass condition: score >= 60 AND srp_enabled AND report_generated
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_geo_srp_eccentricity_evolution(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    geo_sma = metadata.get('geo_sma_km', 42164.17)
    srp_area = metadata.get('srp_area_m2', 45.0)
    srp_cr = metadata.get('srp_cr', 1.2)
    max_ecc_min = metadata.get('max_ecc_min', 0.0003)
    max_ecc_max = metadata.get('max_ecc_max', 0.005)
    period_min = metadata.get('period_min_days', 340)
    period_max = metadata.get('period_max_days', 390)
    sma_tol = metadata.get('sma_tolerance_km', 10.0)

    scores = {
        "script_created": 10,
        "geo_orbit_correct": 10,
        "srp_enabled": 15,
        "srp_area_correct": 10,
        "third_body_present": 5,
        "drag_disabled": 5,
        "report_generated": 10,
        "analysis_written": 10,
        "max_ecc_valid": 10,
        "ecc_period_valid": 10,
        "sma_stable": 5
    }

    total_score = 0
    feedback = []
    srp_is_enabled = False
    report_is_generated = False

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

    # 2. Orbit Report Generated
    line_count = task_result.get('report_line_count', 0)
    if line_count > 100:
        total_score += scores["report_generated"]
        report_is_generated = True
        feedback.append(f"Orbit report file generated ({line_count} lines).")
    else:
        feedback.append("Orbit report file missing or has insufficient lines (propagation failed).")

    # 3. Analyze Script Content
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/geo_srp_mission.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Geo Orbit Check (SMA ~ 42164)
            sma_match = re.search(r'SMA\s*=\s*([0-9]+\.?[0-9]*)', script_content)
            if sma_match and abs(float(sma_match.group(1)) - geo_sma) < 100:
                total_score += scores["geo_orbit_correct"]
                feedback.append(f"GEO SMA correctly set (~{sma_match.group(1)} km).")
            else:
                feedback.append("GEO SMA incorrect or missing.")

            # SRP Enabled Check
            if re.search(r'\.SRP\s*=\s*On', script_content):
                total_score += scores["srp_enabled"]
                srp_is_enabled = True
                feedback.append("SRP force model enabled.")
            else:
                feedback.append("SRP force model NOT enabled.")

            # SRP Area & Cr
            area_match = re.search(r'SRPArea\s*=\s*([0-9]+\.?[0-9]*)', script_content)
            cr_match = re.search(r'Cr\s*=\s*([0-9]+\.?[0-9]*)', script_content)
            area_ok = area_match and abs(float(area_match.group(1)) - srp_area) < 0.1
            cr_ok = cr_match and abs(float(cr_match.group(1)) - srp_cr) < 0.1
            if area_ok and cr_ok:
                total_score += scores["srp_area_correct"]
                feedback.append("SRPArea and Cr correctly configured.")
            elif area_ok or cr_ok:
                total_score += scores["srp_area_correct"] // 2
                feedback.append("Either SRPArea or Cr incorrect.")
            else:
                feedback.append("SRPArea and Cr not configured properly.")

            # Third Body Present
            if re.search(r'PointMasses\s*=\s*\{.*(?:Sun|Luna|Moon).*\}', script_content):
                total_score += scores["third_body_present"]
                feedback.append("Third body perturbations (Sun/Moon) included.")
            else:
                feedback.append("Third body perturbations missing.")

            # Drag Disabled
            if not re.search(r'AtmosphereModel\s*=\s*(JacchiaRoberts|MSISE86|NRLMSISE00)', script_content):
                total_score += scores["drag_disabled"]
                feedback.append("Atmospheric drag properly excluded.")
            else:
                feedback.append("Atmospheric drag incorrectly included for GEO.")

        except Exception as e:
            feedback.append(f"Error parsing script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 4. Analyze Analysis Report
    analysis_file = task_result.get('analysis_file', {})
    analysis_path = task_result.get('analysis_path', '/home/ga/GMAT_output/srp_eccentricity_analysis.txt')
    if isinstance(analysis_file, dict) and analysis_file.get('exists'):
        temp_analysis = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(analysis_path, temp_analysis.name)
            with open(temp_analysis.name, 'r', encoding='utf-8', errors='ignore') as f:
                analysis_text = f.read()

            # Extract fields
            max_ecc_match = re.search(r'max_eccentricity:\s*([0-9]+\.?[0-9eE+-]*)', analysis_text)
            min_ecc_match = re.search(r'min_eccentricity:\s*([0-9]+\.?[0-9eE+-]*)', analysis_text)
            period_match = re.search(r'ecc_oscillation_period_days:\s*([0-9]+\.?[0-9]*)', analysis_text)
            sma_match = re.search(r'final_sma_km:\s*([0-9]+\.?[0-9]*)', analysis_text)
            srp_match = re.search(r'srp_enabled:\s*(true|false|True|False)', analysis_text)

            found_fields = sum(1 for x in [max_ecc_match, min_ecc_match, period_match, sma_match, srp_match] if x)

            if found_fields >= 4:
                total_score += scores["analysis_written"]
                feedback.append(f"Analysis report formatted correctly ({found_fields} fields found).")
            else:
                feedback.append(f"Analysis report missing required fields (only {found_fields} found).")

            # Validate Max Eccentricity
            if max_ecc_match:
                max_ecc = float(max_ecc_match.group(1))
                if max_ecc_min <= max_ecc <= max_ecc_max:
                    total_score += scores["max_ecc_valid"]
                    feedback.append(f"Max eccentricity realistic: {max_ecc:.5f}")
                else:
                    feedback.append(f"Max eccentricity unrealistic: {max_ecc:.5f} (expected {max_ecc_min}-{max_ecc_max})")

            # Validate Period
            if period_match:
                period = float(period_match.group(1))
                if period_min <= period <= period_max:
                    total_score += scores["ecc_period_valid"]
                    feedback.append(f"Eccentricity period valid: {period} days.")
                else:
                    feedback.append(f"Eccentricity period invalid: {period} days (expected ~365).")

            # Validate SMA stability
            if sma_match:
                final_sma = float(sma_match.group(1))
                if abs(final_sma - geo_sma) <= sma_tol:
                    total_score += scores["sma_stable"]
                    feedback.append(f"Final SMA stable: {final_sma:.2f} km.")
                else:
                    feedback.append(f"Final SMA drifted too much: {final_sma:.2f} km.")

        except Exception as e:
            feedback.append(f"Error parsing analysis file: {e}")
        finally:
            if os.path.exists(temp_analysis.name):
                os.unlink(temp_analysis.name)
    else:
        feedback.append("Analysis report not created.")

    # Determine Pass/Fail
    passed = total_score >= 60 and srp_is_enabled and report_is_generated

    if passed:
        feedback.insert(0, "SUCCESS: Task completed correctly.")
    else:
        feedback.insert(0, "FAILED: Did not meet minimum requirements.")

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }