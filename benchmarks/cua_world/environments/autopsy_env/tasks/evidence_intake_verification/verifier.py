#!/usr/bin/env python3
"""
Verifier for evidence_intake_verification task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  - Case DB found
  10 pts  - Disk image data source added
  10 pts  - Ingest completed
  5 pts   - Intake report exists & recent
  15 pts  - IMAGE_MD5 is correct (MANDATORY TO PASS)
  5 pts   - IMAGE_SIZE_BYTES is correct
  5 pts   - FILE_SYSTEM_TYPE correct
  10 pts  - TOTAL_FILES within tolerance
  10 pts  - DELETED_FILES within tolerance
  5 pts   - ALLOCATED_FILES within tolerance
  5 pts   - TOTAL_DIRECTORIES within tolerance
  5 pts   - File inventory CSV exists, formatted correctly
  5 pts   - Inventory covers >=50% GT filenames
"""

import json
import os
import re
import tempfile

def verify_evidence_intake_verification(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/evidence_intake_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/evidence_intake_gt.json")
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # Load Result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file missing: {e}"}

    # Load GT JSON
    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(gt_file_vm, tmp_path)
        with open(tmp_path) as f:
            gt = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        pass # Handle gracefully if GT failed to compute completely
        
    # --- Check Autopsy Progress ---
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")
        
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not added")
        
    if result.get("ingest_completed"):
        score += 10
        feedback_parts.append("PASS Ingest completed (+10)")
    else:
        feedback_parts.append("FAIL Ingest not completed")
        
    # --- Parse Intake Report ---
    start_time = result.get("start_time", 0)
    rep_exists = result.get("report_exists", False)
    rep_mtime = result.get("report_mtime", 0)
    rep_content = result.get("report_content", "")
    
    if rep_exists:
        if start_time == 0 or rep_mtime >= start_time:
            score += 5
            feedback_parts.append("PASS Intake report exists & recent (+5)")
        else:
            feedback_parts.append("PARTIAL Intake report exists but is old (+0)")
    else:
        feedback_parts.append("FAIL Intake report not found")
        
    parsed_report = {}
    for line in rep_content.splitlines():
        if ':' in line:
            parts = line.split(':', 1)
            parsed_report[parts[0].strip().upper()] = parts[1].strip()
            
    # --- Validate Intake Information ---
    md5_pass = False
    reported_md5 = parsed_report.get("IMAGE_MD5", "").lower()
    gt_md5 = gt.get("image_md5", "").lower()
    if gt_md5 and reported_md5 == gt_md5:
        score += 15
        md5_pass = True
        feedback_parts.append("PASS IMAGE_MD5 correct (+15)")
    else:
        feedback_parts.append(f"FAIL IMAGE_MD5 incorrect (Expected {gt_md5[:8]}...)")
        
    reported_size = parsed_report.get("IMAGE_SIZE_BYTES", "").replace(",", "")
    gt_size = str(gt.get("image_size", ""))
    if gt_size and reported_size == gt_size:
        score += 5
        feedback_parts.append("PASS IMAGE_SIZE_BYTES correct (+5)")
    else:
        feedback_parts.append(f"FAIL IMAGE_SIZE_BYTES incorrect")
        
    reported_fs = parsed_report.get("FILE_SYSTEM_TYPE", "").upper()
    if "NTFS" in reported_fs:
        score += 5
        feedback_parts.append("PASS FILE_SYSTEM_TYPE contains NTFS (+5)")
    else:
        feedback_parts.append("FAIL FILE_SYSTEM_TYPE incorrect")
        
    # --- Validate File Counts (Tolerance applied to account for TSK vs Autopsy DB differences) ---
    def check_count(field, gt_val, tol, pts):
        nonlocal score
        val_str = parsed_report.get(field, "")
        try:
            val = int(re.sub(r'[^\d]', '', val_str))
            if abs(val - gt_val) <= tol:
                score += pts
                feedback_parts.append(f"PASS {field} within tolerance (+{pts})")
            else:
                feedback_parts.append(f"FAIL {field} out of bounds ({val} vs GT {gt_val})")
        except:
            feedback_parts.append(f"FAIL {field} not found or invalid format")
            
    check_count("TOTAL_FILES", gt.get("total_files", 0), 5, 10)
    check_count("DELETED_FILES", gt.get("deleted_files", 0), 5, 10)
    check_count("ALLOCATED_FILES", gt.get("allocated_files", 0), 5, 5)
    check_count("TOTAL_DIRECTORIES", gt.get("total_directories", 0), 5, 5)
    
    # --- Validate File Inventory CSV ---
    inv_exists = result.get("inventory_exists", False)
    inv_content = result.get("inventory_content", "")
    gt_names = set(n.lower() for n in gt.get("file_names", []))
    
    if inv_exists:
        lines = [l for l in inv_content.splitlines() if l.strip()]
        has_header = any("FILENAME" in l.upper() for l in lines[:3])
        has_pipes = any("|" in l for l in lines)
        data_lines = len(lines) - 1 if has_header else len(lines)
        
        if has_header and has_pipes and data_lines >= 5:
            score += 5
            feedback_parts.append("PASS Inventory CSV formatted correctly (+5)")
        else:
            feedback_parts.append("FAIL Inventory CSV format invalid")
            
        inv_lower = inv_content.lower()
        if gt_names:
            matched = sum(1 for n in gt_names if n in inv_lower)
            if matched / len(gt_names) >= 0.5:
                score += 5
                feedback_parts.append("PASS Inventory covers >=50% GT filenames (+5)")
            else:
                feedback_parts.append("FAIL Inventory covers <50% GT filenames")
        else:
            feedback_parts.append("FAIL No GT names for inventory coverage check")
    else:
        feedback_parts.append("FAIL Inventory CSV not found")
        
    # --- Finalize Score ---
    if not md5_pass and score > 55:
        score = 55
        feedback_parts.append("CAP Score capped at 55 due to incorrect MD5 (MANDATORY for integrity)")
        
    passed = score >= 60 and md5_pass
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }