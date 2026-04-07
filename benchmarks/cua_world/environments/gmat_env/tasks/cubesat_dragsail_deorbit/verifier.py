#!/usr/bin/env python3
"""
Verifier for cubesat_dragsail_deorbit@1

Agent must simulate a 1-year CubeSat operational phase, use an Assignment command
to deploy a drag sail (DragArea = 2.5), and propagate to re-entry (120 km).

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window
  - drag_force_model (10): JacchiaRoberts or MSISE atmosphere model used
  - multi_phase_sequence (15): >= 2 Propagate commands in Mission Sequence
  - sail_deployment_logic (25): DragArea is modified to ~2.5 mid-sequence
  - report_generated (10): Compliance report written with required fields
  - altitude_valid (10): Deployment altitude in [600, 625] km
  - lifetime_valid (10): Total lifetime in [400, 1800] days
  - compliance_correct (10): Status is COMPLIANT

Pass condition: score >= 60 AND multi_phase_sequence AND sail_deployment_logic
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cubesat_dragsail_deorbit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    alt_min = metadata.get('altitude_deployment_min_km', 600.0)
    alt_max = metadata.get('altitude_deployment_max_km', 625.0)
    life_min = metadata.get('lifetime_min_days', 400.0)
    life_max = metadata.get('lifetime_max_days', 1800.0)

    scores = {
        "script_created": 10,
        "drag_force_model": 10,
        "multi_phase_sequence": 15,
        "sail_deployment_logic": 25,
        "report_generated": 10,
        "altitude_valid": 10,
        "lifetime_valid": 10,
        "compliance_correct": 10,
    }

    total_score = 0
    feedback = []
    logic_ok = False
    deployment_ok = False

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

    # 2. Analyze script content
    script_path = task_result.get('script_path', '/home/ga/Documents/missions/dragsail_mission.script')
    script_content = ""
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check Atmosphere Model
            if re.search(r'AtmosphereModel\s*=\s*(JacchiaRoberts|MSISE86|NRLMSISE00)', script_content):
                total_score += scores["drag_force_model"]
                feedback.append("Drag atmosphere model configured.")
            else:
                feedback.append("Drag atmosphere model missing.")

            # Analyze Mission Sequence
            parts = script_content.split('BeginMissionSequence')
            if len(parts) > 1:
                mission_seq = parts[1]
                
                # Count Propagate commands
                propagate_count = len(re.findall(r'\bPropagate\b', mission_seq))
                if propagate_count >= 2:
                    total_score += scores["multi_phase_sequence"]
                    logic_ok = True
                    feedback.append(f"Multi-phase sequence detected ({propagate_count} Propagate commands).")
                else:
                    feedback.append(f"Mission sequence only has {propagate_count} Propagate command(s) - expected >= 2.")

                # Check for DragArea assignment in sequence
                # Look for ".DragArea = 2.5" or similar
                drag_assignments = re.findall(r'\.DragArea\s*=\s*([0-9.]+)', mission_seq)
                has_deployment = False
                for val in drag_assignments:
                    try:
                        if float(val) > 1.0: # Identifies the 2.5 assignment vs the 0.06
                            has_deployment = True
                    except ValueError:
                        pass
                
                if has_deployment:
                    total_score += scores["sail_deployment_logic"]
                    deployment_ok = True
                    feedback.append("DragArea assignment (sail deployment) found in mission sequence.")
                else:
                    feedback.append("No DragArea increase found in mission sequence.")
            else:
                feedback.append("No BeginMissionSequence block found in script.")
        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Script file not found.")

    # 3. Analyze Report
    report_file = task_result.get('report_file', {})
    report_path = task_result.get('report_path', '/home/ga/GMAT_output/dragsail_compliance_report.txt')
    if isinstance(report_file, dict) and report_file.get('exists'):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()

            total_score += scores["report_generated"]
            feedback.append("Compliance report generated.")

            # Extract values
            alt_match = re.search(r'altitude_at_deployment_km\s*:\s*([0-9.]+)', report_content, re.IGNORECASE)
            life_match = re.search(r'total_lifetime_days\s*:\s*([0-9.]+)', report_content, re.IGNORECASE)
            status_match = re.search(r'compliance_status\s*:\s*([A-Z_]+)', report_content, re.IGNORECASE)

            # Check Altitude
            if alt_match:
                try:
                    alt_val = float(alt_match.group(1))
                    if alt_min <= alt_val <= alt_max:
                        total_score += scores["altitude_valid"]
                        feedback.append(f"Deployment altitude valid: {alt_val:.2f} km.")
                    else:
                        feedback.append(f"Deployment altitude {alt_val:.2f} km outside expected range [{alt_min}, {alt_max}].")
                except ValueError:
                    feedback.append("Could not parse deployment altitude.")
            else:
                feedback.append("Deployment altitude missing from report.")

            # Check Lifetime
            if life_match:
                try:
                    life_val = float(life_match.group(1))
                    if life_min <= life_val <= life_max:
                        total_score += scores["lifetime_valid"]
                        feedback.append(f"Total lifetime valid: {life_val:.1f} days.")
                    else:
                        feedback.append(f"Total lifetime {life_val:.1f} days outside expected range [{life_min}, {life_max}].")
                except ValueError:
                    feedback.append("Could not parse total lifetime.")
            else:
                feedback.append("Total lifetime missing from report.")

            # Check Compliance
            if status_match:
                status = status_match.group(1).strip()
                if status == "COMPLIANT":
                    total_score += scores["compliance_correct"]
                    feedback.append("Compliance status correctly evaluated as COMPLIANT.")
                else:
                    feedback.append(f"Incorrect compliance status: {status}.")
            else:
                feedback.append("Compliance status missing from report.")

        except Exception as e:
            feedback.append(f"Error reading report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback.append("Compliance report not found.")

    passed = (total_score >= 60) and logic_ok and deployment_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }