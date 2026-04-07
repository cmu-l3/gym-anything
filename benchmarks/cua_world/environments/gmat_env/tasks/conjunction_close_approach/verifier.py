#!/usr/bin/env python3
"""
Verifier for conjunction_close_approach@1

Verification Strategy:
  - script_created: 10 pts (Script was successfully saved)
  - two_spacecraft_defined: 15 pts (Two objects modeled)
  - force_model_configured: 5 pts (Drag modeled)
  - distance_computation: 15 pts (Logic for calculating relative distances)
  - propagation_72h: 10 pts (Duration is correct)
  - report_file_generated: 5 pts (Report file saved properly)
  - assessment_written: 10 pts (Required fields format followed)
  - tca_reasonable: 10 pts (Time of closest approach is populated)
  - miss_distance_plausible: 10 pts (Distance falls in realistic ranges <100km)
  - recommendation_valid: 10 pts (Logical match between distance and recommendation)

Pass condition: >= 55 AND two_spacecraft_defined AND distance_computation
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_conjunction_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    scores = {
        "script_created": 10,
        "two_spacecraft_defined": 15,
        "force_model_configured": 5,
        "distance_computation": 15,
        "propagation_72h": 10,
        "report_file_generated": 5,
        "assessment_written": 10,
        "tca_reasonable": 10,
        "miss_distance_plausible": 10,
        "recommendation_valid": 10
    }

    total_score = 0
    feedback = []
    sc_ok = False
    dist_ok = False

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

    # 1. Verify Script Creation
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Analyze Script Components
    script_path = task_result.get('script_path', '/home/ga/Documents/missions/conjunction_assessment.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Spacecraft check
            sc_count = len(re.findall(r'Create\s+Spacecraft', script_content, re.IGNORECASE))
            if sc_count >= 2:
                total_score += scores["two_spacecraft_defined"]
                sc_ok = True
                feedback.append("Two spacecraft defined in script.")
            elif sc_count == 1:
                total_score += scores["two_spacecraft_defined"] // 2
                feedback.append("Only one spacecraft defined.")
            else:
                feedback.append("No spacecraft defined.")

            # ForceModel check
            if re.search(r'AtmosphereModel|Drag', script_content, re.IGNORECASE):
                total_score += scores["force_model_configured"]
                feedback.append("ForceModel configured with drag.")
            else:
                feedback.append("Drag not configured in ForceModel.")

            # Distance computation check
            if re.search(r'sqrt|dist|distance|rel|mag|norm', script_content, re.IGNORECASE):
                total_score += scores["distance_computation"]
                dist_ok = True
                feedback.append("Distance computation logic found.")
            else:
                feedback.append("Distance computation not found.")

            # Propagation check
            if re.search(r'Propagate.*ElapsedDays\s*<\s*([3-9]|\d{2,})', script_content, re.IGNORECASE) or \
               re.search(r'Propagate.*ElapsedSecs\s*<\s*([2-9]\d{5,})', script_content, re.IGNORECASE) or \
               re.search(r'Propagate.*[A-Za-z0-9_]*\s*,\s*[A-Za-z0-9_]*', script_content, re.IGNORECASE):
                total_score += scores["propagation_72h"]
                feedback.append("Propagation logic found.")
            else:
                feedback.append("No propagation logic found.")

        except Exception as e:
            feedback.append(f"Could not read script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Script file does not exist.")

    # 3. Reference Ground Truth
    gt_exists = task_result.get('gt_exists', False)
    gt_dist = 15.2
    if gt_exists:
        gt_path = task_result.get('gt_path', '/var/lib/gmat_ground_truth/gt_results.json')
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(gt_path, temp_gt.name)
            with open(temp_gt.name, 'r') as f:
                gt_data = json.load(f)
                gt_dist = float(gt_data.get('min_dist_km', 15.2))
        except Exception as e:
            logger.warning(f"Could not read ground truth: {e}")
        finally:
            if os.path.exists(temp_gt.name):
                os.unlink(temp_gt.name)

    # 4. Report Analysis
    report_file = task_result.get('report_file', {})
    report_path = task_result.get('report_path', '/home/ga/GMAT_output/conjunction_assessment.txt')
    if isinstance(report_file, dict) and report_file.get('exists'):
        total_score += scores["report_file_generated"]
        feedback.append("Report file generated.")

        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()

            tca_match = re.search(r'TCA:\s*(.*)', report_content, re.IGNORECASE)
            miss_match = re.search(r'MISS_DISTANCE_KM:\s*([0-9]+\.?[0-9]*)', report_content, re.IGNORECASE)
            rec_match = re.search(r'RECOMMENDATION:\s*(MANEUVER_REQUIRED|MONITOR|NO_ACTION)', report_content, re.IGNORECASE)
            dv_match = re.search(r'AVOIDANCE_DV_MS:\s*([0-9]+\.?[0-9]*)', report_content, re.IGNORECASE)

            fields_found = sum([bool(tca_match), bool(miss_match), bool(rec_match), bool(dv_match)])
            if fields_found >= 3:
                total_score += scores["assessment_written"]
                feedback.append(f"Assessment written with {fields_found}/4 fields.")
            elif fields_found > 0:
                total_score += scores["assessment_written"] // 2
                feedback.append(f"Assessment incomplete ({fields_found}/4 fields).")
            else:
                feedback.append("Assessment fields not found.")

            # TCA Check
            if tca_match and len(tca_match.group(1).strip()) > 0:
                total_score += scores["tca_reasonable"]
                feedback.append("TCA provided.")
            
            # Miss distance check
            if miss_match:
                agent_dist = float(miss_match.group(1))
                if agent_dist < 100.0:  # Distance check for plausible intersection ranges
                    total_score += scores["miss_distance_plausible"]
                    feedback.append(f"Miss distance plausible ({agent_dist:.2f} km).")
                else:
                    feedback.append(f"Miss distance implausible ({agent_dist:.2f} km).")
            else:
                agent_dist = 999.0

            # Recommendation Check
            if rec_match:
                rec = rec_match.group(1).upper()
                dv = float(dv_match.group(1)) if dv_match else 0.0

                if agent_dist < 1.0:
                    if rec == "MANEUVER_REQUIRED" and 0.001 <= dv <= 5.0:
                        total_score += scores["recommendation_valid"]
                        feedback.append(f"Correct recommendation (MANEUVER_REQUIRED, DV={dv:.3f}).")
                    elif rec == "MANEUVER_REQUIRED":
                        total_score += scores["recommendation_valid"] // 2
                        feedback.append("Correct recommendation, but DV missing or out of bounds.")
                    else:
                        feedback.append("Incorrect recommendation for < 1km miss.")
                else:
                    if rec in ["MONITOR", "NO_ACTION"]:
                        total_score += scores["recommendation_valid"]
                        feedback.append(f"Correct recommendation ({rec}).")
                    else:
                        feedback.append(f"Incorrect recommendation ({rec}) for > 1km miss.")

        except Exception as e:
            feedback.append(f"Could not read assessment report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback.append("Report file not generated.")

    passed = (total_score >= 55) and sc_ok and dist_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }