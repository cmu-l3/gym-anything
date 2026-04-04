"""
Verifier for partitioned_archival_strategy task.

Scoring breakdown (100 pts total):
- EMPLOYEE_HISTORY_ARCHIVE table created (10 pts)
- Table is range-partitioned (10 pts)
- Has 4 partitions (10 pts)  / 3 partitions (5 pts partial)
- Archive contains all JOB_HISTORY rows (15 pts) / partial (8 pts)
- Bitmap index on JOB_ID column (10 pts)
- Bitmap index on DEPARTMENT_ID column (10 pts)
- MV_DEPT_TURNOVER materialized view exists (10 pts)
- MV is VALID/FRESH and has rows (5 pts)
- archive_analysis.txt file exists on Desktop (10 pts)
- File references partition names or row counts (10 pts)

Pass threshold: 55 pts
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_partitioned_archival_strategy(traj, env_info, task_info):
    """
    Verifies the partitioned archival strategy task.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "score": 0.0,
            "passed": False,
            "feedback": "copy_from_env not available"
        }

    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "partitioned_archival_strategy_result.json")
        try:
            copy_from_env("/tmp/partitioned_archival_strategy_result.json", result_path)
        except Exception as e:
            return {
                "score": 0.0,
                "passed": False,
                "feedback": f"Could not retrieve result file: {e}"
            }

        if not os.path.exists(result_path):
            return {"score": 0.0, "passed": False, "feedback": "Result file not found after copy."}

        try:
            with open(result_path, "r") as f:
                result = json.load(f)
        except json.JSONDecodeError as e:
            return {"score": 0.0, "passed": False, "feedback": f"Result JSON malformed: {e}"}

    score = 0
    feedback_parts = []

    # --- Archive table exists (10 pts) ---
    if result.get("archive_table_exists"):
        score += 10
        feedback_parts.append("EMPLOYEE_HISTORY_ARCHIVE: table created (+10)")
    else:
        feedback_parts.append("EMPLOYEE_HISTORY_ARCHIVE: NOT FOUND — 0 pts for all table checks")
        return {
            "score": 0.0,
            "passed": False,
            "feedback": " | ".join(feedback_parts)
        }

    # --- Table is partitioned (10 pts) ---
    if result.get("archive_table_partitioned"):
        score += 10
        feedback_parts.append("Table is range-partitioned (+10)")
    else:
        feedback_parts.append("Table exists but is NOT partitioned (0 pts)")

    # --- Partition count (10 pts for 4, 5 pts for 3) ---
    partition_count = result.get("archive_partition_count", 0)
    if partition_count >= 4:
        score += 10
        feedback_parts.append(f"Partition count: {partition_count} (>=4 required) (+10)")
    elif partition_count == 3:
        score += 5
        feedback_parts.append(f"Partition count: 3 (4 required) (+5 partial)")
    elif partition_count > 0:
        score += 2
        feedback_parts.append(f"Partition count: {partition_count} (too few) (+2 partial)")
    else:
        feedback_parts.append("No partitions found on archive table (0 pts)")

    # --- Row migration (15 pts for all rows, 8 pts for partial) ---
    baseline = result.get("job_history_baseline", 10)
    archive_rows = result.get("archive_total_rows", 0)
    if archive_rows >= baseline and baseline > 0:
        score += 15
        feedback_parts.append(f"Row migration: {archive_rows} rows (all {baseline} JOB_HISTORY rows migrated) (+15)")
    elif archive_rows > 0:
        pct = int(archive_rows / max(baseline, 1) * 100)
        score += 8
        feedback_parts.append(f"Row migration: {archive_rows}/{baseline} rows ({pct}%) (+8 partial)")
    else:
        feedback_parts.append(f"Row migration: archive is empty (0 pts)")

    # --- Bitmap indexes (10 + 10 pts) ---
    bitmap_cols = {idx["column"].upper() for idx in result.get("bitmap_indexes", [])}
    if "JOB_ID" in bitmap_cols:
        score += 10
        feedback_parts.append("Bitmap index on JOB_ID: found (+10)")
    else:
        feedback_parts.append("Bitmap index on JOB_ID: NOT found (0 pts)")

    if "DEPARTMENT_ID" in bitmap_cols:
        score += 10
        feedback_parts.append("Bitmap index on DEPARTMENT_ID: found (+10)")
    else:
        feedback_parts.append("Bitmap index on DEPARTMENT_ID: NOT found (0 pts)")

    # --- Materialized view (10 + 5 pts) ---
    if result.get("mv_dept_turnover_exists"):
        score += 10
        mv_status = result.get("mv_dept_turnover_status", "UNKNOWN")
        feedback_parts.append(f"MV_DEPT_TURNOVER: exists (status={mv_status}) (+10)")

        mv_rows = result.get("mv_dept_turnover_rows", 0)
        if mv_rows > 0 and mv_status in ("VALID", "NEEDS COMPILE") :
            score += 5
            feedback_parts.append(f"MV_DEPT_TURNOVER: {mv_rows} rows, queryable (+5)")
        elif mv_rows > 0:
            score += 3
            feedback_parts.append(f"MV_DEPT_TURNOVER: {mv_rows} rows but status={mv_status} (+3 partial)")
        else:
            feedback_parts.append("MV_DEPT_TURNOVER: 0 rows or not queryable (0 pts)")
    else:
        feedback_parts.append("MV_DEPT_TURNOVER: NOT found (0 pts)")

    # --- archive_analysis.txt file (10 + 10 pts) ---
    if result.get("archive_analysis_file_exists"):
        file_size = result.get("archive_analysis_file_size", 0)
        score += 10
        feedback_parts.append(f"archive_analysis.txt: exists ({file_size} bytes) (+10)")

        preview = result.get("archive_analysis_preview", "").upper()
        # Check file references partition names or counts
        has_partition_data = (
            "PARTITION" in preview or
            re.search(r"\d{3,}", preview) or
            "P_" in preview or
            "ROWS" in preview or
            "COUNT" in preview
        )
        if has_partition_data:
            score += 10
            feedback_parts.append("archive_analysis.txt: contains partition/count data (+10)")
        else:
            feedback_parts.append("archive_analysis.txt: content does not mention partitions or counts (0 pts)")
    else:
        feedback_parts.append("archive_analysis.txt: NOT found at /home/ga/Desktop/ (0 pts)")

    max_score = 100
    normalized = round(score / max_score, 4)
    passed = score >= 55

    return {
        "score": normalized,
        "passed": passed,
        "raw_score": score,
        "max_score": max_score,
        "feedback": " | ".join(feedback_parts)
    }
