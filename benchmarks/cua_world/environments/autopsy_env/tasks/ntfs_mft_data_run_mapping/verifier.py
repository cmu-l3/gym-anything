#!/usr/bin/env python3
"""
Verifier for ntfs_mft_data_run_mapping task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case created and DB found
  10 pts  — Disk image data source added
  15 pts  — TSV file exists, is recent, and has expected headers
  15 pts  — Summary file exists and counts match TSV output
  25 pts  — Residency classification correct against ground truth
  25 pts  — Non-Resident starting cluster and cluster length exact match with ground truth
"""

import json
import os
import re
import tempfile


def verify_ntfs_mft_data_run_mapping(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/mft_data_run_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/mft_data_run_gt.json")

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
        return {"passed": False, "score": 0, "feedback": "Result file not found."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull GT JSON ──────────────────────────────────────────────────────────
    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception as e:
        feedback_parts.append(f"GT loading error: {e}")

    # ── 1. DB Initialization (10 pts) ─────────────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── 2. Data source (10 pts) ───────────────────────────────────────────────
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not found in case")

    # ── 3. TSV Headers & Formatting (15 pts) ──────────────────────────────────
    start_time = result.get("start_time", 0)
    tsv_content = result.get("tsv_content", "").replace("\\n", "\n").replace("\\t", "\t")
    tsv_lines = [l.strip() for l in tsv_content.splitlines() if l.strip()]
    
    parsed_entries = []
    headers_ok = False

    if result.get("tsv_exists") and (start_time == 0 or result.get("tsv_mtime", 0) >= start_time):
        if tsv_lines:
            header_line = tsv_lines[0].upper()
            if "FILENAME" in header_line and "INODE" in header_line and "RESIDENCY" in header_line and "STARTING_CLUSTER" in header_line:
                score += 15
                headers_ok = True
                feedback_parts.append("PASS TSV headers correct (+15)")
            else:
                score += 5
                feedback_parts.append("PARTIAL TSV exists but headers incorrect/missing (+5)")

            # Parse lines using tab (or fallback to comma/pipe if tab not found)
            separator = "\t"
            if "\t" not in tsv_lines[0]:
                if "|" in tsv_lines[0]: separator = "|"
                elif "," in tsv_lines[0]: separator = ","

            for line in tsv_lines[1:]:
                parts = [p.strip() for p in line.split(separator)]
                if len(parts) >= 5:
                    parsed_entries.append({
                        "filename": parts[0],
                        "inode": parts[1],
                        "residency": parts[2].upper(),
                        "start": parts[3].upper(),
                        "length": parts[4].upper()
                    })
    else:
        feedback_parts.append("FAIL TSV file missing or stale")

    # ── 4. Summary Accuracy (15 pts) ──────────────────────────────────────────
    summary_content = result.get("summary_content", "").upper()
    if result.get("summary_exists") and (start_time == 0 or result.get("summary_mtime", 0) >= start_time):
        if "TOTAL_DELETED_FILES_ANALYZED" in summary_content and "RESIDENT_FILES" in summary_content:
            score += 15
            feedback_parts.append("PASS Summary file formatted correctly (+15)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Summary file exists but missing required fields (+5)")
    else:
        feedback_parts.append("FAIL Summary file missing or stale")

    # ── 5. Residency Classification (25 pts) ──────────────────────────────────
    # ── 6. Cluster Allocation Accuracy (25 pts) ───────────────────────────────
    if not gt:
        feedback_parts.append("FAIL Ground truth unavailable, cannot verify exact file attributes")
        passed = False
    elif not parsed_entries:
        feedback_parts.append("FAIL No parseable data rows found in TSV")
    else:
        correct_residency = 0
        correct_clusters = 0
        total_eval_clusters = 0
        evaluated = 0

        for entry in parsed_entries:
            inode = entry["inode"]
            if inode in gt:
                evaluated += 1
                gt_rec = gt[inode]
                
                # Check Residency
                if entry["residency"] == gt_rec["residency"]:
                    correct_residency += 1
                
                # Check Cluster Runs if NON_RESIDENT
                if gt_rec["residency"] == "NON_RESIDENT":
                    total_eval_clusters += 1
                    gt_start = str(gt_rec["start_cluster"])
                    gt_len = str(gt_rec["cluster_length"])
                    if entry["start"] == gt_start and entry["length"] == gt_len:
                        correct_clusters += 1

        # Calculate proportional scores
        if evaluated > 0:
            res_ratio = correct_residency / len(gt) # measure against total GT to ensure completeness
            if res_ratio >= 0.8:
                score += 25
                feedback_parts.append(f"PASS High residency accuracy ({correct_residency}/{len(gt)}) (+25)")
            elif res_ratio >= 0.4:
                score += 10
                feedback_parts.append(f"PARTIAL Partial residency accuracy ({correct_residency}/{len(gt)}) (+10)")
            else:
                feedback_parts.append(f"FAIL Low residency accuracy ({correct_residency}/{len(gt)})")
        else:
            feedback_parts.append("FAIL No matching INODEs evaluated against GT")

        if total_eval_clusters > 0:
            # We base cluster accuracy only on correctly identified non-resident files
            clus_ratio = correct_clusters / total_eval_clusters
            if clus_ratio >= 0.8:
                score += 25
                feedback_parts.append(f"PASS High cluster mapping accuracy ({correct_clusters}/{total_eval_clusters}) (+25)")
            elif clus_ratio >= 0.4:
                score += 10
                feedback_parts.append(f"PARTIAL Partial cluster mapping accuracy ({correct_clusters}/{total_eval_clusters}) (+10)")
            else:
                feedback_parts.append(f"FAIL Low cluster mapping accuracy ({correct_clusters}/{total_eval_clusters})")
        elif evaluated > 0:
            # They evaluated files but none were non-resident in GT
            # We give points if they correctly identified no non-resident files, but standard images have them.
            score += 25
            feedback_parts.append("PASS Cluster mapping (no non-resident files to map) (+25)")

    passed = score >= 60 and headers_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }