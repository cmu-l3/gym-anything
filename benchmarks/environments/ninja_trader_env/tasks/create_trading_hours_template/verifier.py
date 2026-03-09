#!/usr/bin/env python3
"""
Verifier for create_trading_hours_template task.

Verifies:
1. "US Morning Session" template exists in NinjaTrader XML data.
2. Session times are correct (09:30 - 12:00).
3. AAPL Chart exists in a workspace.
4. Chart uses the custom Trading Hours template.
5. Files were modified during the task (anti-gaming).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_trading_hours_template(traj, env_info, task_info):
    """
    Verify the creation and application of a custom Trading Hours template.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # File path inside the container (Windows path mapped to standard output location)
    # The export script writes to C:\Users\Docker\Desktop\task_result.json
    # We need to use the linux path representation if mounted, or just the path the agent sees?
    # Usually copy_from_env takes the path inside the VM/Container.
    # In 'ninja_trader_env', it's a Windows container/VM. 
    # Paths are Windows paths.
    result_path = "C:\\Users\\Docker\\Desktop\\task_result.json"

    score = 0
    feedback_parts = []
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env(result_path, temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse result file: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Check if template was found (25 pts)
    if result.get("template_found", False):
        score += 25
        feedback_parts.append("Template 'US Morning Session' found (+25)")
    else:
        feedback_parts.append("Template 'US Morning Session' NOT found")
        # Critical failure if template doesn't exist at all
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check session times (20 pts)
    if result.get("session_times_correct", False):
        score += 20
        feedback_parts.append("Session times 9:30-12:00 confirmed (+20)")
    else:
        feedback_parts.append("Session times incorrect or could not be parsed")

    # 3. Check AAPL chart existence (20 pts)
    if result.get("aapl_chart_found", False):
        score += 20
        feedback_parts.append("AAPL chart configuration found (+20)")
    else:
        feedback_parts.append("AAPL chart configuration NOT found")

    # 4. Check application to chart (20 pts)
    if result.get("template_applied_to_chart", False):
        score += 20
        feedback_parts.append("Template correctly applied to AAPL chart (+20)")
    else:
        feedback_parts.append("Template NOT applied to AAPL chart")

    # 5. Anti-gaming: File modification check (15 pts)
    if result.get("file_modified_during_task", False):
        score += 15
        feedback_parts.append("Work saved during task (+15)")
    else:
        feedback_parts.append("Files not modified during task session (Possible pre-existing data)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }