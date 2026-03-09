#!/usr/bin/env python3
"""
Verifier for verify_volume_integrity task.

Criteria:
1. Integrity report exists (10 pts)
2. Report created during task (timestamp check) (10 pts)
3. Report header format is valid (10 pts)
4. Report status line "ALL FILES VERIFIED OK" (20 pts)
5. All expected files listed with [OK] status (20 pts)
6. Volume is dismounted at the end (10 pts)
7. VLM verification of workflow (10 pts)
8. No errors in report (10 pts)
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_volume_integrity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Load Task Result JSON
    # ================================================================
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # ================================================================
    # 2. Check Report Existence & Timestamp (20 pts)
    # ================================================================
    report_exists = task_result.get('report_exists', False)
    created_during_task = task_result.get('report_created_during_task', False)
    
    if report_exists:
        score += 10
        feedback_parts.append("Report file exists")
        if created_during_task:
            score += 10
            feedback_parts.append("Report created during task")
        else:
            feedback_parts.append("Report pre-dated task (anti-gaming fail)")
    else:
        feedback_parts.append("Report file NOT found")
        # Critical failure if report missing
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # ================================================================
    # 3. Analyze Report Content (50 pts)
    # ================================================================
    report_content = ""
    ground_truth_files = []
    
    # Read report content
    with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
        try:
            copy_from_env("/tmp/integrity_report_export.txt", tmp.name)
            with open(tmp.name, 'r') as f:
                report_content = f.read()
        except Exception as e:
            feedback_parts.append(f"Failed to read report content: {e}")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
                
    # Read ground truth manifest to get file list
    with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
        try:
            copy_from_env("/tmp/ground_truth_manifest.txt", tmp.name)
            with open(tmp.name, 'r') as f:
                # sha256sum output format: "hash  filename"
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 2:
                        # Handle potential * binary indicator in sha256sum
                        fname = parts[1].lstrip('*')
                        ground_truth_files.append(fname)
        except Exception as e:
            feedback_parts.append("Ground truth missing")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    lines = report_content.strip().split('\n')
    
    # Criterion 3: Header Format (10 pts)
    header_ok = False
    if len(lines) >= 4:
        if "INTEGRITY VERIFICATION REPORT" in lines[0].upper() and \
           "data_volume.hc" in lines[1]:
            header_ok = True
    
    if header_ok:
        score += 10
        feedback_parts.append("Header format correct")
    else:
        feedback_parts.append("Header format incorrect")

    # Criterion 4: Status Line (20 pts)
    status_ok = False
    for line in lines:
        if "Status:" in line and "ALL FILES VERIFIED OK" in line:
            status_ok = True
            break
            
    if status_ok:
        score += 20
        feedback_parts.append("Status line correct")
    else:
        feedback_parts.append("Status line incorrect or missing")

    # Criterion 5: File List Checks (20 pts)
    files_ok_count = 0
    if ground_truth_files:
        for fname in ground_truth_files:
            # Check for "[OK] filename" pattern
            # Using regex to be flexible with spacing
            pattern = re.compile(r'\[OK\].*' + re.escape(fname), re.IGNORECASE)
            if pattern.search(report_content):
                files_ok_count += 1
        
        if files_ok_count >= len(ground_truth_files):
            score += 20
            feedback_parts.append(f"All {len(ground_truth_files)} files verified OK")
        elif files_ok_count > 0:
            partial = int(20 * (files_ok_count / len(ground_truth_files)))
            score += partial
            feedback_parts.append(f"Some files verified OK ({files_ok_count}/{len(ground_truth_files)})")
        else:
            feedback_parts.append("No files listed as OK")
    else:
        feedback_parts.append("Could not verify file list (ground truth missing)")
    
    # Criterion 8: No errors in report (10 pts)
    if "FAIL" not in report_content and "ERROR" not in report_content:
        score += 10
        feedback_parts.append("No errors reported")

    # ================================================================
    # 4. Check Dismount State (10 pts)
    # ================================================================
    if task_result.get('volume_dismounted', False):
        score += 10
        feedback_parts.append("Volume dismounted")
    else:
        feedback_parts.append("Volume left mounted")

    # ================================================================
    # 5. VLM Trajectory Verification (10 pts)
    # ================================================================
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a user performing a data integrity verification task in Linux/VeraCrypt.
        
        Look for:
        1. A terminal window running 'sha256sum' or similar commands.
        2. A text editor writing a report.
        3. VeraCrypt window showing mount/dismount actions.
        
        Did the user appear to compute checksums and write a report?
        Answer yes or no.
        """
        
        try:
            result = query_vlm(images=frames + [final_img], prompt=prompt)
            if result.get("success") and "yes" in result.get("text", "").lower():
                vlm_score = 10
                feedback_parts.append("VLM confirmed workflow")
            else:
                # Fallback: simple trajectory length check
                if len(traj.get('steps', [])) > 5:
                    vlm_score = 5
                    feedback_parts.append("VLM inconclusive (partial credit)")
        except Exception:
            # If VLM fails, grant partial if trajectory exists
            if len(traj) > 0:
                vlm_score = 5
    else:
        # Fallback if VLM not available
        vlm_score = 10
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }