#!/usr/bin/env python3
"""
Verifier for ntfs_special_artifact_analysis task.

Scoring (100 pts total, pass threshold = 60):
  10 pts - Case DB found with correct case name
  10 pts - Disk image added as data source
  10 pts - Ingest completed successfully
  10 pts - Metafile inventory file exists and is recent
  5 pts  - Inventory has correct pipe-delimited format with header
  15 pts - Inventory covers >= 70% of GT system metafiles
  10 pts - MFT size reported within 10% of GT
  5 pts  - LogFile size reported within 10% of GT
  10 pts - Analysis report exists with all required sections
  10 pts - Orphan file count within +/- 2 of GT
  5 pts  - Anti-forensics assessment section present
"""

import json
import os
import re
import tempfile

def parse_size(size_str):
    """Safely extract integer from a size string like '123,456 bytes'."""
    s = re.sub(r'[^\d]', '', size_str)
    return int(s) if s else -1

def verify_ntfs_special_artifact_analysis(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/ntfs_artifact_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/ntfs_artifact_gt.json")

    # ── Pull result JSON ──────────────────────────────────────────────────────
    result = {}
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # ── Pull ground truth ─────────────────────────────────────────────────────
    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        gt = {"metafile_names": [], "orphan_count": 0, "mft_size_bytes": 0, "logfile_size_bytes": 0}

    gt_metafile_names = set(n.lower() for n in gt.get("metafile_names", []))
    gt_orphan_count = gt.get("orphan_count", 0)
    gt_mft_size = gt.get("mft_size_bytes", 0)
    gt_logfile_size = gt.get("logfile_size_bytes", 0)

    # ── Criteria 1-3: Autopsy DB State (30 pts) ───────────────────────────────
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

    # ── Criterion 4-6: Inventory File (30 pts) ────────────────────────────────
    start_time = result.get("start_time", 0)
    inv_mtime = result.get("inventory_mtime", 0)
    inv_content = result.get("inventory_content", "").replace("\\n", "\n")
    
    if result.get("inventory_file_exists") and (start_time == 0 or inv_mtime >= start_time):
        score += 10
        feedback_parts.append("PASS Inventory file exists and is recent (+10)")
        
        lines = [l.strip() for l in inv_content.splitlines() if l.strip()]
        if lines and "FILENAME" in lines[0].upper() and "ALLOCATION" in lines[0].upper() and "|" in lines[0]:
            score += 5
            feedback_parts.append("PASS Inventory has proper pipe-delimited header (+5)")
        else:
            feedback_parts.append("FAIL Inventory lacks expected header format")
            
        if gt_metafile_names:
            inv_lower = inv_content.lower()
            found_metafiles = sum(1 for name in gt_metafile_names if name in inv_lower)
            coverage = found_metafiles / len(gt_metafile_names)
            
            if coverage >= 0.7:
                score += 15
                feedback_parts.append(f"PASS Inventory covers {coverage*100:.1f}% of GT metafiles (+15)")
            elif coverage >= 0.3:
                score += 7
                feedback_parts.append(f"PARTIAL Inventory covers {coverage*100:.1f}% of GT metafiles (+7)")
            else:
                feedback_parts.append(f"FAIL Inventory coverage too low ({coverage*100:.1f}%)")
        else:
            # If GT is empty/failed, grant points if they attempted it
            if len(lines) > 1:
                score += 15
                feedback_parts.append("PASS Inventory populated (GT missing) (+15)")
    else:
        feedback_parts.append("FAIL Inventory file missing or stale")

    # ── Criterion 7-11: Report File (40 pts) ──────────────────────────────────
    rep_mtime = result.get("report_mtime", 0)
    rep_content = result.get("report_content", "").replace("\\n", "\n")
    
    if result.get("report_file_exists") and (start_time == 0 or rep_mtime >= start_time):
        req_sections = ["VOLUME_FILE_SYSTEM", "TOTAL_METAFILES", "TOTAL_ORPHAN_FILES", 
                        "MFT_SIZE_BYTES", "LOGFILE_SIZE_BYTES", "METAFILE_LIST", "ORPHAN_FILE_LIST"]
        
        rep_upper = rep_content.upper()
        missing_sections = [s for s in req_sections if s not in rep_upper]
        
        if not missing_sections:
            score += 10
            feedback_parts.append("PASS Report has all required sections (+10)")
        else:
            feedback_parts.append(f"FAIL Report missing sections: {missing_sections}")

        # Check MFT Size (10 pts)
        mft_match = re.search(r'MFT_SIZE_BYTES:\s*([0-9,]+)', rep_upper)
        if mft_match and gt_mft_size > 0:
            reported_mft = parse_size(mft_match.group(1))
            if abs(reported_mft - gt_mft_size) <= gt_mft_size * 0.1:
                score += 10
                feedback_parts.append(f"PASS MFT size accurate: {reported_mft} (+10)")
            else:
                feedback_parts.append(f"FAIL MFT size inaccurate: got {reported_mft}, expected {gt_mft_size}")
        elif mft_match:
            score += 10  # Auto-pass if GT missing
            
        # Check LogFile Size (5 pts)
        log_match = re.search(r'LOGFILE_SIZE_BYTES:\s*([0-9,]+)', rep_upper)
        if log_match and gt_logfile_size > 0:
            reported_log = parse_size(log_match.group(1))
            if abs(reported_log - gt_logfile_size) <= gt_logfile_size * 0.1:
                score += 5
                feedback_parts.append(f"PASS LogFile size accurate: {reported_log} (+5)")
            else:
                feedback_parts.append(f"FAIL LogFile size inaccurate: got {reported_log}, expected {gt_logfile_size}")
        elif log_match:
            score += 5

        # Check Orphan Count (10 pts)
        orphan_match = re.search(r'TOTAL_ORPHAN_FILES:\s*(\d+)', rep_upper)
        if orphan_match:
            reported_orphans = int(orphan_match.group(1))
            if abs(reported_orphans - gt_orphan_count) <= 2:
                score += 10
                feedback_parts.append(f"PASS Orphan count accurate: {reported_orphans} (+10)")
            else:
                feedback_parts.append(f"FAIL Orphan count inaccurate: got {reported_orphans}, expected {gt_orphan_count}")
                
        # Check Anti-forensics section (5 pts)
        if "ANTI_FORENSICS_INDICATORS:" in rep_upper:
            # Check if there is some text after the heading
            af_idx = rep_upper.find("ANTI_FORENSICS_INDICATORS:")
            after_text = rep_content[af_idx + len("ANTI_FORENSICS_INDICATORS:"):].strip()
            if len(after_text) > 5:
                score += 5
                feedback_parts.append("PASS Anti-forensics assessment included (+5)")
            else:
                feedback_parts.append("FAIL Anti-forensics section is empty")
    else:
        feedback_parts.append("FAIL Analysis report missing or stale")

    # Pass condition: must have >= 60 points and basic case/inventory files exist
    key_files_exist = result.get("case_db_found") and result.get("inventory_file_exists")
    passed = (score >= 60) and key_files_exist

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }