#!/usr/bin/env python3
"""
Verifier for MFT record extraction task.

Scoring (100 pts, threshold 70):
- 20 pts: Target INODE in report matches the actual largest deleted file
- 10 pts: target_mft_record.bin is exactly 1024 bytes
- 30 pts: SHA-256 of target_mft_record.bin matches ground truth
- 20 pts: SHA-256 of target_file_content.bin matches ground truth
- 20 pts: Documentation accuracy (MFT signature, MTIMEs match GT)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mft_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch GT and Results
    gt = {}
    result = {}
    
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp_gt:
        try:
            copy_from_env("/tmp/mft_gt.json", tmp_gt.name)
            with open(tmp_gt.name, 'r') as f:
                gt = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load GT: {e}"}
        finally:
            os.unlink(tmp_gt.name)
            
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp_res:
        try:
            copy_from_env("/tmp/mft_result.json", tmp_res.name)
            with open(tmp_res.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
        finally:
            os.unlink(tmp_res.name)

    # Anti-gaming: Ensure files were generated during the task
    start_time = result.get('task_start', 0)
    
    # Check Report
    report = result.get('parsed_report', {})
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    
    if not report_exists:
        feedback_parts.append("FAIL: Report file daubert_validation.txt not found.")
    elif report_mtime < start_time:
        feedback_parts.append("FAIL: Report file is stale (created before task start).")
    else:
        # Criterion 1: Target Inode (20 pts)
        agent_inode = str(report.get('TARGET_INODE', '')).strip()
        gt_inode = str(gt.get('target_inode', '')).strip()
        
        if agent_inode == gt_inode and gt_inode != "":
            score += 20
            feedback_parts.append(f"PASS: Identified correct target inode ({gt_inode}). [20/20]")
        else:
            feedback_parts.append(f"FAIL: Target inode mismatch. Expected {gt_inode}, got '{agent_inode}'. [0/20]")

        # Criterion 5: Documentation Accuracy (20 pts)
        agent_sig = str(report.get('MFT_RECORD_HEX_SIGNATURE', '')).strip().upper()
        agent_si_mtime = str(report.get('STANDARD_INFORMATION_MTIME', '')).strip()
        agent_fn_mtime = str(report.get('FILE_NAME_MTIME', '')).strip()
        
        gt_sig = str(gt.get('mft_sig', '')).strip().upper()
        gt_si_mtime = str(gt.get('si_mtime', '')).strip()
        gt_fn_mtime = str(gt.get('fn_mtime', '')).strip()
        
        doc_score = 0
        if agent_sig and (agent_sig == gt_sig or agent_sig == "FILE"):
            doc_score += 6
        if agent_si_mtime == gt_si_mtime and gt_si_mtime != "":
            doc_score += 7
        if agent_fn_mtime == gt_fn_mtime and gt_fn_mtime != "":
            doc_score += 7
            
        score += doc_score
        feedback_parts.append(f"Documentation check: {doc_score}/20 pts awarded.")

    # Check MFT Record
    mft_exists = result.get('mft_record_exists', False)
    mft_mtime = result.get('mft_record_mtime', 0)
    
    if not mft_exists:
        feedback_parts.append("FAIL: MFT record target_mft_record.bin not found.")
    elif mft_mtime < start_time:
        feedback_parts.append("FAIL: MFT record is stale (created before task start).")
    else:
        # Criterion 2: Record size is exactly 1024 (10 pts)
        mft_size = result.get('mft_record_size', 0)
        if mft_size == 1024:
            score += 10
            feedback_parts.append("PASS: MFT record size is exactly 1024 bytes. [10/10]")
        else:
            feedback_parts.append(f"FAIL: MFT record size is {mft_size} bytes (expected 1024). [0/10]")
            
        # Criterion 3: Record hash matches GT (30 pts)
        agent_mft_hash = result.get('mft_record_hash', '')
        gt_mft_hash = gt.get('mft_hash', '')
        
        if agent_mft_hash == gt_mft_hash and gt_mft_hash != "":
            score += 30
            feedback_parts.append("PASS: MFT record SHA-256 hash matches ground truth. [30/30]")
        else:
            feedback_parts.append(f"FAIL: MFT record hash mismatch. [0/30]")

    # Check File Content
    content_exists = result.get('file_content_exists', False)
    content_mtime = result.get('file_content_mtime', 0)
    
    if not content_exists:
        feedback_parts.append("FAIL: File content target_file_content.bin not found.")
    elif content_mtime < start_time:
        feedback_parts.append("FAIL: File content is stale (created before task start).")
    else:
        # Criterion 4: Content hash matches GT (20 pts)
        agent_content_hash = result.get('file_content_hash', '')
        gt_content_hash = gt.get('content_hash', '')
        
        if agent_content_hash == gt_content_hash and gt_content_hash != "":
            score += 20
            feedback_parts.append("PASS: File content SHA-256 hash matches ground truth. [20/20]")
        else:
            feedback_parts.append("FAIL: File content hash mismatch. [0/20]")

    passed = (score >= 70 and agent_mft_hash == gt_mft_hash)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }