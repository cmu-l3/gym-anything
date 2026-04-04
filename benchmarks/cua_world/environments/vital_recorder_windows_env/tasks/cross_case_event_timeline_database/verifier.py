#!/usr/bin/env python3
"""Verifier for cross_case_event_timeline_database task.

Scoring (100 points total):
  Criterion 1 (20 pts): All three CSV exports exist (case_0001_events.csv,
                        case_0002_events.csv, case_0003_events.csv), each >=100 bytes
  Criterion 2 (20 pts): Event database document exists with substantial content (>=400 bytes)
  Criterion 3 (20 pts): Database mentions all three case identifiers (0001, 0002, 0003)
  Criterion 4 (20 pts): Database contains recognized event names
                        ('Surgery started', 'Surgery finished', 'Case started', 'Case finished')
  Criterion 5 (20 pts): Database has numeric time data (minutes or timestamps per event)

Output gate: score=0 if no CSV files AND no database exist.
Pass threshold: 60 points

Ground truth:
  Each of the 3 cases has exactly 4 events:
    'Case started', 'Surgery started', 'Surgery finished', 'Case finished'
  Total expected events across all cases: 12
  The database must cover all three cases and categorize events by perioperative phase.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD  = 60
CSV_MIN_SIZE    = 100
DB_MIN_SIZE     = 400

# Known event names in all three recordings
KNOWN_EVENTS = [
    "case started", "surgery started", "surgery finished", "case finished",
    "case start", "surgery start", "surgery finish", "case finish",
    "surgical incision", "incision", "closure", "wound closure",
]

# Numeric time patterns — a number with minute/time context
TIME_PATTERN = re.compile(
    r"\b\d+\.?\d*\s*(min|minute|minutes|:|\bhr\b|\bhour\b|\bsec\b)",
    re.IGNORECASE,
)
# Also match standalone numbers that appear in tabular time columns
STANDALONE_NUMBER = re.compile(r"\b\d{1,4}\.\d{1,2}\b|\b\d{1,4}\b")

# Phase labels
PHASE_TERMS = [
    "pre-op", "pre op", "preop", "pre-operative", "preoperative",
    "intraop", "intra-op", "intraoperative",
    "post-op", "post op", "postop", "post-operative", "postoperative",
]


def _safe_copy(copy_from_env, remote_path, local_path):
    try:
        copy_from_env(remote_path, local_path)
        return os.path.exists(local_path) and os.path.getsize(local_path) > 0
    except Exception as exc:
        logger.warning("copy_from_env(%s) failed: %s", remote_path, exc)
        return False


def _get_csv_info(copy_from_env, remote_path, label):
    """Copy a CSV and return (exists, size_bytes, header)."""
    tmp = tempfile.mktemp(suffix=".csv")
    try:
        if _safe_copy(copy_from_env, remote_path, tmp):
            size = os.path.getsize(tmp)
            with open(tmp, "r", encoding="utf-8", errors="replace") as f:
                header = f.readline().strip()
            logger.info("%s: size=%d, header=%s", label, size, header[:80])
            return True, size, header
        return False, 0, ""
    except Exception as exc:
        logger.warning("CSV check for %s failed: %s", label, exc)
        return False, 0, ""
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def verify_cross_case_event_timeline_database(traj, env_info, task_info):
    """Multi-criterion verifier for cross_case_event_timeline_database."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # ------------------------------------------------------------------
    # Supplemental export JSON
    # ------------------------------------------------------------------
    result_json = {}
    tmp_json = tempfile.mktemp(suffix=".json")
    try:
        if _safe_copy(copy_from_env, r"C:\Users\Docker\task_result_event_timeline.json", tmp_json):
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
    # Collect CSV info for all three cases
    # ------------------------------------------------------------------
    csvs = {}
    for case_id in ["0001", "0002", "0003"]:
        remote = rf"C:\Users\Docker\Desktop\case_{case_id}_events.csv"
        ex, sz, hdr = _get_csv_info(copy_from_env, remote, f"CSV-{case_id}")
        if not ex and result_json.get(f"csv_{case_id}_exists"):
            ex  = True
            sz  = result_json.get(f"csv_{case_id}_size_bytes", 0)
            hdr = result_json.get(f"csv_{case_id}_header", "")
        csvs[case_id] = {"exists": ex, "size": sz, "header": hdr}

    # ------------------------------------------------------------------
    # Collect database document
    # ------------------------------------------------------------------
    db_exists  = False
    db_size    = 0
    db_content = ""
    tmp_db     = tempfile.mktemp(suffix=".txt")
    try:
        if _safe_copy(copy_from_env, r"C:\Users\Docker\Desktop\event_timeline_db.txt", tmp_db):
            db_exists = True
            db_size   = os.path.getsize(tmp_db)
            with open(tmp_db, "r", encoding="utf-8", errors="replace") as f:
                db_content = f.read()
    except Exception as exc:
        logger.warning("DB read error: %s", exc)
    finally:
        try:
            os.unlink(tmp_db)
        except OSError:
            pass

    if not db_exists and result_json.get("db_exists"):
        db_exists  = True
        db_size    = result_json.get("db_size_bytes", 0)
        db_content = result_json.get("db_content", "")

    # ------------------------------------------------------------------
    # Output gate
    # ------------------------------------------------------------------
    any_csv    = any(c["exists"] for c in csvs.values())
    if not any_csv and not db_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output gate: no output files found at all. Score=0.",
        }

    # ------------------------------------------------------------------
    # Criterion 1 (20 pts): All three CSV files exist and are substantial
    # ------------------------------------------------------------------
    present = [cid for cid, info in csvs.items() if info["exists"] and info["size"] >= CSV_MIN_SIZE]
    n_present = len(present)

    if n_present == 3:
        score += 20
        sizes_str = ", ".join(f"{csvs[c]['size']:,}" for c in ["0001", "0002", "0003"])
        feedback_parts.append(
            f"All 3 case CSV files present and substantial (sizes: {sizes_str} bytes)"
        )
    elif n_present == 2:
        score += 13
        feedback_parts.append(f"2/3 CSV files found (present: {', '.join(present)})")
    elif n_present == 1:
        score += 6
        feedback_parts.append(f"1/3 CSV files found (present: {present[0]})")
    else:
        feedback_parts.append("No substantial CSV files found (need case_XXXX_events.csv for all 3 cases)")

    # ------------------------------------------------------------------
    # Criterion 2 (20 pts): Event database with substantial content
    # ------------------------------------------------------------------
    if db_exists and db_size >= DB_MIN_SIZE:
        score += 20
        feedback_parts.append(f"Event database document exists with substantial content ({db_size:,} bytes)")
    elif db_exists:
        score += 8
        feedback_parts.append(f"Event database too brief ({db_size} bytes, need >={DB_MIN_SIZE})")
    else:
        feedback_parts.append("Event database (event_timeline_db.txt) not found")

    db_lower = db_content.lower()

    # ------------------------------------------------------------------
    # Criterion 3 (20 pts): Database covers all three cases
    # ------------------------------------------------------------------
    if db_content:
        cases_in_db = [cid for cid in ["0001", "0002", "0003"] if cid in db_content]
        if len(cases_in_db) == 3:
            score += 20
            feedback_parts.append("Database covers all three cases (0001, 0002, 0003)")
        elif len(cases_in_db) == 2:
            score += 12
            feedback_parts.append(f"Database covers 2/3 cases ({', '.join(cases_in_db)})")
        elif len(cases_in_db) == 1:
            score += 5
            feedback_parts.append(f"Database covers only 1 case ({cases_in_db[0]})")
        else:
            feedback_parts.append("Database does not reference any case identifiers (0001/0002/0003)")
    else:
        feedback_parts.append("No database content to check for case coverage")

    # ------------------------------------------------------------------
    # Criterion 4 (20 pts): Database contains recognized event names
    # ------------------------------------------------------------------
    if db_content:
        matched_events = [e for e in KNOWN_EVENTS if e in db_lower]
        # Also accept common variants
        has_surgery_event = (
            "surgery" in db_lower and
            ("started" in db_lower or "finished" in db_lower or "start" in db_lower or "end" in db_lower)
        )
        has_case_event = (
            ("case" in db_lower or "recording" in db_lower) and
            ("started" in db_lower or "finished" in db_lower or "start" in db_lower)
        )

        if len(matched_events) >= 2:
            score += 20
            feedback_parts.append(
                f"Database contains recognized event names ({', '.join(matched_events[:4])})"
            )
        elif has_surgery_event and has_case_event:
            score += 15
            feedback_parts.append("Database has surgery and case event references (minor naming variation)")
        elif has_surgery_event or has_case_event:
            score += 8
            feedback_parts.append("Database has partial event coverage (surgery OR case events, not both)")
        else:
            feedback_parts.append(
                "Database lacks recognized event names "
                "('Surgery started/finished', 'Case started/finished')"
            )
    else:
        feedback_parts.append("No database content for event name check")

    # ------------------------------------------------------------------
    # Criterion 5 (20 pts): Database has numeric time data
    # ------------------------------------------------------------------
    if db_content:
        time_matches = TIME_PATTERN.findall(db_content)
        standalone_nums = STANDALONE_NUMBER.findall(db_content)
        phase_matches   = [t for t in PHASE_TERMS if t in db_lower]

        if len(time_matches) >= 3:
            score += 20
            feedback_parts.append(
                f"Database has {len(time_matches)} numeric time entries with units "
                f"(phase labels: {', '.join(phase_matches[:3]) if phase_matches else 'none found'})"
            )
        elif len(time_matches) >= 1 or (len(standalone_nums) >= 8 and phase_matches):
            score += 12
            feedback_parts.append(
                f"Database has some numeric time data ({len(time_matches)} with units, "
                f"{len(standalone_nums)} standalone numbers)"
            )
        elif len(standalone_nums) >= 4:
            score += 6
            feedback_parts.append(
                f"Database has numbers ({len(standalone_nums)}) but time units/context unclear"
            )
        else:
            feedback_parts.append("Database lacks numeric time data for event timestamps")
    else:
        feedback_parts.append("No database content for numeric time check")

    # ------------------------------------------------------------------
    # Final verdict
    # ------------------------------------------------------------------
    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
