#!/usr/bin/env python3
"""
Verifier for deleted_file_differential_analysis task.

Scoring (100 pts total, pass threshold = 60):
  10 pts - Case DB found for Deletion_Differential_2024
  10 pts - Disk image data source added
  10 pts - Ingest completed (files indexed)
  10 pts - Differential report exists and is recent
  10 pts - Allocated file count correct (±2)
  10 pts - Deleted file count correct (±2)
   5 pts - Deletion ratio correct (±0.1)
  10 pts - Allocated files listing covers ≥50%
  10 pts - Deleted files listing covers ≥50%
   5 pts - Type distribution sections present
   5 pts - Summary file exists with correct format
   5 pts - Deletion pattern assessment present

Also uses VLM on trajectory to verify Autopsy usage (visual verification).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine these trajectory screenshots from a digital forensics task.
Did the user interact with the Autopsy digital forensics interface?
Look specifically for signs that they browsed through the file system tree, looked at allocated files, or looked at deleted files (often marked with a red X or under $OrphanFiles).

Respond in JSON format:
{
    "autopsy_used": true/false,
    "browsed_files": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""


def verify_deleted_file_differential_analysis(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/deletion_differential_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/deletion_differential_gt.json")
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not provided"}

    # ── Pull result JSON ──────────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull ground truth ──────────────────────────────────────────────────────
    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_alloc_count = gt.get("allocated_count", 0)
    gt_del_count = gt.get("deleted_count", 0)
    gt_ratio = gt.get("deletion_ratio", 0.0)
    gt_alloc_names = set(gt.get("allocated_names", []))
    gt_del_names = set(gt.get("deleted_names", []))

    # ── DB & Autopsy Criteria (30 pts) ────────────────────────────────────────
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

    # ── Report Exists & Recent (10 pts) ───────────────────────────────────────
    start_time = result.get("start_time", 0)
    report_mtime = result.get("report_mtime", 0)
    report_content = result.get("report_content", "")
    summary_content = result.get("summary_content", "")
    
    if result.get("report_file_exists"):
        if start_time == 0 or report_mtime >= start_time:
            score += 10
            feedback_parts.append("PASS Report exists and is recent (+10)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Report exists but is stale (+5)")
    else:
        feedback_parts.append("FAIL Report not found")

    # ── Parse Report Data ─────────────────────────────────────────────────────
    alloc_count_match = re.search(r"ALLOCATED_FILE_COUNT:\s*(\d+)", report_content)
    del_count_match = re.search(r"DELETED_FILE_COUNT:\s*(\d+)", report_content)
    ratio_match = re.search(r"DELETION_RATIO:\s*([\d.]+)", report_content)

    rep_alloc_count = int(alloc_count_match.group(1)) if alloc_count_match else -1
    rep_del_count = int(del_count_match.group(1)) if del_count_match else -1
    rep_ratio = float(ratio_match.group(1)) if ratio_match else -1.0

    # Counts (25 pts total)
    if rep_alloc_count >= 0 and abs(rep_alloc_count - gt_alloc_count) <= 2:
        score += 10
        feedback_parts.append(f"PASS Allocated count {rep_alloc_count} matches GT {gt_alloc_count} (+10)")
    elif rep_alloc_count >= 0:
        feedback_parts.append(f"FAIL Allocated count {rep_alloc_count} != GT {gt_alloc_count}")

    if rep_del_count >= 0 and abs(rep_del_count - gt_del_count) <= 2:
        score += 10
        feedback_parts.append(f"PASS Deleted count {rep_del_count} matches GT {gt_del_count} (+10)")
    elif rep_del_count >= 0:
        feedback_parts.append(f"FAIL Deleted count {rep_del_count} != GT {gt_del_count}")

    if rep_ratio >= 0.0 and abs(rep_ratio - gt_ratio) <= 0.1:
        score += 5
        feedback_parts.append(f"PASS Ratio {rep_ratio} matches GT {gt_ratio} (+5)")
    elif rep_ratio >= 0.0:
        feedback_parts.append(f"FAIL Ratio {rep_ratio} != GT {gt_ratio}")

    # Coverage (20 pts total)
    alloc_block = ""
    del_block = ""
    if "ALLOCATED_FILES:" in report_content and "DELETED_FILES:" in report_content:
        alloc_block = report_content.split("ALLOCATED_FILES:")[1].split("DELETED_FILES:")[0]
    if "DELETED_FILES:" in report_content and "TYPE_DISTRIBUTION_ALLOCATED:" in report_content:
        del_block = report_content.split("DELETED_FILES:")[1].split("TYPE_DISTRIBUTION_ALLOCATED:")[0]
        
    rep_alloc_names = set(line.split("|")[0].strip().lower() for line in alloc_block.splitlines() if "|" in line)
    rep_del_names = set(line.split("|")[0].strip().lower() for line in del_block.splitlines() if "|" in line)

    if gt_alloc_names:
        alloc_overlap = len(rep_alloc_names.intersection(gt_alloc_names))
        if alloc_overlap / len(gt_alloc_names) >= 0.5:
            score += 10
            feedback_parts.append("PASS Allocated file coverage >= 50% (+10)")
        elif alloc_overlap > 0:
            score += 5
            feedback_parts.append("PARTIAL Allocated file coverage < 50% (+5)")

    if gt_del_names:
        del_overlap = len(rep_del_names.intersection(gt_del_names))
        if del_overlap / len(gt_del_names) >= 0.5:
            score += 10
            feedback_parts.append("PASS Deleted file coverage >= 50% (+10)")
        elif del_overlap > 0:
            score += 5
            feedback_parts.append("PARTIAL Deleted file coverage < 50% (+5)")

    # Type Distributions (5 pts)
    if "TYPE_DISTRIBUTION_ALLOCATED:" in report_content and "TYPE_DISTRIBUTION_DELETED:" in report_content:
        score += 5
        feedback_parts.append("PASS Type distributions present (+5)")

    # Summary File (5 pts)
    if result.get("summary_file_exists") and "CASE_NUMBER" in summary_content and "DELETION_PATTERN_ASSESSMENT" in summary_content:
        score += 5
        feedback_parts.append("PASS Summary file exists & formatted (+5)")

    # Assessment (5 pts)
    assessment_match = re.search(r"DELETION_PATTERN_ASSESSMENT:\s*(SYSTEMATIC|INCIDENTAL|INCONCLUSIVE)", report_content, re.IGNORECASE)
    justification_match = re.search(r"ASSESSMENT_JUSTIFICATION:\s*(.+)", report_content, re.IGNORECASE)
    if assessment_match and justification_match and len(justification_match.group(1).strip()) > 5:
        score += 5
        feedback_parts.append("PASS Pattern assessment & justification present (+5)")

    # ── VLM Verification (Gating / Logging) ───────────────────────────────────
    vlm_passed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        vlm_res = query_vlm(images=frames + [final], prompt=build_vlm_prompt())
        
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("autopsy_used", False) and parsed.get("browsed_files", False):
                vlm_passed = True
                feedback_parts.append("VLM confirms Autopsy interaction.")
            else:
                feedback_parts.append(f"VLM did not confirm Autopsy usage. Reasoning: {parsed.get('reasoning')}")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        vlm_passed = True  # Do not punish if VLM fails technically

    # ── Final Determination ───────────────────────────────────────────────────
    passed = (score >= 60) and result.get("report_file_exists") and vlm_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }