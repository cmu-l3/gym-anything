#!/usr/bin/env python3
"""
Verifier for unallocated_carving_analysis task.

Scoring Rubric (100 pts total, Pass Threshold = 60):
  10 pts - Autopsy case created and DB found
  10 pts - Disk image data source added
  15 pts - PhotoRec carver ran successfully (Carved files exist in Autopsy DB)
  5 pts  - Ingest completed and hashes generated
  10 pts - Carved catalog exists, is recent, and uses pipe-delimited format
  10 pts - Allocated catalog exists, is recent, and uses pipe-delimited format
  10 pts - Carved file count in report matches DB count (tolerance ±2)
  5 pts  - Allocated file count in report matches DB count (tolerance ±2)
  10 pts - CARVED_UNIQUE logic holds and exists in report
  5 pts  - CARVED_DUPLICATES logic holds (Unique + Dupes == Total Carved)
  5 pts  - Analysis report has all required sections
  5 pts  - Forensic assessment conclusion present
"""

import json
import os
import re
import tempfile


def extract_report_value(content, key):
    """Extracts a numeric value from the report given a key."""
    match = re.search(rf"{key}:\s*(\d+)", content, re.IGNORECASE)
    if match:
        return int(match.group(1))
    return None


def verify_unallocated_carving_analysis(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/carving_analysis_result.json")

    # ── Pull result JSON ──────────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — task was not attempted."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Criterion 1: Case DB found (10 pts) ───────────────────────────────────
    if result.get("case_db_found") and result.get("case_name_matches"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Data source added (10 pts) ───────────────────────────────
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not found in DB")

    # ── Criterion 3: PhotoRec Ran / Carved files in DB (15 pts) ───────────────
    db_carved = result.get("db_carved_count", 0)
    db_allocated = result.get("db_allocated_count", 0)
    
    if db_carved > 0:
        score += 15
        feedback_parts.append(f"PASS {db_carved} carved files found in Autopsy DB (+15)")
    else:
        feedback_parts.append("FAIL No carved files found in DB. PhotoRec may not have run.")

    # ── Criterion 4: Ingest & Hashes (5 pts) ──────────────────────────────────
    if result.get("ingest_completed") and result.get("db_has_hashes"):
        score += 5
        feedback_parts.append("PASS Ingest completed with hashes (+5)")
    else:
        feedback_parts.append("FAIL Ingest did not complete or hashes not generated")

    # ── Verify Catalogs ───────────────────────────────────────────────────────
    start_time = result.get("start_time", 0)
    
    def check_catalog(name_prefix, exists_key, mtime_key, content_key):
        if result.get(exists_key):
            mtime = result.get(mtime_key, 0)
            content = result.get(content_key, "").strip()
            pipes = content.count("|")
            lines = len([l for l in content.splitlines() if l.strip()])
            is_recent = (start_time == 0 or mtime >= start_time)
            
            if is_recent and pipes >= lines and lines > 0:
                return True, f"PASS {name_prefix} catalog format correct (+10)"
            elif is_recent and lines > 0:
                return 0.5, f"PARTIAL {name_prefix} catalog exists but format may be incorrect (+5)"
            else:
                return 0, f"FAIL {name_prefix} catalog empty or stale"
        return 0, f"FAIL {name_prefix} catalog missing"

    # Carved Catalog (10 pts)
    status, msg = check_catalog("Carved", "carved_catalog_exists", "carved_catalog_mtime", "carved_catalog_content")
    if status is True: score += 10
    elif status == 0.5: score += 5
    feedback_parts.append(msg)

    # Allocated Catalog (10 pts)
    status, msg = check_catalog("Allocated", "allocated_catalog_exists", "allocated_catalog_mtime", "allocated_catalog_content")
    if status is True: score += 10
    elif status == 0.5: score += 5
    feedback_parts.append(msg)

    # ── Verify Analysis Report & Logic ─────────────────────────────────────────
    if result.get("analysis_report_exists"):
        report_mtime = result.get("analysis_report_mtime", 0)
        content = result.get("analysis_report_content", "")
        
        if start_time == 0 or report_mtime >= start_time:
            req_sections = ["CASE_NAME", "CASE_NUMBER", "DATA_SOURCE", "CARVING_METHOD"]
            if all(sec in content.upper() for sec in req_sections):
                score += 5
                feedback_parts.append("PASS Analysis report has required headers (+5)")
            else:
                feedback_parts.append("FAIL Analysis report missing required headers")

            if "FORENSIC_ASSESSMENT:" in content.upper() and len(content.split("FORENSIC_ASSESSMENT:")[-1].strip()) > 10:
                score += 5
                feedback_parts.append("PASS Forensic assessment conclusion present (+5)")
            else:
                feedback_parts.append("FAIL Forensic assessment conclusion missing or too short")

            # Validate Counts vs DB
            rep_carved = extract_report_value(content, "TOTAL_CARVED_FILES")
            rep_allocated = extract_report_value(content, "TOTAL_ALLOCATED_FILES")
            rep_dupes = extract_report_value(content, "CARVED_DUPLICATES")
            rep_unique = extract_report_value(content, "CARVED_UNIQUE")

            if rep_carved is not None and db_carved > 0 and abs(rep_carved - db_carved) <= 2:
                score += 10
                feedback_parts.append(f"PASS TOTAL_CARVED_FILES ({rep_carved}) matches DB (+10)")
            else:
                feedback_parts.append(f"FAIL TOTAL_CARVED_FILES mismatch (Report: {rep_carved}, DB: {db_carved})")

            if rep_allocated is not None and db_allocated > 0 and abs(rep_allocated - db_allocated) <= 5:
                score += 5
                feedback_parts.append(f"PASS TOTAL_ALLOCATED_FILES ({rep_allocated}) matches DB (+5)")
            else:
                feedback_parts.append(f"FAIL TOTAL_ALLOCATED_FILES mismatch (Report: {rep_allocated}, DB: {db_allocated})")

            # Logical Math check (Unique + Dupes == Total)
            if rep_unique is not None:
                score += 10
                feedback_parts.append("PASS CARVED_UNIQUE found (+10)")
            else:
                feedback_parts.append("FAIL CARVED_UNIQUE missing")

            if rep_unique is not None and rep_dupes is not None and rep_carved is not None:
                if rep_unique + rep_dupes == rep_carved:
                    score += 5
                    feedback_parts.append("PASS CARVED_UNIQUE + CARVED_DUPLICATES equals TOTAL_CARVED_FILES (+5)")
                else:
                    feedback_parts.append(f"FAIL Mathematical error: Unique({rep_unique}) + Dupes({rep_dupes}) != Total({rep_carved})")
            else:
                feedback_parts.append("FAIL Missing values for logic check")

        else:
            feedback_parts.append("FAIL Analysis report is stale (created before task start)")
    else:
        feedback_parts.append("FAIL Analysis report missing")

    passed = score >= 60 and db_carved > 0
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }