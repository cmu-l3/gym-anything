#!/usr/bin/env python3
"""
Verifier for mount_corrupted_header task.

Verifies:
1. Volume is mounted at /home/ga/MountPoints/slot1 (25 pts)
2. Files inside are accessible and match ground truth checksums (25 pts)
3. Recovery report exists and contains correct data (25 pts)
4. Anti-gaming: Primary header is STILL corrupted (Agent used backup header, didn't repair) (25 pts)
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mount_corrupted_header(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # 1. Check Mount Status (25 pts)
    if result.get("is_mounted", False):
        score += 25
        feedback_parts.append("Volume mounted successfully")
    else:
        feedback_parts.append("Volume NOT mounted at expected path")

    # 2. Check Files & Integrity (25 pts)
    # Parse actual checksums from string "hash filename\nhash filename"
    actual_map = {}
    if result.get("actual_checksums"):
        for line in result["actual_checksums"].strip().split('\n'):
            parts = line.split()
            if len(parts) >= 2:
                actual_map[parts[1]] = parts[0]

    gt_map = {}
    if result.get("ground_truth_checksums"):
        for line in result["ground_truth_checksums"].strip().split('\n'):
            parts = line.split()
            if len(parts) >= 2:
                gt_map[parts[1]] = parts[0]

    if result.get("files_accessible", False):
        # Verify checksums match
        match_count = 0
        expected_files = ["project_ssh_config", "infrastructure_hosts", "quarterly_metrics.csv"]
        
        for fname in expected_files:
            if fname in actual_map and fname in gt_map:
                if actual_map[fname] == gt_map[fname]:
                    match_count += 1
        
        if match_count == 3:
            score += 25
            feedback_parts.append("All files verified intact")
        else:
            score += 10
            feedback_parts.append(f"Files accessible but checksum mismatch ({match_count}/3)")
    else:
        feedback_parts.append("Files NOT accessible in volume")

    # 3. Check Recovery Report (25 pts)
    if result.get("report_exists", False):
        try:
            content = base64.b64decode(result.get("report_content_b64", "")).decode('utf-8')
            lines = content.strip().split('\n')
            
            # Check Header
            report_score = 0
            if "RECOVERY REPORT" in lines[0]:
                report_score += 5
            
            # Check content - ensure hashes are present
            hashes_found = 0
            for fname, fhash in gt_map.items():
                if fhash in content and fname in content:
                    hashes_found += 1
            
            if hashes_found == 3:
                report_score += 15
            else:
                report_score += (hashes_found * 5)

            # Check Footer
            if "RECOVERY COMPLETE" in lines[-1]:
                report_score += 5
            
            score += report_score
            feedback_parts.append(f"Report verified ({report_score}/25 pts)")
            
            # Timestamp check
            task_start = result.get("task_start", 0)
            report_mtime = result.get("report_mtime", 0)
            if report_mtime < task_start:
                 feedback_parts.append("WARNING: Report file predates task start")
                 score = max(0, score - 10)

        except Exception as e:
            feedback_parts.append("Report corrupted or unreadable")
    else:
        feedback_parts.append("Recovery report NOT found")

    # 4. Anti-gaming: Backup Header Usage (25 pts)
    # The task requires mounting with the backup header, not fixing the primary header.
    # If the primary header is still 512 bytes of zeros, they did it right (mounted using backup).
    # If they restored the header (e.g., via Restore Volume Header), the zeros will be overwritten.
    if result.get("is_header_still_corrupted", False):
        score += 25
        feedback_parts.append("Correctly used backup header (primary header still damaged)")
    else:
        feedback_parts.append("Primary header was repaired/modified (Method deviation)")
        # We penalize this because the specific goal was to mount using backup header options,
        # not to perform a repair operation (which might be risky in some forensics contexts).

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }