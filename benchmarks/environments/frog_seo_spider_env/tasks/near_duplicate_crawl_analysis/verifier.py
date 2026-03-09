#!/usr/bin/env python3
"""
Verifier for Near Duplicate Crawl Analysis task.

SCORING CRITERIA (100 pts total):
1. CSV Export Exists (20 pts): A CSV file was created in the export directory.
2. Correct Export Type (40 pts): CSV contains "Similarity" column.
   - This proves the agent exported the "Near Duplicates" tab, not just internal URLs.
   - This implicitly proves "Enable Near Duplicates" was checked (otherwise tab is empty/unavailable).
3. Valid Data Content (30 pts):
   - CSV contains rows (>0) with "crawler-test.com" URLs.
   - This proves the "Crawl Analysis" post-process was actually run.
   - Without running analysis, the Near Duplicates tab remains empty even if enabled.
4. Written Report (10 pts): Text file exists with content.

Pass Threshold: 70 pts (Must have valid CSV with Similarity column and data).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_near_duplicate_crawl_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Check CSV Existence (20 pts)
    csv_found = result.get("csv_found", False)
    if csv_found:
        score += 20
        feedback_parts.append("Export CSV found (20/20)")
    else:
        feedback_parts.append("No export CSV found (0/20)")

    # 2. Check Correct Export Type (40 pts) - The "Similarity" column check
    has_similarity = result.get("has_similarity_column", False)
    if csv_found:
        if has_similarity:
            score += 40
            feedback_parts.append("Correct report type: 'Similarity' column found (40/40)")
        else:
            feedback_parts.append("Wrong report type: 'Similarity' column missing (0/40). Did you export the 'Near Duplicates' tab?")
    
    # 3. Check Data Content (30 pts) - Proves Analysis ran
    has_data = result.get("has_data_rows", False)
    domain_found = result.get("target_domain_found", False)
    row_count = result.get("row_count", 0)

    if csv_found and has_similarity:
        if has_data and domain_found:
            score += 30
            feedback_parts.append(f"Valid data: {row_count} rows from target domain (30/30)")
        elif has_data and not domain_found:
            score += 10
            feedback_parts.append(f"Data found but wrong domain (10/30)")
        else:
            feedback_parts.append("Report is empty (0/30). Did you run 'Crawl Analysis' after crawling?")
    elif csv_found:
        feedback_parts.append("Data check skipped due to wrong report type")

    # 4. Check Written Report (10 pts)
    report_found = result.get("report_found", False)
    report_len = result.get("report_length", 0)
    if report_found and report_len > 10:
        score += 10
        feedback_parts.append("Summary report created (10/10)")
    else:
        feedback_parts.append("Summary report missing or empty (0/10)")

    # Final Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }