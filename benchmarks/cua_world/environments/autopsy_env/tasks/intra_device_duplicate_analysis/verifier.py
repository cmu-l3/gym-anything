#!/usr/bin/env python3
"""
Verifier for intra_device_duplicate_analysis task.

Scoring (100 pts total, pass threshold = 65):
  10 pts  — Autopsy case created and DB found
  20 pts  — Ingest completed and hashes are populated in the DB (prevents bypassing Autopsy)
  20 pts  — Summary report exists, is recent, and TOTAL_DUPLICATE_GROUPS matches GT
  35 pts  — Duplicate MD5 accuracy. The hashes reported match GT duplicates exactly.
  15 pts  — Copy counts reported for each MD5 exactly match GT copy counts.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_intra_device_duplicate_analysis(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/duplicate_analysis_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/duplicate_analysis_gt.json")

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
            "feedback": "Result file not found — task was not attempted."
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull ground truth from VM ─────────────────────────────────────────────
    gt = {
        "total_nonzero_allocated": 0,
        "total_unique_hashes": 0,
        "total_duplicate_groups": 0,
        "duplicate_groups": {}
    }
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_dup_groups = gt.get("duplicate_groups", {})
    gt_total_groups = gt.get("total_duplicate_groups", 0)

    # ── Criterion 1: Case DB found (10 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found for Duplicate_Analysis_2024 (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Ingest with Hashes (20 pts) ──────────────────────────────
    if result.get("data_source_added") and result.get("db_has_hashes"):
        score += 20
        feedback_parts.append("PASS MD5 hashes computed in Autopsy DB (+20)")
    elif result.get("data_source_added") and result.get("ingest_completed"):
        score += 10
        feedback_parts.append("PARTIAL Data source ingested, but MD5 hashes missing in DB (+10)")
    else:
        feedback_parts.append("FAIL Ingest incomplete or MD5 module bypassed")

    # ── Verify Timestamps ─────────────────────────────────────────────────────
    start_time = result.get("start_time", 0)
    summary_mtime = result.get("summary_mtime", 0)
    groups_mtime = result.get("groups_file_mtime", 0)
    
    is_recent_summary = (start_time == 0 or summary_mtime >= start_time)
    is_recent_groups = (start_time == 0 or groups_mtime >= start_time)

    # ── Criterion 3: Summary Report Accuracy (20 pts) ─────────────────────────
    if result.get("summary_file_exists") and is_recent_summary:
        summary_content = result.get("summary_content", "").upper()
        match_dup = re.search(r"TOTAL_DUPLICATE_GROUPS:\s*(\d+)", summary_content)
        if match_dup:
            reported_dups = int(match_dup.group(1))
            if reported_dups == gt_total_groups:
                score += 20
                feedback_parts.append(f"PASS Summary TOTAL_DUPLICATE_GROUPS matches GT exactly ({reported_dups}) (+20)")
            elif reported_dups > 0 and abs(reported_dups - gt_total_groups) <= 3:
                score += 10
                feedback_parts.append(f"PARTIAL Summary TOTAL_DUPLICATE_GROUPS ({reported_dups}) close to GT ({gt_total_groups}) (+10)")
            else:
                feedback_parts.append(f"FAIL Summary TOTAL_DUPLICATE_GROUPS ({reported_dups}) differs significantly from GT ({gt_total_groups})")
        else:
            feedback_parts.append("FAIL Summary missing TOTAL_DUPLICATE_GROUPS count")
    else:
        feedback_parts.append("FAIL Summary file missing or stale")

    # ── Parse Agent Groups Report ─────────────────────────────────────────────
    agent_groups = {}
    if result.get("groups_file_exists") and is_recent_groups:
        groups_content = result.get("groups_content", "")
        blocks = groups_content.split("---")
        for block in blocks:
            md5_match = re.search(r"DUPLICATE_GROUP:\s*([a-fA-F0-9]{32})", block)
            copies_match = re.search(r"COPIES:\s*(\d+)", block)
            if md5_match and copies_match:
                md5 = md5_match.group(1).lower()
                copies = int(copies_match.group(1))
                agent_groups[md5] = copies

    # ── Criterion 4 & 5: MD5 Accuracy (35 pts) & Copy Count (15 pts) ──────────
    if not result.get("groups_file_exists"):
        feedback_parts.append("FAIL Groups report file missing")
    elif not is_recent_groups:
        feedback_parts.append("FAIL Groups report file is stale")
    elif len(agent_groups) == 0:
        feedback_parts.append("FAIL No valid duplicate groups found in report format")
    else:
        # Evaluate precision and recall of duplicate hashes
        gt_md5s = set(gt_dup_groups.keys())
        agent_md5s = set(agent_groups.keys())

        correct_md5s = agent_md5s.intersection(gt_md5s)
        false_positives = agent_md5s - gt_md5s
        false_negatives = gt_md5s - agent_md5s

        # MD5 Accuracy Scoring
        md5_score = 0
        if gt_total_groups > 0:
            recall = len(correct_md5s) / gt_total_groups
            precision = len(correct_md5s) / len(agent_md5s) if agent_md5s else 0
            
            # Weighted penalty for false positives
            if recall > 0.9 and precision > 0.9:
                md5_score = 35
                feedback_parts.append("PASS Agent identified duplicate MD5s perfectly (+35)")
            elif recall >= 0.5:
                # Base score for decent recall, scale by precision
                md5_score = int(35 * recall * precision)
                feedback_parts.append(f"PARTIAL Agent MD5 accuracy: found {len(correct_md5s)}/{gt_total_groups}, {len(false_positives)} false positives (+{md5_score})")
            else:
                md5_score = int(15 * recall)
                feedback_parts.append(f"FAIL Poor MD5 detection recall: found {len(correct_md5s)}/{gt_total_groups} (+{md5_score})")
        else:
            # Edge case: No duplicates exist in image
            if len(agent_md5s) == 0:
                md5_score = 35
                feedback_parts.append("PASS Correctly identified no duplicates exist (+35)")
            else:
                feedback_parts.append("FAIL Reported duplicates when none exist")
        
        score += md5_score

        # Copy Count Accuracy Scoring
        count_score = 0
        correct_counts = 0
        if len(correct_md5s) > 0:
            for md5 in correct_md5s:
                if agent_groups[md5] == len(gt_dup_groups[md5]):
                    correct_counts += 1
            
            count_ratio = correct_counts / len(correct_md5s)
            count_score = int(15 * count_ratio)
            score += count_score
            feedback_parts.append(f"PASS Copy counts correct for {correct_counts}/{len(correct_md5s)} valid hashes (+{count_score})")
        else:
            feedback_parts.append("FAIL Copy counts could not be verified due to missing valid MD5 hashes")

    # Determine pass/fail
    passed = score >= 65 and result.get("case_db_found")

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "\n".join(feedback_parts)
    }