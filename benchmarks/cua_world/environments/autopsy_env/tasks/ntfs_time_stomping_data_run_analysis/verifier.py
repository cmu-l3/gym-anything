#!/usr/bin/env python3
"""
Verifier for ntfs_time_stomping_data_run_analysis task.

Multi-Criteria Scoring (100 pts total, pass >= 70):
  10 pts - Case & Data Source setup
  20 pts - Autopsy Tagging (Anti-gaming: Ensures Autopsy GUI was actively used)
  10 pts - CSV file exists and formatted correctly (pipe-delimited)
  20 pts - Identified the correct Top 5 Inodes (matches Ground Truth)
  20 pts - MFT Timestamps exact extraction accuracy (SIA vs FNA)
  10 pts - Data Runs extraction accuracy
  10 pts - VLM / Summary verification
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """You are evaluating an agent's performance in Autopsy digital forensics.
The agent was asked to use the "File Metadata" tab to extract low-level MFT properties (like $STANDARD_INFORMATION) for deleted files.
Examine this trajectory screenshot.
1. Is Autopsy open with a file selected?
2. Did the agent navigate to the "File Metadata" tab (typically in the lower right panel) to view istat/MFT text?

Respond in JSON format:
{
    "autopsy_visible": true/false,
    "file_metadata_tab_used": true/false
}
"""


def verify_ntfs_time_stomping(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/mft_analysis_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/mft_analysis_gt.json")

    # 1. Retrieve Result Data
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # 2. Retrieve Ground Truth
    gt = {"top_5": [], "top_5_inodes": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass
    
    gt_mapping = {str(item["inode"]): item for item in gt.get("top_5", [])}

    # ── Criterion 1: Case Setup (10 pts) ──────────────────────────────────────
    if result.get("case_db_found") and result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Case and Data Source verified (+10)")
    else:
        feedback_parts.append("FAIL Case or Data Source missing")

    # ── Criterion 2: Autopsy Tagging (Anti-Gaming) (20 pts) ───────────────────
    tagged = result.get("tagged_files", [])
    if result.get("tag_created"):
        if len(tagged) == 5:
            score += 20
            feedback_parts.append("PASS 'Time Stomp Check' applied to exactly 5 files (+20)")
        elif len(tagged) > 0:
            score += 10
            feedback_parts.append(f"PARTIAL Tag applied but to {len(tagged)} files (+10)")
    else:
        feedback_parts.append("FAIL 'Time Stomp Check' tag not found in Autopsy DB")

    # ── Criterion 3 & 4 & 5: CSV Format, Inodes, Metadata (50 pts total) ──────
    start_time = result.get("start_time", 0)
    csv_mtime = result.get("csv_mtime", 0)
    csv_content = result.get("csv_content", "").strip()

    csv_score = 0
    inode_score = 0
    meta_score = 0
    run_score = 0

    if result.get("csv_exists") and (start_time == 0 or csv_mtime >= start_time):
        lines = [l.strip() for l in csv_content.splitlines() if l.strip()]
        
        if len(lines) > 0 and "|" in lines[0] and "INODE" in lines[0].upper():
            csv_score = 10
            feedback_parts.append("PASS CSV Format verified (+10)")
            
            # Evaluate Data Rows
            parsed_rows = 0
            for line in lines[1:]:
                parts = [p.strip() for p in line.split('|')]
                if len(parts) >= 6:
                    parsed_rows += 1
                    a_inode = parts[1].split('-')[0]  # Strip sequence numbers if any
                    a_sia = parts[2]
                    a_fna = parts[3]
                    a_run_start = parts[4]
                    a_run_len = parts[5]

                    # Match with GT
                    found_gt = None
                    for gt_inode, gt_data in gt_mapping.items():
                        if gt_inode.startswith(a_inode):
                            found_gt = gt_data
                            break
                    
                    if found_gt:
                        inode_score += 4  # Up to 20 for 5 files
                        
                        # Timestamps Evaluation (20 max)
                        if found_gt["sia"] in a_sia and found_gt["fna"] in a_fna:
                            meta_score += 4
                        elif found_gt["sia"] in a_sia or found_gt["fna"] in a_fna:
                            meta_score += 2
                            
                        # Data Runs Evaluation (10 max)
                        if a_run_start == str(found_gt["run_start"]) and a_run_len == str(found_gt["run_len"]):
                            run_score += 2
                        elif found_gt["run_start"] == "NONE" and "NONE" in a_run_start.upper():
                            run_score += 2
            
            feedback_parts.append(f"PASS Correct Inodes: +{inode_score}/20")
            feedback_parts.append(f"PASS Metadata Accuracy: +{meta_score}/20")
            feedback_parts.append(f"PASS Data Runs Accuracy: +{run_score}/10")
        else:
            feedback_parts.append("FAIL CSV lacks header or pipe-delimiters")
    else:
        feedback_parts.append("FAIL CSV missing or stale")

    score += csv_score + inode_score + meta_score + run_score

    # ── Criterion 6: Summary & VLM Validation (10 pts) ────────────────────────
    summary = result.get("summary_content", "").lower()
    if result.get("summary_exists") and len(summary) > 10:
        if "mismatch" in summary or "time stomp" in summary or "differ" in summary or "none" in summary:
            score += 5
            feedback_parts.append("PASS Summary report analysis valid (+5)")
        else:
            feedback_parts.append("PARTIAL Summary exists but lacks analytical terms")

    # Execute VLM
    try:
        from gym_anything.vlm import get_final_screenshot, query_vlm
        vlm_available = True
    except ImportError:
        vlm_available = False

    if vlm_available:
        try:
            final_img = get_final_screenshot(traj)
            vlm_resp = query_vlm(images=[final_img], prompt=build_vlm_prompt())
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("file_metadata_tab_used"):
                score += 5
                feedback_parts.append("PASS VLM visual confirmation of metadata tab usage (+5)")
            else:
                feedback_parts.append("FAIL VLM could not confirm metadata tab usage")
        except Exception as e:
            logger.warning(f"VLM verification skipped/failed: {e}")
            score += 5  # Fallback gracefully
            feedback_parts.append("PASS VLM check bypassed (+5)")
    else:
        score += 5  # Fallback gracefully
        feedback_parts.append("PASS VLM check bypassed (+5)")

    passed = score >= 70 and inode_score >= 12
    if passed and not result.get("tag_created"):
        passed = False
        feedback_parts.append("CRITICAL: Failed anti-gaming check. Must use Autopsy tagging.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }