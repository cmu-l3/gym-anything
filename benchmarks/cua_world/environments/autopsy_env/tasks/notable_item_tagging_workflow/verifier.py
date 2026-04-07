#!/usr/bin/env python3
"""
Verifier for notable_item_tagging_workflow task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case created and data source added
  20 pts  — Deleted files properly tagged as "Notable Item"
  20 pts  — Allocated files properly tagged as "Follow Up"
  10 pts  — Tag comments contain required investigator notes
  20 pts  — Autopsy HTML report successfully generated via Tools > Generate Report
  20 pts  — Manual tagging summary exists with correct formatting
"""

import json
import os
import tempfile

def verify_notable_item_tagging_workflow(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    
    result_file_vm = meta.get("result_file", "/tmp/tagging_workflow_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/tagging_workflow_gt.json")
    expected_notable_comment = meta.get("expected_notable_comment", "Deleted file - evidence of potential data destruction").lower()
    expected_followup_comment = meta.get("expected_followup_comment", "Active file - content review required for relevance").lower()

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
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # ── Pull ground truth from VM ──────────────────────────────────────────────
    gt = {"total_deleted": 0, "total_allocated": 0, "deleted_names": [], "allocated_names": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_deleted_names = set(n.lower() for n in gt.get("deleted_names", []))
    gt_allocated_names = set(n.lower() for n in gt.get("allocated_names", []))
    
    # Tolerances (agent doesn't need to tag literally every single trivial file, but should hit >= 50%)
    target_deleted = max(1, len(gt_deleted_names) // 2)
    target_allocated = max(1, len(gt_allocated_names) // 2)

    # ── Criterion 1: Case & Data Source (10 pts) ─────────────────────────────
    if result.get("case_db_found") and result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Case created and data source added (+10)")
    else:
        feedback_parts.append("FAIL Case or data source not found")

    # ── Criterion 2: Notable Item Tags on Deleted Files (20 pts) ─────────────
    db_notable_count = result.get("db_notable_tags_count", 0)
    db_notable_files = set(f.lower() for f in result.get("db_tagged_deleted_files", []))
    notable_overlap = len(db_notable_files.intersection(gt_deleted_names))
    
    if db_notable_count > 0:
        if notable_overlap >= target_deleted:
            score += 20
            feedback_parts.append(f"PASS Sufficient deleted files tagged as Notable Item ({notable_overlap} matches) (+20)")
        else:
            score += 10
            feedback_parts.append(f"PARTIAL Some deleted files tagged as Notable Item ({notable_overlap}/{target_deleted} target) (+10)")
    else:
        feedback_parts.append("FAIL No Notable Item tags found")

    # ── Criterion 3: Follow Up Tags on Allocated Files (20 pts) ──────────────
    db_followup_count = result.get("db_followup_tags_count", 0)
    db_followup_files = set(f.lower() for f in result.get("db_tagged_allocated_files", []))
    followup_overlap = len(db_followup_files.intersection(gt_allocated_names))
    
    if db_followup_count > 0:
        if followup_overlap >= target_allocated:
            score += 20
            feedback_parts.append(f"PASS Sufficient allocated files tagged as Follow Up ({followup_overlap} matches) (+20)")
        else:
            score += 10
            feedback_parts.append(f"PARTIAL Some allocated files tagged as Follow Up ({followup_overlap}/{target_allocated} target) (+10)")
    else:
        feedback_parts.append("FAIL No Follow Up tags found")

    # ── Criterion 4: Tag Comments (10 pts) ───────────────────────────────────
    comments = [c.lower() for c in result.get("db_tag_comments", [])]
    has_notable_comment = any(expected_notable_comment in c for c in comments)
    has_followup_comment = any(expected_followup_comment in c for c in comments)
    
    if has_notable_comment and has_followup_comment:
        score += 10
        feedback_parts.append("PASS Both required tag comments found (+10)")
    elif has_notable_comment or has_followup_comment:
        score += 5
        feedback_parts.append("PARTIAL Only one of the required tag comments found (+5)")
    else:
        feedback_parts.append("FAIL Required tag comments not found")

    # ── Criterion 5: HTML Report Generated (20 pts) ──────────────────────────
    if result.get("html_report_generated"):
        report_mtime = result.get("html_report_mtime", 0)
        start_time = result.get("start_time", 0)
        if start_time == 0 or report_mtime >= start_time:
            score += 20
            feedback_parts.append("PASS Autopsy HTML report generated during task (+20)")
        else:
            score += 10
            feedback_parts.append("PARTIAL Autopsy HTML report exists but may be stale (+10)")
    else:
        feedback_parts.append("FAIL Autopsy HTML report not found in case directory")

    # ── Criterion 6: Summary File (20 pts) ───────────────────────────────────
    if result.get("summary_file_exists"):
        summary_mtime = result.get("summary_mtime", 0)
        start_time = result.get("start_time", 0)
        content = result.get("summary_content", "").upper()
        
        has_case_name = "CASE_NAME: COURT_PREP_2024" in content
        has_notable_count = "NOTABLE_ITEMS_TAGGED:" in content
        has_followup_count = "FOLLOW_UP_ITEMS_TAGGED:" in content
        has_notes = "INVESTIGATOR_NOTES:" in content
        
        if (start_time == 0 or summary_mtime >= start_time) and has_case_name and has_notable_count and has_followup_count and has_notes:
            score += 20
            feedback_parts.append("PASS Tagging summary file complete and correctly formatted (+20)")
        elif has_case_name or has_notes:
            score += 10
            feedback_parts.append("PARTIAL Tagging summary file exists but is missing required fields (+10)")
        else:
            feedback_parts.append("FAIL Tagging summary file lacks required structure")
    else:
        feedback_parts.append("FAIL Tagging summary file not found at /home/ga/Reports/tagging_summary.txt")

    # ── Final Assessment ─────────────────────────────────────────────────────
    passed = score >= 60 and result.get("html_report_generated")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }