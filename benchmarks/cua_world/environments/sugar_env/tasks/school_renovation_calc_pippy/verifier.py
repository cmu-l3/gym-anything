#!/usr/bin/env python3
"""
Verifier for school_renovation_calc_pippy task.
Evaluates if the Python script and resulting calculation report exist, 
and mathematically validates the outputs.
"""

import json
import os
import tempfile
import re

def verify_school_renovation_calc(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Target Values
    exp_floor = metadata.get('expected_total_floor', 2939.5)
    exp_wall = metadata.get('expected_total_wall', 4266.2)
    exp_buckets = metadata.get('expected_buckets', 43)
    exp_lib_floor = metadata.get('library_expected_floor', 180)
    exp_lib_wall = metadata.get('library_expected_wall', 189)

    # Temporary files
    res_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    script_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    report_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')

    score = 0
    feedback = []

    try:
        # Load main result JSON
        copy_from_env("/tmp/task_result.json", res_file.name)
        with open(res_file.name, 'r') as f:
            result = json.load(f)
            
        script_exists = result.get('script_exists', False)
        report_exists = result.get('report_exists', False)

        # CRITERION 1: Script exists (10 points)
        if script_exists:
            score += 10
            feedback.append("Python script created.")
            copy_from_env("/home/ga/Documents/renovation_calc.py", script_file.name)
            with open(script_file.name, 'r') as f:
                script_content = f.read()
        else:
            feedback.append("FAIL: renovation_calc.py missing.")
            script_content = ""

        # Anti-gaming checks on script content
        has_file_io = "open" in script_content or "csv" in script_content
        has_loop = "for " in script_content or "while " in script_content

        # CRITERION 2: Report exists (10 points)
        if report_exists:
            score += 10
            feedback.append("Report file created.")
            copy_from_env("/home/ga/Documents/renovation_report.txt", report_file.name)
            with open(report_file.name, 'r') as f:
                report_content = f.read()
        else:
            feedback.append("FAIL: renovation_report.txt missing.")
            report_content = ""

        if not report_exists:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

        # Parse ALL numbers out of the report for highly robust matching
        # Handles 2939.5, 2939.50, 43.0, 43, etc.
        numbers_in_report = []
        for match in re.findall(r'\d+\.\d+|\d+', report_content):
            try:
                numbers_in_report.append(float(match))
            except ValueError:
                pass

        # CRITERION 3: Library Main room calculation check (20 points)
        has_lib_f = any(abs(n - exp_lib_floor) < 0.1 for n in numbers_in_report)
        has_lib_w = any(abs(n - exp_lib_wall) < 0.1 for n in numbers_in_report)
        if has_lib_f and has_lib_w:
            score += 20
            feedback.append(f"Library individual calculations correct ({exp_lib_floor}, {exp_lib_wall}).")
        else:
            feedback.append("Missing or incorrect individual room calculations in report.")

        # CRITERION 4: Total Floor Area check (20 points)
        if any(abs(n - exp_floor) < 0.1 for n in numbers_in_report):
            score += 20
            feedback.append(f"Total Floor Area correct ({exp_floor}).")
        else:
            feedback.append("Incorrect Total Floor Area.")

        # CRITERION 5: Total Wall Area check (20 points)
        if any(abs(n - exp_wall) < 0.1 for n in numbers_in_report):
            score += 20
            feedback.append(f"Total Wall Area correct ({exp_wall}).")
        else:
            feedback.append("Incorrect Total Wall Area.")

        # CRITERION 6: Paint Buckets check (20 points)
        if any(n == exp_buckets for n in numbers_in_report):
            score += 20
            feedback.append(f"Paint Buckets correct ({exp_buckets}).")
        else:
            feedback.append("Incorrect Paint Buckets count.")

        # Evaluate Anti-Gaming (Deduct if script lacks basics but report is perfect)
        if score > 50 and not (has_file_io and has_loop):
            feedback.append("WARNING: Script lacks file I/O or loops. Possible hardcoded answer.")
            score = max(0, score - 50)  # Heavy penalty for hardcoding

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        for tmp in [res_file, script_file, report_file]:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    passed = score >= 70 and (has_file_io and has_loop)
    
    if passed:
        feedback.append("SUCCESS: Renovation calculations are correct!")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }