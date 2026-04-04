#!/usr/bin/env python3
"""Verifier for longest_case_phase_timeline task.

Scoring (100 points total):
  Criterion 1 (25 pts): CSV exists with cardiovascular tracks unique to case 0002
                        (HR, NIBP, SpO2, VENT columns in header)
  Criterion 2 (20 pts): CSV represents an intraoperative segment, not the full recording
                        (row count substantially less than ~15,740 full-case rows)
  Criterion 3 (20 pts): Phase analysis report exists with substantial content (>=400 bytes)
  Criterion 4 (20 pts): Report identifies case 0002 as the longest / target case
  Criterion 5 (15 pts): Report contains quantitative phase-duration data (numbers + time units)

Output gate: score=0 if neither CSV nor report exists.
Pass threshold: 60 points

Ground truth:
  Longest case is 0002.vital (~4h 22min = ~15,740 seconds).
  Its unique tracks: HR, ST_II, ST_V5, NIBP_SYS, NIBP_DIA, NIBP_MEAN, SpO2,
                     VENT_TV, VENT_PEEP, VENT_RR (no ART, no SEVO).
  A full export would yield ~15,740 rows; intraop segment should be
  roughly 50–90% of that (generous bounds for timing uncertainty).
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD          = 60
CSV_MIN_SIZE            = 100      # bytes
REPORT_MIN_SIZE         = 400      # bytes

# Tracks unique to case 0002 (not present in 0001 or 0003)
CASE_0002_UNIQUE_TRACKS = [
    "HR", "NIBP", "SpO2", "SPO2", "VENT", "ST_II", "ST_V5",
]

# Full case 0002 row count approximation (duration in seconds at 1 Hz export)
FULL_CASE_ROWS_APPROX = 15740
# Intraop segment should be between 40% and 95% of full case
INTRAOP_FRAC_MIN      = 0.40
INTRAOP_FRAC_MAX      = 0.95

# Phase-related keywords for report check
PHASE_TERMS = [
    "pre-operative", "preoperative", "pre operative",
    "intraoperative", "intra-operative",
    "post-operative", "postoperative", "post operative",
    "emergence", "induction", "phase", "period",
]

# Quantitative pattern: a number followed by time units or percentage
QUANT_PATTERN = re.compile(
    r"\b\d+\.?\d*\s*(%|percent|min|minute|hour|second|sec|hr)\b",
    re.IGNORECASE,
)


def _safe_copy(copy_from_env, remote_path, local_path):
    try:
        copy_from_env(remote_path, local_path)
        return os.path.exists(local_path) and os.path.getsize(local_path) > 0
    except Exception as exc:
        logger.warning("copy_from_env(%s) failed: %s", remote_path, exc)
        return False


def verify_longest_case_phase_timeline(traj, env_info, task_info):
    """Multi-criterion verifier for longest_case_phase_timeline."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # ------------------------------------------------------------------
    # Supplemental: export JSON
    # ------------------------------------------------------------------
    result_json = {}
    tmp_json = tempfile.mktemp(suffix=".json")
    try:
        if _safe_copy(copy_from_env, r"C:\Users\Docker\task_result_phase_timeline.json", tmp_json):
            with open(tmp_json, "r", encoding="utf-8-sig", errors="replace") as f:
                result_json = json.load(f)
    except Exception as exc:
        logger.warning("Export JSON load failed: %s", exc)
    finally:
        try:
            os.unlink(tmp_json)
        except OSError:
            pass

    # ------------------------------------------------------------------
    # Independently copy CSV
    # ------------------------------------------------------------------
    csv_size   = 0
    csv_exists = False
    csv_header = ""
    csv_rows   = 0
    tmp_csv    = tempfile.mktemp(suffix=".csv")
    try:
        if _safe_copy(copy_from_env, r"C:\Users\Docker\Desktop\longest_case_intraop.csv", tmp_csv):
            csv_size   = os.path.getsize(tmp_csv)
            csv_exists = True
            with open(tmp_csv, "r", encoding="utf-8", errors="replace") as f:
                csv_header = f.readline().strip()
            # Count rows (subtract 1 for header)
            with open(tmp_csv, "r", encoding="utf-8", errors="replace") as f:
                csv_rows = sum(1 for _ in f) - 1
    except Exception as exc:
        logger.warning("CSV read error: %s", exc)
    finally:
        try:
            os.unlink(tmp_csv)
        except OSError:
            pass

    # Fallback to export JSON
    if not csv_exists and result_json.get("csv_exists"):
        csv_exists = True
        csv_size   = result_json.get("csv_size_bytes", 0)
        csv_header = result_json.get("csv_header", "")
        csv_rows   = result_json.get("csv_line_count", 0) - 1  # subtract header

    # ------------------------------------------------------------------
    # Independently copy report
    # ------------------------------------------------------------------
    report_size    = 0
    report_exists  = False
    report_content = ""
    tmp_report     = tempfile.mktemp(suffix=".txt")
    try:
        if _safe_copy(copy_from_env, r"C:\Users\Docker\Desktop\phase_analysis.txt", tmp_report):
            report_size   = os.path.getsize(tmp_report)
            report_exists = True
            with open(tmp_report, "r", encoding="utf-8", errors="replace") as f:
                report_content = f.read()
    except Exception as exc:
        logger.warning("Report read error: %s", exc)
    finally:
        try:
            os.unlink(tmp_report)
        except OSError:
            pass

    if not report_exists and result_json.get("report_exists"):
        report_exists  = True
        report_size    = result_json.get("report_size_bytes", 0)
        report_content = result_json.get("report_content", "")

    # ------------------------------------------------------------------
    # Output gate
    # ------------------------------------------------------------------
    if not csv_exists and not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output gate: no output files found. Score=0.",
        }

    # ------------------------------------------------------------------
    # Criterion 1 (25 pts): CSV with case-0002-specific tracks
    # ------------------------------------------------------------------
    header_upper = csv_header.upper()
    matched_tracks = [t for t in CASE_0002_UNIQUE_TRACKS if t.upper() in header_upper]

    if csv_exists and csv_size >= CSV_MIN_SIZE and len(matched_tracks) >= 2:
        score += 25
        feedback_parts.append(
            f"CSV has case-0002 tracks in header ({', '.join(matched_tracks[:5])}, {csv_size:,} bytes)"
        )
    elif csv_exists and csv_size >= CSV_MIN_SIZE and len(matched_tracks) == 1:
        score += 12
        feedback_parts.append(
            f"CSV exists but only 1 case-0002 track matched ({matched_tracks[0]}) — "
            f"may be wrong case or partial export"
        )
    elif csv_exists and csv_size >= CSV_MIN_SIZE:
        score += 8
        feedback_parts.append(
            f"CSV exists ({csv_size:,} bytes) but no case-0002 tracks found in header "
            f"(header: {csv_header[:120]})"
        )
    elif csv_exists:
        score += 4
        feedback_parts.append(f"CSV exists but too small ({csv_size} bytes)")
    else:
        feedback_parts.append("CSV not found at expected path")

    # ------------------------------------------------------------------
    # Criterion 2 (20 pts): CSV is an intraop segment (not full recording)
    # ------------------------------------------------------------------
    if csv_exists and csv_rows > 0:
        frac = csv_rows / FULL_CASE_ROWS_APPROX
        if INTRAOP_FRAC_MIN <= frac <= INTRAOP_FRAC_MAX:
            score += 20
            feedback_parts.append(
                f"CSV row count ({csv_rows:,}) consistent with intraop segment "
                f"({frac:.1%} of full case — expected {INTRAOP_FRAC_MIN:.0%}–{INTRAOP_FRAC_MAX:.0%})"
            )
        elif frac > INTRAOP_FRAC_MAX:
            # Too many rows — probably full case was exported
            score += 8
            feedback_parts.append(
                f"CSV rows ({csv_rows:,}) = {frac:.1%} of full case — appears to be full recording, "
                f"not just intraop segment (expected <{INTRAOP_FRAC_MAX:.0%})"
            )
        elif frac < INTRAOP_FRAC_MIN and csv_rows > 500:
            # Some data but not enough for a realistic surgical segment
            score += 10
            feedback_parts.append(
                f"CSV rows ({csv_rows:,}) = {frac:.1%} of full case — segment shorter than expected"
            )
        else:
            feedback_parts.append(
                f"CSV rows ({csv_rows:,}) too few to represent an intraop segment"
            )
    elif csv_exists:
        feedback_parts.append("Could not determine CSV row count for segment validation")
    else:
        feedback_parts.append("CSV not available for segment check")

    report_lower = report_content.lower()

    # ------------------------------------------------------------------
    # Criterion 3 (20 pts): Phase analysis report with substantial content
    # ------------------------------------------------------------------
    if report_exists and report_size >= REPORT_MIN_SIZE:
        score += 20
        feedback_parts.append(f"Phase report exists with substantial content ({report_size:,} bytes)")
    elif report_exists:
        score += 8
        feedback_parts.append(f"Phase report exists but too short ({report_size} bytes, need >={REPORT_MIN_SIZE})")
    else:
        feedback_parts.append("Phase analysis report not found")

    # ------------------------------------------------------------------
    # Criterion 4 (20 pts): Report identifies case 0002 as the longest
    # ------------------------------------------------------------------
    if report_content:
        has_0002 = "0002" in report_content
        has_longest_context = any(
            kw in report_lower
            for kw in ["longest", "4 hour", "4h", "262 min", "262min", "15740", "15,740",
                        "4:22", "four hour"]
        )
        if has_0002 and has_longest_context:
            score += 20
            feedback_parts.append("Report correctly identifies case 0002 as the longest case with duration context")
        elif has_0002:
            score += 10
            feedback_parts.append("Report mentions case 0002 but lacking longest-case duration context")
        elif has_longest_context:
            score += 8
            feedback_parts.append("Report has duration context for longest case but doesn't name case 0002")
        else:
            feedback_parts.append("Report does not identify case 0002 as longest case")
    else:
        feedback_parts.append("No report content for case identification check")

    # ------------------------------------------------------------------
    # Criterion 5 (15 pts): Report contains quantitative phase-duration data
    # ------------------------------------------------------------------
    if report_content:
        quant_matches = QUANT_PATTERN.findall(report_content)
        phase_matches = [t for t in PHASE_TERMS if t in report_lower]

        if len(quant_matches) >= 3 and len(phase_matches) >= 2:
            score += 15
            feedback_parts.append(
                f"Report has quantitative phase data ({len(quant_matches)} numeric+unit matches, "
                f"phase terms: {', '.join(phase_matches[:4])})"
            )
        elif len(quant_matches) >= 1 and len(phase_matches) >= 1:
            score += 8
            feedback_parts.append(
                f"Report has some quantitative content ({len(quant_matches)} numeric matches, "
                f"{len(phase_matches)} phase terms) — could be more detailed"
            )
        elif len(phase_matches) >= 2:
            score += 5
            feedback_parts.append(f"Report mentions phases ({', '.join(phase_matches[:4])}) but lacks numeric data")
        else:
            feedback_parts.append("Report lacks quantitative phase-duration data")
    else:
        feedback_parts.append("No report content for quantitative phase check")

    # ------------------------------------------------------------------
    # Final verdict
    # ------------------------------------------------------------------
    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
