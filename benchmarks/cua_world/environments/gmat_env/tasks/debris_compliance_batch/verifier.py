#!/usr/bin/env python3
"""
Verifier for debris_compliance_batch@1

Agent must simulate orbital decay for 5 satellites from a CSV manifest,
classify each for IADC 25-year PMD compliance, and produce a report.

Ground truth (from orbital mechanics):
  SAT_A: 600 km, CdA/m=0.0367 -> COMPLIANT (~18yr)
  SAT_B: 1200 km, CdA/m=0.0132 -> NON_COMPLIANT (>100yr)
  SAT_C: 500 km, CdA/m=0.0438 -> COMPLIANT (~10yr)
  SAT_D: 900 km, CdA/m=0.0133 -> NON_COMPLIANT (>25yr)
  SAT_E: 400 km, CdA/m=0.0391 -> COMPLIANT (~3yr)

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window
  - all_5_satellites_simulated (20): Script contains 5 spacecraft definitions
  - drag_configured (10): Drag atmosphere model in script
  - report_written (10): Report with all 5 satellite entries
  - sat_a_correct (10): SAT_A classified COMPLIANT
  - sat_b_correct (10): SAT_B classified NON_COMPLIANT
  - sat_c_correct (10): SAT_C classified COMPLIANT
  - sat_d_correct (10): SAT_D classified NON_COMPLIANT
  - sat_e_correct (10): SAT_E classified COMPLIANT
  - summary_counts_correct (10): Report summary line totals correct (3C, 2NC)
                                  Split: 5 pts each for compliant/noncompliant count

Pass condition: score >= 60 AND at least 4/5 satellites correctly classified
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_debris_compliance_batch(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_compliant = set(metadata.get('compliant_satellites', ['SAT_A', 'SAT_C', 'SAT_E']))
    expected_noncompliant = set(metadata.get('noncompliant_satellites', ['SAT_B', 'SAT_D']))
    expected_compliant_count = metadata.get('expected_compliant_count', 3)
    expected_noncompliant_count = metadata.get('expected_noncompliant_count', 2)

    scores = {
        "script_created": 10,
        "all_5_satellites": 20,
        "drag_configured": 10,
        "report_written": 10,
        "sat_a_correct": 10,
        "sat_b_correct": 10,
        "sat_c_correct": 10,
        "sat_d_correct": 10,
        "sat_e_correct": 10,
        "summary_correct": 10,
    }

    total_score = 0
    feedback = []
    correct_classifications = 0

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

    # 2. All 5 satellites simulated
    sat_count = task_result.get('satellite_count_in_script', 0)
    if isinstance(sat_count, str):
        try:
            sat_count = int(sat_count)
        except ValueError:
            sat_count = 0

    if sat_count >= 5:
        total_score += scores["all_5_satellites"]
        feedback.append(f"All 5 satellites defined in script ({sat_count} spacecraft found).")
    elif sat_count >= 3:
        total_score += scores["all_5_satellites"] // 2
        feedback.append(f"Only {sat_count}/5 satellites defined in script.")
    elif sat_count >= 1:
        total_score += scores["all_5_satellites"] // 4
        feedback.append(f"Only {sat_count}/5 satellites defined in script.")
    else:
        feedback.append("No spacecraft definitions found in script.")

    # 3. Drag configured in script
    script_path = task_result.get('script_path', '/home/ga/Documents/missions/debris_batch_analysis.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            if re.search(r'AtmosphereModel\s*=\s*(JacchiaRoberts|MSISE86|NRLMSISE00)', script_content):
                total_score += scores["drag_configured"]
                feedback.append("Drag atmosphere model configured.")
            elif "Drag" in script_content and "ForceModel" in script_content:
                total_score += scores["drag_configured"] // 2
                feedback.append("Drag force model present (atmosphere model not verified).")
            else:
                feedback.append("Drag atmosphere model not configured.")
        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 4. Report written
    report_file = task_result.get('report_file', {})
    report_path = task_result.get('report_path', '/home/ga/GMAT_output/debris_compliance_report.txt')
    report_rerun = task_result.get('report_file_rerun', report_file)
    effective_report = report_rerun if isinstance(report_rerun, dict) and report_rerun.get('exists') else report_file

    report_sat_count = task_result.get('report_satellite_count', 0)
    if isinstance(report_sat_count, str):
        try:
            report_sat_count = int(report_sat_count)
        except ValueError:
            report_sat_count = 0

    if isinstance(effective_report, dict) and effective_report.get('exists') and report_sat_count >= 3:
        total_score += scores["report_written"]
        feedback.append(f"Report written with {report_sat_count}/5 satellite entries.")
    elif isinstance(effective_report, dict) and effective_report.get('exists'):
        total_score += scores["report_written"] // 2
        feedback.append(f"Report exists but only {report_sat_count} satellite entries.")
    else:
        feedback.append("Compliance report not found or empty.")

    # 5. Individual satellite classifications
    sat_statuses = {
        'SAT_A': task_result.get('sat_a_status', 'unknown'),
        'SAT_B': task_result.get('sat_b_status', 'unknown'),
        'SAT_C': task_result.get('sat_c_status', 'unknown'),
        'SAT_D': task_result.get('sat_d_status', 'unknown'),
        'SAT_E': task_result.get('sat_e_status', 'unknown'),
    }

    score_keys = {
        'SAT_A': 'sat_a_correct',
        'SAT_B': 'sat_b_correct',
        'SAT_C': 'sat_c_correct',
        'SAT_D': 'sat_d_correct',
        'SAT_E': 'sat_e_correct',
    }

    for sat_name in ['SAT_A', 'SAT_B', 'SAT_C', 'SAT_D', 'SAT_E']:
        status = sat_statuses[sat_name]
        is_compliant_expected = sat_name in expected_compliant

        if is_compliant_expected:
            if status == 'compliant':
                total_score += scores[score_keys[sat_name]]
                correct_classifications += 1
                feedback.append(f"{sat_name}: COMPLIANT (correct).")
            elif status == 'non_compliant':
                feedback.append(f"{sat_name}: incorrectly classified as NON_COMPLIANT.")
            else:
                feedback.append(f"{sat_name}: not classified or status unknown.")
        else:  # expected non-compliant
            if status == 'non_compliant':
                total_score += scores[score_keys[sat_name]]
                correct_classifications += 1
                feedback.append(f"{sat_name}: NON_COMPLIANT (correct).")
            elif status == 'compliant':
                feedback.append(f"{sat_name}: incorrectly classified as COMPLIANT.")
            else:
                feedback.append(f"{sat_name}: not classified or status unknown.")

    # 6. Summary counts
    compliant_count = task_result.get('compliant_count', 0)
    noncompliant_count = task_result.get('noncompliant_count', 0)

    if isinstance(compliant_count, str):
        try:
            compliant_count = int(compliant_count)
        except ValueError:
            compliant_count = 0
    if isinstance(noncompliant_count, str):
        try:
            noncompliant_count = int(noncompliant_count)
        except ValueError:
            noncompliant_count = 0

    summary_pts = 0
    if compliant_count == expected_compliant_count:
        summary_pts += 5
        feedback.append(f"Compliant count correct: {compliant_count}.")
    else:
        feedback.append(f"Compliant count: {compliant_count} (expected {expected_compliant_count}).")

    if noncompliant_count == expected_noncompliant_count:
        summary_pts += 5
        feedback.append(f"Non-compliant count correct: {noncompliant_count}.")
    else:
        feedback.append(f"Non-compliant count: {noncompliant_count} (expected {expected_noncompliant_count}).")

    total_score += summary_pts

    passed = total_score >= 60 and correct_classifications >= 4

    return {
        "passed": passed,
        "score": min(total_score, 100),
        "feedback": " | ".join(feedback)
    }
