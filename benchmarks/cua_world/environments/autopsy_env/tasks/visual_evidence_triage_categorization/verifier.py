#!/usr/bin/env python3
"""
Verifier for visual_evidence_triage_categorization task.

Scoring System (100 points total, pass threshold: 75):
- Case Setup (15 pts): Case created and Logical Files ingested successfully.
- Tag Creation (10 pts): Custom tag `Aircraft_Evidence` exists in the SQLite `tag_names` table.
- True Positives (Recall) (40 pts): Agent tagged the airplane images (proportional, max 40).
- False Positives (Precision) (-20 pts): Penalty for tagging cars as aircraft (subtract 5 pts per error, max -20).
- Exported Report (15 pts): Report CSV exists and is recent.
- Report Accuracy (20 pts): The CSV contents match the tags actually found in the Autopsy database.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_visual_evidence_triage(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/visual_triage_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/visual_triage_gt.json")

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

    # ── Pull ground truth from VM ─────────────────────────────────────────────
    gt = {"target_aircraft": [], "decoy_cars": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        logger.warning("Ground truth file not found on VM, scoring may be incomplete.")

    target_aircraft = set(gt.get("target_aircraft", []))
    decoy_cars = set(gt.get("decoy_cars", []))
    
    # ── Criterion 1: Case Setup (15 pts) ──────────────────────────────────────
    if result.get("case_db_found") and result.get("data_source_added") and result.get("ingest_completed"):
        score += 15
        feedback_parts.append("PASS Case Aviation_Smuggling_2024 created and data ingested (+15)")
    elif result.get("case_db_found"):
        score += 5
        feedback_parts.append("PARTIAL Case created but data source missing/incomplete (+5)")
    else:
        feedback_parts.append("FAIL Case database not found")

    # ── Criterion 2: Tag Creation (10 pts) ────────────────────────────────────
    if result.get("target_tag_exists"):
        score += 10
        feedback_parts.append("PASS Custom tag 'Aircraft_Evidence' created (+10)")
    else:
        feedback_parts.append("FAIL Target tag 'Aircraft_Evidence' not found in database")

    # ── Criterion 3 & 4: True Positives (40 pts) and False Positives (Penalty) 
    tagged_files = set(result.get("tagged_files", []))
    true_positives = tagged_files.intersection(target_aircraft)
    false_positives = tagged_files.intersection(decoy_cars)
    
    tp_count = len(true_positives)
    fp_count = len(false_positives)
    target_count = len(target_aircraft)
    
    if target_count > 0:
        # 40 points proportional to recall
        tp_score = min(40, int((tp_count / target_count) * 40))
        score += tp_score
        feedback_parts.append(f"PASS Visual tagging True Positives: {tp_count}/{target_count} (+{tp_score})")
        
        # False Positive Penalty (-5 per FP, max -20)
        if fp_count > 0:
            fp_penalty = max(-20, fp_count * -5)
            score += fp_penalty
            feedback_parts.append(f"PENALTY Visual tagging False Positives: {fp_count} cars tagged as aircraft ({fp_penalty})")
    else:
        feedback_parts.append("FAIL Ground truth missing, cannot evaluate tagging accuracy")

    # ── Criterion 5: Exported Report (15 pts) ─────────────────────────────────
    start_time = result.get("start_time", 0)
    report_mtime = result.get("report_mtime", 0)
    report_content = result.get("report_content", "").strip()
    
    report_exists_and_recent = False
    if result.get("report_file_exists"):
        if start_time == 0 or report_mtime >= start_time:
            report_exists_and_recent = True
            score += 15
            feedback_parts.append("PASS CSV report file exists and is recent (+15)")
        else:
            score += 5
            feedback_parts.append("PARTIAL CSV report file exists but predates task start (+5)")
    else:
        feedback_parts.append("FAIL CSV report not found at expected path")

    # ── Criterion 6: Report Accuracy (20 pts) ─────────────────────────────────
    if report_exists_and_recent and report_content:
        # Extract filenames from report lines (agent should have listed them)
        report_lines = [line.strip() for line in report_content.splitlines() if line.strip()]
        
        # Simple match check: does the report contain the tagged files?
        matched_in_report = 0
        for tf in tagged_files:
            if any(tf in line for line in report_lines):
                matched_in_report += 1
                
        if len(tagged_files) > 0:
            accuracy = matched_in_report / len(tagged_files)
            if accuracy >= 0.9:
                score += 20
                feedback_parts.append("PASS Report accurately reflects tagged items in DB (+20)")
            elif accuracy >= 0.5:
                score += 10
                feedback_parts.append(f"PARTIAL Report partially reflects DB tagged items ({matched_in_report}/{len(tagged_files)}) (+10)")
            else:
                feedback_parts.append("FAIL Report contents do not align with DB tagged items")
        else:
            if len(report_lines) == 0:
                score += 20
                feedback_parts.append("PASS Report is correctly empty (matches 0 DB tags) (+20)")
            else:
                feedback_parts.append("FAIL Report contains items but no DB tags exist")
    else:
        feedback_parts.append("FAIL Report accuracy cannot be evaluated (missing/empty file)")

    # ── Final Evaluation ──────────────────────────────────────────────────────
    # Pass requires >= 75 points AND at least 3 True Positives and < 2 False Positives
    key_criteria_met = (tp_count >= 3) and (fp_count < 2)
    passed = score >= 75 and key_criteria_met
    
    if passed:
        feedback_parts.append("RESULT: PASSED")
    else:
        feedback_parts.append(f"RESULT: FAILED (Key visual criteria met: {key_criteria_met})")

    # Ensure score bounds
    score = max(0, min(100, score))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "true_positives": tp_count,
            "false_positives": fp_count,
            "target_count": target_count,
            "report_matched": matched_in_report if 'matched_in_report' in locals() else 0
        }
    }