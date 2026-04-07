#!/usr/bin/env python3
"""
Verifier for custom_interesting_items_triage task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Case Setup (DB exists, data source added)
  25 pts  — Rule Config & Execution (DB contains TSK_INTERESTING_FILE_HIT for 'Config_And_Logs') [Anti-Gaming]
  15 pts  — TSV Catalog Format (Header present, tab-delimited)
  30 pts  — TSV Content Accuracy (Files & MD5 hashes cover >=80% of GT)
  20 pts  — Summary Report matches requirements and math is correct
"""

import json
import os
import re
import tempfile

def verify_custom_interesting_items_triage(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/triage_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/triage_gt.json")

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
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # ── Pull ground truth from VM ──────────────────────────────────────────────
    gt = {"total_targets": 0, "target_files": [], "target_names": [], "txt_count": 0, "log_count": 0, "xml_count": 0}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_names = set(n.lower() for n in gt.get("target_names", []))
    gt_total = gt.get("total_targets", 0)
    
    # ── Criterion 1: Case Setup (10 pts) ──────────────────────────────────────
    if result.get("case_db_found") and result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Case DB found and data source added (+10)")
    else:
        feedback_parts.append("FAIL Case DB or data source missing")

    # ── Criterion 2: Rule Config & Execution [ANTI-GAMING] (25 pts) ───────────
    db_config_hits = result.get("db_config_logs_hits", 0)
    rule_executed = False
    
    if db_config_hits > 0:
        score += 25
        rule_executed = True
        feedback_parts.append(f"PASS Autopsy DB contains {db_config_hits} hits for 'Config_And_Logs' rule (+25)")
    else:
        if result.get("db_interesting_hits_count", 0) > 0:
            feedback_parts.append("FAIL Interesting Items found, but NOT for set 'Config_And_Logs'")
        else:
            feedback_parts.append("FAIL No Interesting Item artifacts in DB. Module not configured or not run.")

    # ── Criterion 3: TSV Format (15 pts) ──────────────────────────────────────
    start_time = result.get("start_time", 0)
    tsv_content = result.get("tsv_content", "").replace("\\n", "\n").replace("\\t", "\t")
    tsv_lines = [l.strip() for l in tsv_content.splitlines() if l.strip()]
    
    has_header = False
    is_tabbed = False
    if result.get("tsv_file_exists"):
        if any("FILENAME" in l.upper() and "EXTENSION" in l.upper() for l in tsv_lines[:3]):
            has_header = True
        if any("\t" in l for l in tsv_lines):
            is_tabbed = True
            
        if has_header and is_tabbed:
            score += 15
            feedback_parts.append("PASS TSV catalog has correct header and is tab-delimited (+15)")
        elif is_tabbed or len(tsv_lines) > 1:
            score += 7
            feedback_parts.append("PARTIAL TSV catalog exists but formatting/header is incorrect (+7)")
        else:
            feedback_parts.append("FAIL TSV file exists but format is unreadable")
    else:
        feedback_parts.append("FAIL TSV catalog file not found")

    # ── Criterion 4: TSV Content Accuracy (30 pts) ────────────────────────────
    # Earning this REQUIRES rule_executed to be True to prevent gaming!
    if not rule_executed:
        feedback_parts.append("FAIL TSV content ignored because DB artifacts (Rule Execution) failed (Anti-Gaming)")
    elif tsv_lines and gt_total > 0:
        tsv_lower = tsv_content.lower()
        
        # Check filename coverage
        found_names = sum(1 for n in gt_names if n in tsv_lower)
        name_coverage = found_names / gt_total if gt_total else 0
        
        # Check MD5 coverage (only for files with MD5s available)
        gt_md5s = set(f["md5"].lower() for f in gt.get("target_files", []) if f.get("md5") and f["md5"] != "n/a")
        found_md5s = sum(1 for m in gt_md5s if m in tsv_lower)
        md5_coverage = found_md5s / len(gt_md5s) if gt_md5s else 0
        
        avg_coverage = (name_coverage + md5_coverage) / 2
        
        if avg_coverage >= 0.8:
            score += 30
            feedback_parts.append(f"PASS TSV covers {found_names}/{gt_total} files and {found_md5s}/{len(gt_md5s)} hashes (+30)")
        elif avg_coverage >= 0.4:
            score += 15
            feedback_parts.append(f"PARTIAL TSV coverage is partial: {avg_coverage*100:.1f}% (+15)")
        else:
            feedback_parts.append(f"FAIL TSV content inaccurate (coverage: {avg_coverage*100:.1f}%)")

    # ── Criterion 5: Summary Report (20 pts) ──────────────────────────────────
    summary_content = result.get("summary_content", "").upper()
    if result.get("summary_file_exists"):
        has_reqs = all(k in summary_content for k in ["INV-TRG-001", "CONFIG_AND_LOGS", "TOTAL_FLAGGED_FILES"])
        
        # Extract counts safely
        try:
            total_match = re.search(r'TOTAL_FLAGGED_FILES[^\d]+(\d+)', summary_content)
            rep_total = int(total_match.group(1)) if total_match else -1
            
            txt_match = re.search(r'TXT_COUNT[^\d]+(\d+)', summary_content)
            rep_txt = int(txt_match.group(1)) if txt_match else 0
            
            log_match = re.search(r'LOG_COUNT[^\d]+(\d+)', summary_content)
            rep_log = int(log_match.group(1)) if log_match else 0
            
            xml_match = re.search(r'XML_COUNT[^\d]+(\d+)', summary_content)
            rep_xml = int(xml_match.group(1)) if xml_match else 0
            
            math_correct = (rep_total == (rep_txt + rep_log + rep_xml)) and rep_total > 0
        except Exception:
            math_correct = False

        if has_reqs and math_correct:
            score += 20
            feedback_parts.append("PASS Summary report has all requirements and correct math (+20)")
        elif has_reqs:
            score += 10
            feedback_parts.append("PARTIAL Summary report missing accurate math/fields (+10)")
        else:
            feedback_parts.append("FAIL Summary report missing required sections")
    else:
        feedback_parts.append("FAIL Summary file not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }