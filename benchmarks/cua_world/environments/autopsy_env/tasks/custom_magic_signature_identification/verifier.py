#!/usr/bin/env python3
"""
Verifier for custom_magic_signature_identification task.

Scoring (100 pts total, pass threshold = 75):
  10 pts  — Autopsy case created and DB found
  10 pts  — Disk image data source added
  35 pts  — DB explicitly contains files assigned 'application/x-xyz-config' (Proves GUI config)
  10 pts  — CSV report exists, is recent, and has the correct pipe-delimited header
  25 pts  — Accurate detection: All 3 injected C2 files are present in the CSV report
  10 pts  — Zero False Positives: Only files containing the signature are included
"""

import json
import os
import tempfile


def verify_custom_magic_signature(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/c2_hunting_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/c2_hunting_gt.json")

    # ── Pull result JSON from VM ──────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script did not run or task was not attempted."
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file: {e}"
        }

    # ── Pull Ground Truth from VM ─────────────────────────────────────────────
    gt = {"c2_files": [], "noise_files": [], "expected_mime_type": "application/x-xyz-config"}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass  # GT unavailable - use hardcoded defaults based on setup script

    expected_c2_files = set(f.lower() for f in gt.get("c2_files", ["sys_config.txt", "vacation_photo.jpg", "system_backup.dat"]))
    expected_mime = gt.get("expected_mime_type", "application/x-xyz-config")

    # ── Criterion 1: Case DB found (10 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found for C2_Hunting_2024 (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Data source added (10 pts) ───────────────────────────────
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added to case (+10)")
    else:
        feedback_parts.append("FAIL Data source not found in case DB")

    # ── Criterion 3: Custom MIME Type Configuration (35 pts) ──────────────────
    # This is the anti-gaming check. If they didn't configure Autopsy GUI, this is empty.
    db_custom_files = set(f.lower() for f in result.get("db_custom_mime_files", []))
    if db_custom_files:
        matches = db_custom_files.intersection(expected_c2_files)
        if len(matches) == len(expected_c2_files):
            score += 35
            feedback_parts.append(f"PASS Autopsy DB verified: {expected_mime} configured and detected {len(matches)} files (+35)")
        elif len(matches) > 0:
            score += 20
            feedback_parts.append(f"PARTIAL Autopsy DB verified: custom MIME type configured, but only detected {len(matches)} files (+20)")
        else:
            feedback_parts.append("FAIL Autopsy DB recorded custom MIME type but applied it to wrong files")
    else:
        if result.get("ingest_completed"):
            feedback_parts.append(f"FAIL Ingest completed, but no files in DB have MIME type '{expected_mime}'. Custom File Type was not configured correctly.")
        else:
            feedback_parts.append("FAIL Ingest not completed, Custom File Type verification failed.")

    # ── Criterion 4 & 5 & 6: CSV Report Verification (45 pts total) ───────────
    start_time = result.get("start_time", 0)
    report_mtime = result.get("report_mtime", 0)
    report_content = result.get("report_content", "").strip()

    if result.get("report_file_exists"):
        if start_time > 0 and report_mtime < start_time:
            feedback_parts.append("FAIL CSV report exists but pre-dates task start (stale)")
        elif not report_content:
            feedback_parts.append("FAIL CSV report is empty")
        else:
            lines = [l.strip() for l in report_content.splitlines() if l.strip()]
            header = lines[0].upper()
            
            # Sub-Criterion 4: CSV formatting (10 pts)
            if "FILENAME" in header and "EXTENSION" in header and "|" in header and "MIME_TYPE" in header:
                score += 10
                feedback_parts.append("PASS CSV report has valid pipe-delimited header (+10)")
            else:
                feedback_parts.append("FAIL CSV report lacks proper pipe-delimited header format")

            # Parse reported files
            reported_files = set()
            for line in lines[1:]:
                parts = line.split("|")
                if len(parts) >= 1:
                    reported_files.add(parts[0].strip().lower())

            # Sub-Criterion 5: Accurate Detection (25 pts)
            found_c2 = reported_files.intersection(expected_c2_files)
            if len(found_c2) == len(expected_c2_files):
                score += 25
                feedback_parts.append(f"PASS CSV report accurately lists all {len(expected_c2_files)} C2 files (+25)")
            elif len(found_c2) > 0:
                score += int(25 * (len(found_c2) / len(expected_c2_files)))
                feedback_parts.append(f"PARTIAL CSV report lists {len(found_c2)}/{len(expected_c2_files)} C2 files (+{int(25 * (len(found_c2) / len(expected_c2_files)))})")
            else:
                feedback_parts.append("FAIL CSV report does not list any expected C2 files")

            # Sub-Criterion 6: Zero False Positives (10 pts)
            false_positives = reported_files - expected_c2_files
            if len(false_positives) == 0 and len(reported_files) > 0:
                score += 10
                feedback_parts.append("PASS Zero false positives in CSV report (+10)")
            elif len(false_positives) > 0:
                feedback_parts.append(f"FAIL CSV report contains {len(false_positives)} false positives")
    else:
        feedback_parts.append("FAIL Report file not written to /home/ga/Reports/c2_discovered_configs.csv")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }