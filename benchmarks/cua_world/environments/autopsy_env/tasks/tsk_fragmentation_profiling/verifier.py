#!/usr/bin/env python3
"""
Verifier for tsk_fragmentation_profiling task.

Scoring (100 pts total, pass threshold = 70):
  10 pts  — CSV Structure: Exists with correct headers.
  25 pts  — Comprehensive Recall: All regular allocated files represented correctly.
  25 pts  — Accurate Run Counts: The calculated RUN_COUNT matches ground truth exactly.
  10 pts  — Correct Sorting: CSV is sorted by Run_Count (DESC) then Inode (ASC).
  15 pts  — Split Point Identification: Text file accurately details the highest fragmented file and sector.
  15 pts  — Raw Sector Extraction: The extracted .bin file hash matches the actual data block hash.
"""

import json
import os
import csv
import io
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tsk_fragmentation_profiling(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/fragmentation_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/tsk_fragmentation_gt.json")

    # ── Pull Exported Results ─────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — task was not attempted."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull Ground Truth ─────────────────────────────────────────────────────
    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        return {"passed": False, "score": 0, "feedback": "Ground truth not found — setup failure."}

    start_time = result.get("start_time", 0)

    # ── Verify CSV Content & Structure (10 pts) ───────────────────────────────
    csv_exists = result.get("csv_exists", False)
    csv_content = result.get("csv_content", "").strip()
    agent_dict = {}
    agent_order = []
    
    csv_is_recent = result.get("csv_mtime", 0) >= start_time

    if csv_exists and csv_content and csv_is_recent:
        try:
            reader = csv.reader(io.StringIO(csv_content))
            rows = list(reader)
            if rows:
                header = [h.strip().upper() for h in rows[0]]
                if header == ["INODE", "FILENAME", "RUN_COUNT"]:
                    score += 10
                    feedback_parts.append("PASS CSV header is exact (+10)")
                else:
                    feedback_parts.append("FAIL CSV header does not match expected format exactly")

                for row in rows[1:]:
                    if len(row) >= 3:
                        try:
                            inode = int(row[0].strip())
                            name = row[1].strip()
                            count = int(row[2].strip())
                            agent_dict[inode] = {"name": name, "count": count}
                            agent_order.append(inode)
                        except ValueError:
                            continue
        except Exception as e:
            feedback_parts.append(f"FAIL Parsing CSV: {e}")
    else:
        feedback_parts.append("FAIL CSV file missing, empty, or stale")

    # ── Verify Comprehensive Recall (25 pts) ──────────────────────────────────
    gt_dict = {f["inode"]: f for f in gt.get("files", [])}
    gt_order = [f["inode"] for f in gt.get("files", [])]
    
    missing = set(gt_dict.keys()) - set(agent_dict.keys())
    extra = set(agent_dict.keys()) - set(gt_dict.keys())

    if gt_dict and not missing and not extra:
        score += 25
        feedback_parts.append("PASS Comprehensive Recall: Found all allocated files (+25)")
    elif gt_dict and len(missing) < max(5, int(len(gt_dict)*0.1)) and len(extra) < max(5, int(len(gt_dict)*0.1)):
        score += 15
        feedback_parts.append(f"PARTIAL Recall: Missing {len(missing)} extra {len(extra)} (+15)")
    else:
        feedback_parts.append(f"FAIL Recall: Missing {len(missing)}, Extra {len(extra)} (Total GT: {len(gt_dict)})")

    # ── Verify Accurate Run Counts (25 pts) ───────────────────────────────────
    correct_counts = 0
    for inode, adata in agent_dict.items():
        if inode in gt_dict and gt_dict[inode]["run_count"] == adata["count"]:
            correct_counts += 1

    if gt_dict and correct_counts == len(gt_dict) and not missing and not extra:
        score += 25
        feedback_parts.append("PASS Accurate Run Counts: All counts match ground truth perfectly (+25)")
    elif gt_dict and correct_counts >= len(gt_dict) * 0.8:
        score += 15
        feedback_parts.append(f"PARTIAL Run Counts: {correct_counts}/{len(gt_dict)} matched exactly (+15)")
    else:
        feedback_parts.append(f"FAIL Run Counts: Only {correct_counts}/{len(gt_dict)} matched")

    # ── Verify Correct Sorting (10 pts) ───────────────────────────────────────
    if agent_order and gt_order:
        # Check if agent list is properly sorted by their OWN counts (Descending) then Inode (Ascending)
        # Re-sort agent list to see if it matches
        expected_agent_sort = sorted(agent_dict.items(), key=lambda item: (-item[1]['count'], item[0]))
        expected_agent_order = [inode for inode, data in expected_agent_sort]
        
        if agent_order == expected_agent_order:
            score += 10
            feedback_parts.append("PASS Correct Sorting: CSV is sorted properly (+10)")
        else:
            feedback_parts.append("FAIL Correct Sorting: CSV is not sorted by RUN_COUNT DESC, INODE ASC")

    # ── Verify Split Point ID (15 pts) ────────────────────────────────────────
    txt_exists = result.get("txt_exists", False)
    txt_content = result.get("txt_content", "")
    txt_is_recent = result.get("txt_mtime", 0) >= start_time
    
    gt_sector = gt.get("second_run_sector", -1)
    gt_target = gt.get("most_fragmented", {})

    parsed_txt = {}
    for line in txt_content.split('\n'):
        if ':' in line:
            k, v = line.split(':', 1)
            parsed_txt[k.strip().upper()] = v.strip()

    if txt_exists and txt_is_recent:
        try:
            agent_sector = int(parsed_txt.get("SECOND_RUN_START_SECTOR", "-99"))
            if agent_sector == gt_sector and gt_sector != -1:
                score += 15
                feedback_parts.append(f"PASS Split Point ID: Found correct split sector {gt_sector} (+15)")
            else:
                feedback_parts.append(f"FAIL Split Point ID: Expected {gt_sector}, got {agent_sector}")
        except Exception:
            feedback_parts.append("FAIL Split Point ID: Formatting error or missing key in text file")
    else:
        feedback_parts.append("FAIL Split Point ID: Text file missing or stale")

    # ── Verify Raw Sector Extraction (15 pts) ─────────────────────────────────
    bin_exists = result.get("bin_exists", False)
    bin_is_recent = result.get("bin_mtime", 0) >= start_time
    bin_hash = result.get("bin_hash", "")
    gt_hash = gt.get("sector_hash", "N/A")

    if bin_exists and bin_is_recent:
        if bin_hash == gt_hash and gt_hash != "N/A":
            score += 15
            feedback_parts.append("PASS Raw Sector Extraction: Block hash matches Ground Truth exactly (+15)")
        else:
            feedback_parts.append(f"FAIL Raw Sector Extraction: Block hash mismatch")
    else:
        feedback_parts.append("FAIL Raw Sector Extraction: Binary file missing or stale")

    # ── Evaluation ────────────────────────────────────────────────────────────
    # Minimum requirement for passing is >70% combined with having largely generated accurate CSV
    key_criteria_met = (correct_counts >= len(gt_dict) * 0.8) and (len(missing) < max(5, int(len(gt_dict)*0.1)))
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }