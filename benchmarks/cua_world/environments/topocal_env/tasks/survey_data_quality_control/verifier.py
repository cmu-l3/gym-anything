#!/usr/bin/env python3
"""
Verifier for survey_data_quality_control task.

Scoring (total 100 pts, pass threshold 60):
  30 pts — cleaned_survey.csv exists AND was created after task start
  25 pts — cleaned CSV has fewer rows than the raw 150 (agent deleted outliers)
  25 pts — QC_Report.txt exists, is new, and has substantive content
  20 pts — QC report mentions specific outlier point numbers (51-56 or nearby)
"""

import json
import re
import os
import tempfile
from datetime import datetime, timezone

OUTLIER_IDS = {51, 52, 53, 54, 55, 56}
RAW_COUNT = 150  # total points in raw_survey.csv


def _parse_dt(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.strip().replace("Z", "+00:00"))
    except Exception:
        return None


def verify_survey_data_quality_control(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result_path = (
        task_info.get("metadata", {}).get("result_file")
        or "C:\\Users\\Docker\\survey_data_quality_control_result.json"
    )

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        env_info["copy_from_env"](result_path, tmp.name)
    except Exception as exc:
        return {"passed": False, "score": 0,
                "feedback": f"Could not retrieve result file: {exc}"}

    try:
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as exc:
        return {"passed": False, "score": 0,
                "feedback": f"Result JSON invalid: {exc}"}
    finally:
        os.unlink(tmp.name)

    start_dt = _parse_dt(result.get("start_time", ""))

    def is_new(mod_time_str):
        mod_dt = _parse_dt(mod_time_str)
        if not mod_dt or not start_dt:
            return False
        if mod_dt.tzinfo is None:
            mod_dt = mod_dt.replace(tzinfo=timezone.utc)
        sd = start_dt.replace(tzinfo=timezone.utc) if start_dt.tzinfo is None else start_dt
        return mod_dt > sd

    # ── Criterion 1: cleaned_survey.csv exists and is new (30 pts) ──
    csv_exists = bool(result.get("cleaned_csv_exists"))
    csv_new    = csv_exists and is_new(result.get("cleaned_csv_mod", ""))
    csv_rows   = int(result.get("cleaned_csv_rows") or 0)

    if csv_exists and csv_new:
        score += 30
        feedback_parts.append("PASS(30): cleaned_survey.csv exists and is newer than task start")
    elif csv_exists:
        score += 12
        feedback_parts.append("PARTIAL(12): cleaned_survey.csv exists but may predate task start")
    else:
        feedback_parts.append("FAIL(0): cleaned_survey.csv not found")

    # ── Criterion 2: row count reduced (outliers removed) (25 pts) ──
    # Raw had 150 rows. If agent removed all 6 outliers: 144 rows expected.
    # Accept 130-149 as partial credit, 144 ± 3 for full credit.
    if csv_rows > 0:
        if 141 <= csv_rows <= 149:
            score += 25
            feedback_parts.append(
                f"PASS(25): cleaned CSV has {csv_rows} rows (outliers removed, near expected 144)"
            )
        elif 130 <= csv_rows <= 150:
            score += 12
            feedback_parts.append(
                f"PARTIAL(12): cleaned CSV has {csv_rows} rows (expected ~144 after removing 6 outliers)"
            )
        elif csv_rows == RAW_COUNT:
            feedback_parts.append(
                f"FAIL(0): cleaned CSV has same count as raw ({csv_rows}) — no outliers removed"
            )
        else:
            score += 5
            feedback_parts.append(
                f"PARTIAL(5): cleaned CSV has {csv_rows} rows (unexpected count; raw was {RAW_COUNT})"
            )
    else:
        feedback_parts.append("FAIL(0): could not determine cleaned CSV row count")

    # ── Criterion 3: QC_Report.txt exists, new, has content (25 pts) ──
    rep_exists = bool(result.get("report_exists"))
    rep_new    = rep_exists and is_new(result.get("report_mod_time", ""))
    rep_lines  = int(result.get("report_lines") or 0)

    if rep_exists and rep_new and rep_lines >= 5:
        score += 25
        feedback_parts.append(f"PASS(25): QC_Report.txt exists, is new, has {rep_lines} lines")
    elif rep_exists and rep_new:
        score += 15
        feedback_parts.append(f"PARTIAL(15): QC_Report.txt exists and is new but only {rep_lines} lines")
    elif rep_exists:
        score += 8
        feedback_parts.append("PARTIAL(8): QC_Report.txt exists but may predate task start")
    else:
        feedback_parts.append("FAIL(0): QC_Report.txt not found")

    # ── Criterion 4: QC report mentions outlier point numbers (20 pts) ──
    raw_content = result.get("report_content", "") or ""
    content = raw_content.replace("\\n", "\n").replace("\\t", "\t")

    # Find all numbers mentioned in the report
    numbers_in_report = set(int(m) for m in re.findall(r"\b(\d+)\b", content))
    # How many outlier IDs are mentioned?
    mentioned_outliers = OUTLIER_IDS & numbers_in_report

    if len(mentioned_outliers) >= 4:
        score += 20
        feedback_parts.append(
            f"PASS(20): QC report mentions {len(mentioned_outliers)} outlier point IDs "
            f"({sorted(mentioned_outliers)})"
        )
    elif len(mentioned_outliers) >= 2:
        score += 10
        feedback_parts.append(
            f"PARTIAL(10): QC report mentions {len(mentioned_outliers)} outlier IDs "
            f"({sorted(mentioned_outliers)})"
        )
    elif rep_exists and re.search(r"(?i)outl|anomal|elimin|remov|borr", content):
        score += 5
        feedback_parts.append("PARTIAL(5): report mentions removal but no specific outlier IDs found")
    else:
        feedback_parts.append(
            f"FAIL(0): QC report does not mention outlier point numbers {sorted(OUTLIER_IDS)}"
        )

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
