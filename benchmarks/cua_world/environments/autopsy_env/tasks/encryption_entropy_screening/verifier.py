#!/usr/bin/env python3
"""
Verifier for encryption_entropy_screening task.

Scoring (100 pts total, pass threshold = 60):
  10 pts - Case DB found
  10 pts - Data source added
  15 pts - Ingest completed (evidence indexed)
  10 pts - Entropy CSV exists, recent, correct format
  15 pts - Entropy values within tolerance of GT (±0.5 bpb) for >= 60% of files
  10 pts - File coverage >= 50% of GT files
   5 pts - Classification labels consistent with reported entropy
  15 pts - Screening report has all 7 required sections
   5 pts - TOTAL_FILES_ANALYZED within ±2 of GT
   5 pts - Conclusion section is non-empty and coherent
"""

import json
import os
import re
import tempfile

def verify_encryption_entropy_screening(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/encryption_screening_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/encryption_screening_gt.json")

    # 1. Pull result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export script did not run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # 2. Pull GT JSON
    gt = {"files": [], "total_files": 0, "class_counts": {}}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_files = {f["name"].lower(): f for f in gt.get("files", [])}
    gt_total = gt.get("total_files", 0)

    # Criteria 1: Case DB
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # Criteria 2: Data Source
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not added")

    # Criteria 3: Ingest Completed
    if result.get("ingest_completed"):
        score += 15
        feedback_parts.append("PASS Ingest completed (+15)")
    else:
        feedback_parts.append("FAIL Ingest did not complete")

    # Process CSV Data
    start_time = result.get("start_time", 0)
    csv_exists = result.get("csv_file_exists", False)
    csv_mtime = result.get("csv_mtime", 0)
    csv_content = result.get("csv_content", "").replace("\\n", "\n")
    
    csv_is_recent = start_time == 0 or csv_mtime >= start_time
    parsed_rows = []
    
    if csv_exists and csv_is_recent:
        lines = [l.strip() for l in csv_content.splitlines() if l.strip()]
        if len(lines) > 0 and "|" in lines[0] and "FILENAME" in lines[0].upper():
            score += 10
            feedback_parts.append("PASS CSV exists with valid header (+10)")
            for line in lines[1:]:
                parts = line.split("|")
                if len(parts) >= 5:
                    parsed_rows.append({
                        "filename": parts[0].strip().lower(),
                        "entropy": parts[3].strip(),
                        "classification": parts[4].strip().upper()
                    })
        else:
            feedback_parts.append("FAIL CSV missing header or not pipe-delimited")
    else:
        feedback_parts.append("FAIL CSV not found or stale")

    # Evaluate Entropy and Coverage
    if gt_total > 0 and parsed_rows:
        matched = 0
        accurate_entropy = 0
        consistent_class = 0

        for row in parsed_rows:
            if row["filename"] in gt_files:
                matched += 1
                gt_val = gt_files[row["filename"]]["entropy"]
                try:
                    agent_val = float(row["entropy"])
                    if abs(agent_val - gt_val) <= 0.5:
                        accurate_entropy += 1
                    
                    # Check classification logic
                    expected_class = "SUSPICIOUS"
                    if agent_val < 4.0: expected_class = "LOW"
                    elif agent_val < 6.5: expected_class = "MEDIUM"
                    elif agent_val < 7.5: expected_class = "HIGH"

                    if row["classification"] == expected_class:
                        consistent_class += 1
                except ValueError:
                    pass

        coverage_pct = matched / gt_total
        accuracy_pct = accurate_entropy / matched if matched > 0 else 0
        class_pct = consistent_class / matched if matched > 0 else 0

        # Coverage (10 pts)
        if coverage_pct >= 0.5:
            score += 10
            feedback_parts.append(f"PASS File coverage {coverage_pct*100:.1f}% >= 50% (+10)")
        elif coverage_pct > 0:
            score += 5
            feedback_parts.append(f"PARTIAL File coverage {coverage_pct*100:.1f}% < 50% (+5)")
        else:
            feedback_parts.append("FAIL No valid files mapped to GT in CSV")

        # Accuracy (15 pts)
        if accuracy_pct >= 0.6:
            score += 15
            feedback_parts.append(f"PASS Entropy accuracy {accuracy_pct*100:.1f}% >= 60% (+15)")
        elif accuracy_pct > 0:
            score += 7
            feedback_parts.append(f"PARTIAL Entropy accuracy {accuracy_pct*100:.1f}% < 60% (+7)")
        else:
            feedback_parts.append("FAIL Entropy values inaccurate")

        # Classification (5 pts)
        if class_pct >= 0.9:
            score += 5
            feedback_parts.append("PASS Classifications match reported entropy (+5)")
        else:
            feedback_parts.append(f"FAIL Classifications inconsistent (only {class_pct*100:.1f}%)")
    else:
        feedback_parts.append("FAIL Could not evaluate CSV against ground truth")

    # Evaluate Report
    report_exists = result.get("report_file_exists", False)
    report_mtime = result.get("report_mtime", 0)
    report_content = result.get("report_content", "").replace("\\n", "\n")
    report_is_recent = start_time == 0 or report_mtime >= start_time

    if report_exists and report_is_recent:
        req_sections = [
            "CASE_NUMBER", "IMAGE_ANALYZED", "TOTAL_FILES_ANALYZED",
            "ENCRYPTION_MODULE_HITS", "ENTROPY_CLASSIFICATION_SUMMARY",
            "HIGH_ENTROPY_FILES", "CONCLUSION"
        ]
        missing = [s for s in req_sections if s not in report_content]
        
        if not missing:
            score += 15
            feedback_parts.append("PASS Report has all 7 sections (+15)")
        else:
            pts = int(15 * (len(req_sections) - len(missing)) / len(req_sections))
            score += pts
            feedback_parts.append(f"PARTIAL Report missing {len(missing)} sections (+{pts})")

        # Check TOTAL_FILES_ANALYZED
        total_match = re.search(r"TOTAL_FILES_ANALYZED:\s*(\d+)", report_content)
        if total_match:
            try:
                reported_total = int(total_match.group(1))
                if gt_total > 0 and abs(reported_total - gt_total) <= 2:
                    score += 5
                    feedback_parts.append("PASS TOTAL_FILES_ANALYZED accurate (+5)")
                elif abs(reported_total - len(parsed_rows)) <= 1:
                    score += 3
                    feedback_parts.append("PARTIAL TOTAL matches CSV rows but not GT (+3)")
                else:
                    feedback_parts.append("FAIL TOTAL_FILES_ANALYZED inaccurate")
            except ValueError:
                feedback_parts.append("FAIL TOTAL_FILES_ANALYZED not a number")
        else:
            feedback_parts.append("FAIL TOTAL_FILES_ANALYZED value missing")

        # Check CONCLUSION
        concl_idx = report_content.find("CONCLUSION:")
        if concl_idx != -1:
            concl_text = report_content[concl_idx + len("CONCLUSION:"):].strip()
            if len(concl_text) > 10:
                score += 5
                feedback_parts.append("PASS Conclusion section is populated (+5)")
            else:
                feedback_parts.append("FAIL Conclusion section is empty")
        else:
            feedback_parts.append("FAIL Conclusion section not found")
            
    else:
        feedback_parts.append("FAIL Screening report not found or stale")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }