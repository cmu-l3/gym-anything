#!/usr/bin/env python3
"""
Verifier for agile_eo_target_accessibility@1

Agent must translate a 30-degree off-nadir constraint into a Ground Station Minimum Elevation Angle
and determine access windows for three targets.

Mathematical derivation:
Re = 6378.1363 km
H = 500.0 km
r = Re + H = 6878.1363 km
Nadir angle eta = 30 deg
By Law of Sines: Re / sin(eta) = r / sin(90 + elevation)
cos(elevation) = (r / Re) * sin(eta) = (6878.1363 / 6378.1363) * 0.5 = 0.539196
elevation = acos(0.539196) = 57.37 deg

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window
  - targets_defined (20): All three GroundStations (DC, Beijing, Moscow) defined
  - constraint_applied (30): MinimumElevationAngle set to ~56-58.5 deg (or ConicalFOV = 60)
  - locator_configured (15): ContactLocator present
  - propagation_correct (10): Propagation set for 3 days
  - summary_written (15): accessibility_summary.txt contains counts for all 3 cities

Pass condition: score >= 60 AND constraint_applied AND targets_defined
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_agile_eo_target_accessibility(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_elev = metadata.get('min_elevation_min_deg', 56.0)
    max_elev = metadata.get('min_elevation_max_deg', 58.5)
    fov_min = metadata.get('fov_angle_min_deg', 59.9)
    fov_max = metadata.get('fov_angle_max_deg', 60.1)

    scores = {
        "script_created": 10,
        "targets_defined": 20,
        "constraint_applied": 30,
        "locator_configured": 15,
        "propagation_correct": 10,
        "summary_written": 15,
    }

    total_score = 0
    feedback = []
    constraint_ok = False
    targets_ok = False

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

    # Parse Script
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/agile_targeting.script')
    script_content = ""
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # 2. Targets defined
            has_gs = "Create GroundStation" in script_content or "GroundStation" in script_content
            # Check cities by name or rough lat/lon
            has_dc = bool(re.search(r'(Washington|DC|38\.9)', script_content, re.IGNORECASE))
            has_beijing = bool(re.search(r'(Beijing|39\.9)', script_content, re.IGNORECASE))
            has_moscow = bool(re.search(r'(Moscow|55\.7)', script_content, re.IGNORECASE))
            
            if has_gs and has_dc and has_beijing and has_moscow:
                total_score += scores["targets_defined"]
                targets_ok = True
                feedback.append("All three targets (DC, Beijing, Moscow) defined in script.")
            elif has_gs and (has_dc or has_beijing or has_moscow):
                total_score += scores["targets_defined"] // 2
                feedback.append("Some but not all targets defined in script.")
            else:
                feedback.append("Targets not properly defined in script.")

            # 3. Constraint applied
            elev_matches = re.findall(r'MinimumElevationAngle\s*=\s*([0-9.]+)', script_content)
            fov_matches = re.findall(r'FieldOfView\s*=\s*([0-9.]+)', script_content)
            fov_half_matches = re.findall(r'ConeAngle\s*=\s*([0-9.]+)', script_content) # Alternate FOV property

            applied = False
            found_vals = []
            
            for val_str in elev_matches:
                try:
                    val = float(val_str)
                    found_vals.append(f"MinElev={val}")
                    if min_elev <= val <= max_elev:
                        applied = True
                except ValueError:
                    pass

            for val_str in fov_matches + fov_half_matches:
                try:
                    val = float(val_str)
                    found_vals.append(f"FOV={val}")
                    # Allow either full cone (60) or half cone (30) if they used a ConicalFOV
                    if (fov_min <= val <= fov_max) or (29.9 <= val <= 30.1):
                        applied = True
                except ValueError:
                    pass
            
            if applied:
                total_score += scores["constraint_applied"]
                constraint_ok = True
                feedback.append("Correct off-nadir constraint translated and applied (~57.4 deg min elevation or 60 deg FOV).")
            else:
                if found_vals:
                    feedback.append(f"Constraint applied incorrectly. Found: {', '.join(found_vals)} (Expected MinElev ~57.4 deg). Note: 90-30=60 is flat-earth approximation and is inaccurate.")
                else:
                    feedback.append("Constraint (MinimumElevationAngle or FieldOfView) not found in script.")

            # 4. Locator configured
            if "Create ContactLocator" in script_content or "ContactLocator" in script_content:
                total_score += scores["locator_configured"]
                feedback.append("ContactLocator configured.")
            else:
                feedback.append("ContactLocator missing from script.")

            # 5. Propagation correct (3 days)
            if bool(re.search(r'ElapsedDays\s*=\s*3(\.0+)?\b', script_content)) or bool(re.search(r'ElapsedSecs\s*=\s*259200', script_content)):
                total_score += scores["propagation_correct"]
                feedback.append("Propagation correctly set to 3 days.")
            else:
                feedback.append("Propagation not set to 3 days.")

        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 6. Summary written
    report_file = task_result.get('report_file', {})
    report_path = task_result.get('report_path', '/home/ga/GMAT_output/accessibility_summary.txt')
    if isinstance(report_file, dict) and report_file.get('exists'):
        temp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_rpt.name)
            with open(temp_rpt.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()

            has_dc = bool(re.search(r'(Washington|DC)', report_content, re.IGNORECASE))
            has_beijing = bool(re.search(r'Beijing', report_content, re.IGNORECASE))
            has_moscow = bool(re.search(r'Moscow', report_content, re.IGNORECASE))
            has_numbers = bool(re.search(r'[0-9]+', report_content))
            
            if has_dc and has_beijing and has_moscow and has_numbers:
                total_score += scores["summary_written"]
                feedback.append("Summary report contains required cities and numerical counts.")
            elif has_numbers:
                total_score += scores["summary_written"] // 2
                feedback.append("Summary report has numbers but is missing some city names.")
            else:
                feedback.append("Summary report does not contain valid pass counts.")
                
        except Exception as e:
            feedback.append(f"Error reading report: {e}")
        finally:
            if os.path.exists(temp_rpt.name):
                os.unlink(temp_rpt.name)
    else:
        feedback.append("Summary report not found.")

    key_criteria_met = constraint_ok and targets_ok
    passed = (total_score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }