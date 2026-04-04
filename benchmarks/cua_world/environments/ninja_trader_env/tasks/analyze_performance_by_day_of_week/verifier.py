#!/usr/bin/env python3
"""
Verifier for Analyze Performance by Day of Week task in NinjaTrader 8.

Verifies:
1. CSV export exists and was created during the task.
2. CSV contains specific "Day of Week" analysis data (Monday-Friday rows).
3. Workspace was saved.
4. Data logic (total trades > 0).

Scores:
- Export file exists and created during task: 30 pts
- Correct analysis type (Monday-Friday rows found): 40 pts
- Workspace saved: 15 pts
- Reasonable trade data (sum of trades > 10): 15 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_performance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Result JSON path in the Windows container (mapped to temp via export script)
    # The export_result.ps1 saves to C:\Users\Docker\AppData\Local\Temp\task_result.json
    # In the Linux context of copy_from_env, we typically use the path mapped. 
    # NOTE: Assuming the framework handles the path translation or we use the specific path.
    # For NinjaTrader env, it's often easiest to pull from the mapped /tmp or specific location.
    # The export script above used Windows temp. Let's assume standard path translation or 
    # that we should pull from where we know we can access. 
    # ADJUSTMENT: The export_result.ps1 saves to a Windows path. 
    # We will try to copy from that Windows path if the copy_from_env supports it, 
    # or assume the environment maps /tmp. 
    # A safe bet in gym-anything windows envs is often a specific C: path.
    
    remote_json_path = "C:/Users/Docker/AppData/Local/Temp/task_result.json"

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_json_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Output File Check (30 pts)
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if output_exists and created_during:
        score += 30
        feedback_parts.append("CSV exported correctly (+30)")
    elif output_exists:
        score += 10
        feedback_parts.append("CSV exists but timestamp verification failed (+10)")
    else:
        feedback_parts.append("No CSV export found (0)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Content Analysis (40 pts)
    # Did the agent switch to "Day of Week" mode?
    days_found = result.get('days_found', [])
    has_day_rows = result.get('has_day_rows', False)
    
    required_days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    matching_days = [d for d in required_days if d in days_found]
    
    if len(matching_days) >= 5:
        score += 40
        feedback_parts.append("Day of Week analysis verified (+40)")
    elif len(matching_days) > 0:
        partial = int(40 * (len(matching_days) / 5))
        score += partial
        feedback_parts.append(f"Partial Day of Week data ({len(matching_days)}/5 days) (+{partial})")
    else:
        feedback_parts.append("CSV content does not look like Day of Week analysis (0)")

    # 3. Workspace Persistence (15 pts)
    if result.get('workspace_modified', False):
        score += 15
        feedback_parts.append("Workspace saved (+15)")
    else:
        feedback_parts.append("Workspace not saved (0)")

    # 4. Data Validity (15 pts)
    # Check if we actually ran a backtest (trades > 0)
    total_trades = result.get('total_trades_sum', 0)
    if total_trades >= 10:
        score += 15
        feedback_parts.append(f"Trade data valid ({total_trades} trades) (+15)")
    elif total_trades > 0:
        score += 10
        feedback_parts.append(f"Trade data present but low count ({total_trades}) (+10)")
    else:
        feedback_parts.append("No trades found in export (0)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }