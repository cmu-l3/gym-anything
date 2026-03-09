#!/usr/bin/env python3
"""
Verifier for fix_containerized_cron_job.

Checks:
1. Container 'sales-cron' is running.
2. A NEW report file was automatically generated during the 70s wait period in export_result.sh.
   (This confirms cron is actually scheduling the job, not just a manual run).
3. The report content is valid JSON and contains the correct sum for 'NorthAmerica' (350.5).
   (This confirms env vars are correctly injected).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_containerized_cron_job(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_amount = metadata.get('expected_total_amount', 350.50)
    expected_count = metadata.get('expected_transaction_count', 3)
    target_region = metadata.get('target_region', 'NorthAmerica')

    # Read result
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
    
    # Criterion 1: Container Running (20 pts)
    if result.get('container_running', False):
        score += 20
        feedback_parts.append("Container is running (+20)")
    else:
        feedback_parts.append("Container NOT running")

    # Criterion 2: Automatic Execution (40 pts)
    # The export script cleared files and waited 70s. New files implies cron worked.
    auto_gen = result.get('automatic_generation', False)
    if auto_gen:
        score += 40
        feedback_parts.append("Cron job successfully generated report automatically (+40)")
    else:
        feedback_parts.append("No report generated automatically during wait period")

    # Criterion 3: Data Correctness (40 pts)
    # Checks if env vars were passed correctly (required for correct filtering)
    content = result.get('report_content', {})
    
    correct_data = False
    if isinstance(content, dict) and content:
        actual_total = content.get('total_amount', 0)
        actual_region = content.get('region', '')
        
        # Tolerance for float comparison
        if abs(actual_total - expected_amount) < 0.01 and actual_region == target_region:
            score += 40
            feedback_parts.append(f"Report data correct: Region={actual_region}, Total={actual_total} (+40)")
            correct_data = True
        else:
            feedback_parts.append(f"Report data incorrect. Expected {target_region}/{expected_amount}, got {actual_region}/{actual_total}")
    else:
        if auto_gen:
             feedback_parts.append("Generated file was empty or invalid JSON")

    # Bonus: Check if they modified the files (just for feedback, not score)
    if result.get('entrypoint_modified', False) or result.get('crontab_modified', False):
        feedback_parts.append("(Config files modified as expected)")

    passed = (score >= 90) # Requires running + auto gen + correct data

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }