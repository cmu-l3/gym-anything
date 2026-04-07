#!/usr/bin/env python3
"""
Verifier for forensic_peer_review_audit task.

Scoring (100 pts total, pass threshold = 60):
  10 pts - Case created and Autopsy DB found
  10 pts - Disk image added as data source
  10 pts - Ingest completed
  10 pts - FILESYSTEM_TYPE correct
  10 pts - TOTAL_FILES correct (+/- 5)
  10 pts - DELETED_FILES correct (+/- 5)
  05 pts - VOLUME_LABEL correct
  05 pts - LARGEST_FILE_NAME/SIZE correct
  10 pts - At least 3 specific errors found in the report section
  10 pts - Error summary file exists and contains pipe-delimited records
  10 pts - Main report has all structural sections
"""

import json
import os
import re
import tempfile


def extract_field(content, field_name):
    """Extract a field from the report content safely."""
    # Match FIELD_NAME: value
    match = re.search(fr"^{field_name}:\s*(.+)$", content, re.IGNORECASE | re.MULTILINE)
    if match:
        return match.group(1).strip()
    return None

def verify_forensic_peer_review_audit(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/peer_review_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/peer_review_gt.json")

    # ── Pull result JSON ──────────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export did not run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull ground truth ──────────────────────────────────────────────────────
    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass # Handle gracefully below

    gt_fs_type = gt.get("filesystem_type", "NTFS").upper()
    gt_vol_label = gt.get("volume_label", "No Label").upper()
    gt_total = gt.get("total_files", 0)
    gt_deleted = gt.get("deleted_files", 0)

    db_largest_name = result.get("db_largest_file_name", "").lower()
    db_largest_size = result.get("db_largest_file_size", 0)

    # ── Criterion 1: Case DB found (10 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Data source added (10 pts) ───────────────────────────────
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not added")

    # ── Criterion 3: Ingest completed (10 pts) ────────────────────────────────
    if result.get("ingest_completed"):
        score += 10
        feedback_parts.append("PASS Ingest completed (+10)")
    else:
        feedback_parts.append("FAIL Ingest not completed")

    # ── Parse Agent's Report ──────────────────────────────────────────────────
    start_time = result.get("start_time", 0)
    report_mtime = result.get("report_mtime", 0)
    report_content = result.get("report_content", "")
    
    # Check if report is valid and recent
    report_valid = False
    if result.get("report_file_exists") and (start_time == 0 or report_mtime >= start_time):
        report_valid = True
    else:
        feedback_parts.append("FAIL Report file missing or stale")

    if report_valid:
        # ── Criterion 4: Filesystem Type (10 pts) ─────────────────────────────
        fs_val = extract_field(report_content, "FILESYSTEM_TYPE")
        if fs_val and gt_fs_type in fs_val.upper():
            score += 10
            feedback_parts.append(f"PASS FS Type '{fs_val}' correct (+10)")
        else:
            feedback_parts.append(f"FAIL FS Type incorrect: {fs_val} (Expected {gt_fs_type})")

        # ── Criterion 5: Total Files (10 pts) ──────────────────────────────────
        tf_val_str = extract_field(report_content, "TOTAL_FILES")
        try:
            tf_val = int(re.sub(r'[^\d]', '', tf_val_str)) if tf_val_str else -1
            if abs(tf_val - gt_total) <= 5:  # Tolerance for hidden/system files
                score += 10
                feedback_parts.append(f"PASS Total Files {tf_val} correct (+10)")
            else:
                feedback_parts.append(f"FAIL Total Files incorrect: {tf_val} (Expected ~{gt_total})")
        except ValueError:
            feedback_parts.append("FAIL Total Files not parseable")

        # ── Criterion 6: Deleted Files (10 pts) ────────────────────────────────
        df_val_str = extract_field(report_content, "DELETED_FILES")
        try:
            df_val = int(re.sub(r'[^\d]', '', df_val_str)) if df_val_str else -1
            if abs(df_val - gt_deleted) <= 5:
                score += 10
                feedback_parts.append(f"PASS Deleted Files {df_val} correct (+10)")
            else:
                feedback_parts.append(f"FAIL Deleted Files incorrect: {df_val} (Expected ~{gt_deleted})")
        except ValueError:
            feedback_parts.append("FAIL Deleted Files not parseable")

        # ── Criterion 7: Volume Label (5 pts) ──────────────────────────────────
        vl_val = extract_field(report_content, "VOLUME_LABEL")
        if vl_val and (gt_vol_label in vl_val.upper() or vl_val.upper() in gt_vol_label):
            score += 5
            feedback_parts.append("PASS Volume Label correct (+5)")
        else:
            feedback_parts.append(f"FAIL Volume Label incorrect: {vl_val} (Expected {gt_vol_label})")

        # ── Criterion 8: Largest File (5 pts) ──────────────────────────────────
        lf_name = extract_field(report_content, "LARGEST_FILE_NAME")
        lf_size_str = extract_field(report_content, "LARGEST_FILE_SIZE")
        
        if lf_name and db_largest_name and lf_name.lower() in db_largest_name:
            score += 5
            feedback_parts.append("PASS Largest file name correct (+5)")
        elif lf_size_str:
            # Fallback check size
            try:
                lf_size = int(re.sub(r'[^\d]', '', lf_size_str))
                if abs(lf_size - db_largest_size) < 1000:
                    score += 5
                    feedback_parts.append("PASS Largest file size correct (+5)")
            except:
                feedback_parts.append("FAIL Largest file incorrect")
        else:
            feedback_parts.append("FAIL Largest file missing/incorrect")

        # ── Criterion 9: Errors Identified (10 pts) ────────────────────────────
        error_lines = [l for l in report_content.splitlines() if l.strip().upper().startswith("ERROR")]
        if len(error_lines) >= 3:
            score += 10
            feedback_parts.append(f"PASS {len(error_lines)} errors detailed in report (+10)")
        elif len(error_lines) > 0:
            score += 5
            feedback_parts.append(f"PARTIAL Only {len(error_lines)} errors detailed (+5)")
        else:
            feedback_parts.append("FAIL No ERROR lines found in report")

        # ── Criterion 11: All Sections Present (10 pts) ────────────────────────
        has_header = "PEER REVIEW REPORT" in report_content.upper()
        has_errors_section = "ERRORS FOUND" in report_content.upper()
        has_conclusion = "REVIEW_CONCLUSION" in report_content.upper()
        if has_header and has_errors_section and has_conclusion:
            score += 10
            feedback_parts.append("PASS All structural sections present (+10)")
        else:
            feedback_parts.append("FAIL Report missing required structural headers")

    # ── Criterion 10: Error Summary File (10 pts) ──────────────────────────────
    summary_content = result.get("error_summary_content", "")
    if result.get("error_summary_exists") and summary_content.strip():
        pipe_lines = [l for l in summary_content.splitlines() if "|" in l]
        if len(pipe_lines) >= 3:
            score += 10
            feedback_parts.append("PASS Error summary file properly formatted (+10)")
        elif len(pipe_lines) > 0:
            score += 5
            feedback_parts.append("PARTIAL Error summary file missing some lines (+5)")
        else:
            feedback_parts.append("FAIL Error summary lacks pipe-delimited formatting")
    else:
        feedback_parts.append("FAIL Error summary file missing or empty")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }