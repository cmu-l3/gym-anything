#!/usr/bin/env python3
"""
Verifier for metadata_filesystem_timestamp_divergence task.

Scoring (100 pts total, pass threshold = 60):
  15 pts  — Autopsy case created, data source added, EXIF artifacts in DB
  10 pts  — CSV Formatting: File exists, is recent, has correct pipe-delimited header
  25 pts  — Coverage: The CSV report includes at least 80% of GT JPEGs with EXIF dates
  30 pts  — Delta Accuracy: The DELTA_DAYS values in the CSV are mathematically correct (within ±1 day)
  10 pts  — Summary Content: temporal_summary.txt exists and contains required keys
  10 pts  — Summary Consistency: Aggregate metrics match the parsed CSV data
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_metadata_filesystem_timestamp_divergence(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/temporal_divergence_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/temporal_divergence_gt.json")

    # ── Pull Result JSON from VM ──────────────────────────────────────────────
    result = {}
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
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

    # ── Pull Ground Truth from VM ──────────────────────────────────────────────
    gt_files = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt_files = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass  # Will handle empty GT gracefully

    # ── Criterion 1: Case Creation & Ingest (15 pts) ──────────────────────────
    db_ok = result.get("case_db_found")
    ds_ok = result.get("data_source_added")
    exif_ok = result.get("db_exif_artifacts_found") or result.get("ingest_completed")
    
    if db_ok and ds_ok and exif_ok:
        score += 15
        feedback_parts.append("PASS Autopsy case populated (+15)")
    elif db_ok and ds_ok:
        score += 10
        feedback_parts.append("PARTIAL Autopsy case created but ingest may be incomplete (+10)")
    else:
        feedback_parts.append("FAIL Autopsy case setup incomplete")

    # ── Parse CSV Content ─────────────────────────────────────────────────────
    csv_content = result.get("csv_content", "").replace("\\n", "\n")
    lines = [l.strip() for l in csv_content.splitlines() if l.strip()]
    
    csv_data = {}
    csv_format_ok = False
    
    if len(lines) > 0:
        header = lines[0]
        if "FILENAME|" in header.upper() and "|DELTA_DAYS" in header.upper():
            csv_format_ok = True
            
        for line in lines[1:]:
            parts = line.split('|')
            if len(parts) >= 4:
                filename = parts[0].strip().lower()
                # Clean filename if it includes paths
                filename = filename.split('/')[-1].split('\\')[-1]
                try:
                    # Extract numeric digits from DELTA_DAYS
                    delta_str = re.sub(r'[^\d.-]', '', parts[3])
                    delta_days = float(delta_str)
                    csv_data[filename] = delta_days
                except ValueError:
                    continue

    # ── Criterion 2: CSV Formatting (10 pts) ──────────────────────────────────
    start_time = result.get("start_time", 0)
    csv_mtime = result.get("csv_mtime", 0)
    
    if result.get("csv_file_exists"):
        is_recent = (start_time == 0 or csv_mtime >= start_time)
        if csv_format_ok and is_recent:
            score += 10
            feedback_parts.append("PASS CSV properly formatted and recent (+10)")
        elif csv_format_ok:
            score += 5
            feedback_parts.append("PARTIAL CSV formatted but pre-dates task start (+5)")
        elif len(csv_data) > 0:
            score += 5
            feedback_parts.append("PARTIAL CSV has data but bad header/delimiters (+5)")
        else:
            feedback_parts.append("FAIL CSV exists but format is invalid")
    else:
        feedback_parts.append("FAIL CSV report missing")

    # ── Criterion 3 & 4: Coverage (25 pts) and Accuracy (30 pts) ──────────────
    if not gt_files:
        # Fallback if Python GT computation failed on host
        if len(csv_data) > 0:
            score += 30  # Give partial credit since GT failed but agent did work
            feedback_parts.append(f"PASS Agent reported {len(csv_data)} files (GT unavailable) (+30)")
    else:
        matched_files = 0
        accurate_deltas = 0
        
        for gt_name, gt_info in gt_files.items():
            expected_delta = gt_info["delta_days"]
            # Try to find the file in the agent's CSV
            # exact match or substring match
            agent_delta = None
            if gt_name in csv_data:
                agent_delta = csv_data[gt_name]
            else:
                for a_name, a_delta in csv_data.items():
                    if gt_name in a_name or a_name in gt_name:
                        agent_delta = a_delta
                        break
            
            if agent_delta is not None:
                matched_files += 1
                if abs(agent_delta - expected_delta) <= 1.0:
                    accurate_deltas += 1

        coverage_ratio = matched_files / len(gt_files)
        accuracy_ratio = accurate_deltas / matched_files if matched_files > 0 else 0
        
        # Coverage Score
        if coverage_ratio >= 0.8:
            score += 25
            feedback_parts.append(f"PASS Coverage {coverage_ratio*100:.0f}% (+25)")
        elif coverage_ratio >= 0.4:
            score += 15
            feedback_parts.append(f"PARTIAL Coverage {coverage_ratio*100:.0f}% (+15)")
        else:
            feedback_parts.append(f"FAIL Low Coverage {coverage_ratio*100:.0f}%")

        # Accuracy Score (Contingent on actually doing the math)
        if accuracy_ratio >= 0.8 and matched_files > 0:
            score += 30
            feedback_parts.append(f"PASS Delta Accuracy {accuracy_ratio*100:.0f}% (+30)")
        elif accuracy_ratio >= 0.4 and matched_files > 0:
            score += 15
            feedback_parts.append(f"PARTIAL Delta Accuracy {accuracy_ratio*100:.0f}% (+15)")
        else:
            feedback_parts.append(f"FAIL Delta calculations inaccurate or missing")

    # ── Criterion 5 & 6: Summary Content (10 pts) & Consistency (10 pts) ──────
    summary_content = result.get("summary_content", "")
    
    if result.get("summary_file_exists") and summary_content.strip():
        # Check for keys
        has_total = "TOTAL_JPEGS_WITH_EXIF" in summary_content
        has_max = "MAX_DIVERGENCE_DAYS" in summary_content
        has_24h = "FILES_EXCEEDING_24H" in summary_content
        has_conc = "CONCLUSION" in summary_content
        
        if has_total and has_max and has_24h and has_conc:
            score += 10
            feedback_parts.append("PASS Summary report has all required sections (+10)")
        elif has_total or has_conc:
            score += 5
            feedback_parts.append("PARTIAL Summary report missing some sections (+5)")
        else:
            feedback_parts.append("FAIL Summary lacks required structure")
            
        # Consistency Check
        try:
            m_total = re.search(r"TOTAL_JPEGS_WITH_EXIF:\s*(\d+)", summary_content)
            m_max = re.search(r"MAX_DIVERGENCE_DAYS:\s*([\d.]+)", summary_content)
            
            if m_total and m_max and len(csv_data) > 0:
                reported_total = int(m_total.group(1))
                reported_max = float(m_max.group(1))
                
                csv_max = max(csv_data.values()) if csv_data else 0
                
                if reported_total == len(csv_data) and abs(reported_max - csv_max) <= 1.0:
                    score += 10
                    feedback_parts.append("PASS Summary metrics match CSV data (+10)")
                else:
                    feedback_parts.append(f"FAIL Summary metrics (Total:{reported_total}, Max:{reported_max}) do not match CSV (Total:{len(csv_data)}, Max:{csv_max})")
        except Exception:
            feedback_parts.append("FAIL Could not parse metrics for consistency check")
    else:
        feedback_parts.append("FAIL Summary report missing")

    # ── Final Pass/Fail ───────────────────────────────────────────────────────
    passed = score >= 60 and (len(csv_data) > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }