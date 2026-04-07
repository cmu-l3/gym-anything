#!/usr/bin/env python3
"""
Verifier for redo_log_sizing_optimization task.

Target State:
- Exactly 3 Redo Log groups.
- Size of each group is 512MB (536,870,912 bytes).
- At least one group is CURRENT (system is operational).
- Evidence of ADD/DROP commands in history (Anti-gaming).

Scoring (100 pts):
- New groups created (512MB): 30 pts
- Old groups dropped (No 50MB groups): 30 pts
- Exact group count (3): 10 pts
- Correct directory usage: 10 pts
- Database Healthy (OPEN & CURRENT log exists): 20 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TARGET_SIZE = 536870912  # 512 * 1024 * 1024
OLD_SIZE = 52428800      # 50 * 1024 * 1024

def verify_redo_log_sizing(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result JSON
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "redo_log_result.json")
        try:
            copy_from_env("/tmp/redo_log_result.json", result_path)
            if not os.path.exists(result_path):
                return {"passed": False, "score": 0, "feedback": "Result file not found."}
            
            with open(result_path, "r") as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Database error during verification: {result['error']}"}

    groups = result.get("final_groups", [])
    total_groups = result.get("total_groups", 0)
    sizes = result.get("sizes_bytes", [])
    statuses = result.get("statuses", [])
    
    # 1. Check New Groups (30 pts)
    # Check if we have groups of the target size
    correct_sized_groups = [g for g in groups if g["bytes"] == TARGET_SIZE]
    if len(correct_sized_groups) >= 3:
        score += 30
        feedback_parts.append("Created 3+ groups of 512MB (+30)")
    elif len(correct_sized_groups) > 0:
        partial = len(correct_sized_groups) * 10
        score += partial
        feedback_parts.append(f"Created {len(correct_sized_groups)} groups of 512MB (+{partial})")
    else:
        feedback_parts.append("No groups of 512MB found (0 pts)")

    # 2. Check Old Groups Dropped (30 pts)
    # Ensure NO groups of 50MB exist
    old_sized_groups = [g for g in groups if g["bytes"] == OLD_SIZE]
    if len(old_sized_groups) == 0:
        score += 30
        feedback_parts.append("All 50MB groups removed (+30)")
    else:
        feedback_parts.append(f"Found {len(old_sized_groups)} old 50MB groups remaining (0 pts)")

    # 3. Exact Group Count (10 pts)
    if total_groups == 3:
        score += 10
        feedback_parts.append("Exact group count of 3 (+10)")
    else:
        feedback_parts.append(f"Group count is {total_groups} (expected 3) (0 pts)")

    # 4. Database Healthy / Status (20 pts)
    # Need at least one CURRENT log
    if "CURRENT" in statuses:
        score += 20
        feedback_parts.append("Database operational (CURRENT log exists) (+20)")
    else:
        feedback_parts.append("No CURRENT log found - Database may be hung or inactive (0 pts)")

    # 5. Directory Usage / File Paths (10 pts)
    # Check if paths look standard (usually /opt/oracle/oradata/XE/...)
    file_paths = result.get("file_paths", [])
    valid_paths = [p for p in file_paths if "oradata" in p or "XE" in p]
    if len(valid_paths) == len(file_paths) and len(file_paths) > 0:
        score += 10
        feedback_parts.append("Log files in correct location (+10)")
    else:
        feedback_parts.append("Log file paths look suspicious or missing (+0)")

    # Anti-gaming check (Implicit in size check, but explicit commands helps confidence)
    commands = result.get("commands_executed", [])
    if not commands:
        feedback_parts.append("(Note: No ADD/DROP commands found in SQL cache)")

    passed = (score >= 70) and ("CURRENT" in statuses)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }