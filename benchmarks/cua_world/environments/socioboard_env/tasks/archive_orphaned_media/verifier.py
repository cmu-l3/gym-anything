#!/usr/bin/env python3
"""
Verifier for archive_orphaned_media task.

Evaluates the agent's ability to cross-reference physical files with database records
and perform a safe system administration operation. Heavy penalties apply for modifying active data.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_archive_orphaned(traj, env_info, task_info):
    """
    Verify the sysadmin reconciliation task.
    
    Scoring:
    1. Active Integrity (35 points) - MUST BE PERFECT or score zeroes out.
    2. Orphans Archived (40 points) - Proportional to orphans correctly moved.
    3. Source Cleaned (15 points) - No orphans left behind.
    4. Report Accuracy (10 points) - Integer in report matches actual orphans.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env missing"}

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

    # Extract ground truth sets
    gt = result.get('ground_truth', {})
    gt_active = set(gt.get('active_files', []))
    gt_orphan = set(gt.get('orphan_files', []))

    # Extract current file system state
    src_files = set(result.get('src_files', []))
    archive_files = set(result.get('archive_files', []))
    report_content = result.get('report_content', '')

    score = 0
    feedback = []

    # 1. Active Integrity (35 points) - CRITICAL CHECK
    active_missing = gt_active - src_files
    active_integrity_passed = False
    
    if len(active_missing) == 0:
        score += 35
        feedback.append("Active integrity maintained (0 active DB files were touched) ✓")
        active_integrity_passed = True
    else:
        feedback.append(f"CRITICAL FAILURE: {len(active_missing)} active DB files were moved or deleted! ✗")

    # 2. Orphans Archived (40 points)
    orphans_correctly_archived = gt_orphan.intersection(archive_files)
    if gt_orphan:
        orphan_archive_ratio = len(orphans_correctly_archived) / len(gt_orphan)
        archive_score = int(40 * orphan_archive_ratio)
        score += archive_score
        
        if archive_score == 40:
            feedback.append(f"Successfully archived all {len(gt_orphan)} orphans ✓")
        else:
            feedback.append(f"Archived {len(orphans_correctly_archived)}/{len(gt_orphan)} orphans ✗")
    else:
        # Edge case protection
        score += 40

    # 3. Source Cleaned (15 points)
    orphans_left_in_src = gt_orphan.intersection(src_files)
    if len(orphans_left_in_src) == 0:
        score += 15
        feedback.append("Source directory successfully cleaned of all orphans ✓")
    else:
        feedback.append(f"{len(orphans_left_in_src)} orphans were incorrectly left in the source directory ✗")

    # 4. Report Accuracy (10 points)
    try:
        # Extract the first consecutive sequence of digits from the report
        matches = re.findall(r'\d+', report_content)
        if matches and int(matches[0]) == len(gt_orphan):
            score += 10
            feedback.append(f"Report correctly identified {len(gt_orphan)} orphaned files ✓")
        elif not matches:
            feedback.append("Report file is missing or contains no numbers ✗")
        else:
            feedback.append(f"Report contains incorrect count: {matches[0]} (expected {len(gt_orphan)}) ✗")
    except Exception:
        feedback.append("Could not parse valid integer from report file ✗")

    # FAILSAFE RULE: 
    # If the agent damaged live data, they fail the entire task regardless of orphans found.
    if not active_integrity_passed:
        score = 0
        feedback.append("--> Score ZEROED due to corruption of active database-linked files.")

    passed = score >= 75 and active_integrity_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }