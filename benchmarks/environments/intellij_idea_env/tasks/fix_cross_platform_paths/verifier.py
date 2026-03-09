#!/usr/bin/env python3
"""
Verifier for fix_cross_platform_paths task.

Criteria:
1. Application runs successfully (Exit Code 0) [30 pts]
2. Report file generated with correct content [20 pts]
3. Main.java: No absolute Windows paths ("C:") [15 pts]
4. Main.java: No hardcoded backslashes ("\\") [15 pts]
5. ConfigLoader.java: Filename case fixed ("config.properties") [10 pts]
6. Files modified during task (Anti-gaming) [10 pts]
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_cross_platform_paths(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    run_exit_code = result.get('run_exit_code', 1)
    run_output = result.get('run_output', '')
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    main_src = result.get('main_source', '')
    config_src = result.get('config_source', '')
    files_modified = result.get('files_modified', False)

    # 1. Application Execution (30 pts)
    if run_exit_code == 0:
        score += 30
        feedback_parts.append("App compiled and ran successfully")
    else:
        feedback_parts.append(f"App execution failed (Exit Code {run_exit_code})")
        # Check logs for clues
        if "FileNotFoundException" in run_output:
            feedback_parts.append("Log: FileNotFoundException detected")
        elif "Compilation failure" in run_output:
            feedback_parts.append("Log: Compilation failed")

    # 2. Output Generation (20 pts)
    if report_exists:
        if "Total Items: 50" in report_content:
            score += 20
            feedback_parts.append("Report generated with correct data")
        else:
            score += 10
            feedback_parts.append("Report generated but content looks wrong")
    else:
        feedback_parts.append("Report file not generated")

    # 3. Main.java: Check for "C:" (15 pts)
    # Using raw string for regex to match literal backslashes
    if main_src:
        if re.search(r'C:\\', main_src, re.IGNORECASE) or re.search(r'"[A-Z]:\\\\', main_src):
            feedback_parts.append("Found hardcoded drive letter")
        else:
            score += 15
            feedback_parts.append("No hardcoded drive letters found")
    else:
        feedback_parts.append("Main.java source not found")

    # 4. Main.java: Check for hardcoded backslashes in paths (15 pts)
    # Allow backslashes only if inside replacement logic or comments, 
    # but simplest check is "path string shouldn't have double backslash"
    if main_src:
        # Looking for "something\\something" string literals
        # This regex looks for double backslashes inside quotes
        if re.search(r'"[^"]*\\\\[^"]*"', main_src):
            # Sometimes needed for regex replacement, so be careful.
            # If the user uses s.replace("\\", "/"), that's valid.
            # The bad code was: "output\\report.txt"
            if "output\\\\report.txt" in main_src or "data\\\\inventory.csv" in main_src:
                 feedback_parts.append("Found hardcoded path separators")
            else:
                 score += 15
                 feedback_parts.append("Path separators improved")
        else:
            score += 15
            feedback_parts.append("No hardcoded backslashes found")

    # 5. ConfigLoader.java: Check filename case (10 pts)
    if config_src:
        if 'config.properties' in config_src:
            score += 10
            feedback_parts.append("Config filename case fixed")
        elif 'Config.properties' in config_src:
             feedback_parts.append("Config filename still incorrect case")
        else:
             # Maybe they extracted it to a constant or passed it in
             feedback_parts.append("Config filename string not found (manual check needed?)")

    # 6. Anti-gaming (10 pts)
    if files_modified:
        score += 10
        feedback_parts.append("Source files were modified")
    else:
        feedback_parts.append("No source files modified (did you save?)")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }