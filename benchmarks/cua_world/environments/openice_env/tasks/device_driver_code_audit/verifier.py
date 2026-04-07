#!/usr/bin/env python3
"""Verifier for device_driver_code_audit task.

Verifies that the agent:
1. Explored the OpenICE source code.
2. Identified correct manufacturer driver paths.
3. Created a report with accurate findings.
4. Correctly identified simulation availability.

Scoring (100 points):
- Report exists and created during task (20 pts)
- Report lists at least 4 manufacturers (20 pts)
- Report contains valid filesystem paths (confirmed by export script) (20 pts)
- Report identifies known OpenICE manufacturers (e.g., Philips, Masimo) (20 pts)
- OpenICE app was running (checking GUI availability) (20 pts)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

KNOWN_MANUFACTURERS = [
    "philips", "masimo", "draeger", "nellcor", "nonin", 
    "ivy", "cpc", "fluke", "orion", "puritan", "bennett"
]

def verify_device_driver_code_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    subscores = {}

    task_start = result.get('task_start_timestamp', 0)
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', "").lower()
    
    # Criterion 1: Report exists and created during task (20 pts)
    report_mtime = result.get('report_mtime', 0)
    created_during_task = int(report_mtime) > task_start
    
    if report_exists and created_during_task:
        score += 20
        subscores['report_file'] = 20
        feedback_parts.append("Report file created during task")
    elif report_exists:
        score += 10
        subscores['report_file'] = 10
        feedback_parts.append("Report file exists but timestamp is old")
    else:
        subscores['report_file'] = 0
        feedback_parts.append("Report file not found")

    # Criterion 2: Manufacturers count (20 pts)
    # We use a heuristic from the export script + python parsing
    declared_count = result.get('manufacturers_count', 0)
    
    # Fallback counting if export script logic was too simple
    lines = report_content.split('\\n')
    valid_entries = 0
    for line in lines:
        if "manufacturer" in line or "brand" in line:
            valid_entries += 1
            
    final_count = max(declared_count, valid_entries)
    
    if final_count >= 4:
        score += 20
        subscores['count'] = 20
        feedback_parts.append(f"Found {final_count} manufacturer entries")
    elif final_count >= 1:
        score += 10
        subscores['count'] = 10
        feedback_parts.append(f"Found only {final_count}/4 manufacturer entries")
    else:
        subscores['count'] = 0
        feedback_parts.append("No manufacturer entries identified")

    # Criterion 3: Valid paths (20 pts)
    valid_paths = result.get('valid_paths_found', 0)
    if valid_paths >= 4:
        score += 20
        subscores['paths'] = 20
        feedback_parts.append(f"Verified {valid_paths} valid source code paths")
    elif valid_paths >= 1:
        score += 10
        subscores['paths'] = 10
        feedback_parts.append(f"Verified {valid_paths}/4 valid source code paths")
    else:
        subscores['paths'] = 0
        feedback_parts.append("No valid source code paths found in report")

    # Criterion 4: Known manufacturers content check (20 pts)
    found_known = 0
    for mfg in KNOWN_MANUFACTURERS:
        if mfg in report_content:
            found_known += 1
            
    if found_known >= 3:
        score += 20
        subscores['content'] = 20
        feedback_parts.append(f"Content mentions known brands: {found_known}")
    elif found_known >= 1:
        score += 10
        subscores['content'] = 10
        feedback_parts.append(f"Content mentions few known brands: {found_known}")
    else:
        subscores['content'] = 0
        feedback_parts.append("Content does not mention standard OpenICE drivers")

    # Criterion 5: OpenICE Running (20 pts)
    # Important because they needed to check the GUI for simulators
    if result.get('openice_running', False):
        score += 20
        subscores['app_running'] = 20
        feedback_parts.append("OpenICE application active")
    else:
        subscores['app_running'] = 0
        feedback_parts.append("OpenICE application not running")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "valid_paths": valid_paths,
            "manufacturers_found": final_count,
            "known_brands_match": found_known
        }
    }