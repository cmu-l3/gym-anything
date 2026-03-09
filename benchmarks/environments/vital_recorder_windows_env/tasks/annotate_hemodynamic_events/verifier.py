#!/usr/bin/env python3
"""
Verifier for annotate_hemodynamic_events task.

Scoring (100 points total):
- Criterion 1 (25 pts): At least 1 new event marker was added (beyond the 4 existing ones)
- Criterion 2 (25 pts): At least 3 new event markers were added
- Criterion 3 (20 pts): CSV export exists at C:\\Users\\Docker\\Desktop\\annotated_0001.csv with >100 bytes
- Criterion 4 (15 pts): The new event markers have text labels (not empty/default)
- Criterion 5 (15 pts): CSV file contains data columns with recognizable vital signs names

Output gate: If no new events AND no CSV exists, return score=0.
Pass threshold: 60 points
"""

import json
import os
import sqlite3
import tempfile
import logging
from typing import Any, Dict, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Known initial events in the recording
INITIAL_EVENTS = {"Case started", "Surgery started", "Surgery finished", "Case finished"}
INITIAL_EVENT_COUNT = 4

# Vital signs keywords to look for in CSV header
VITAL_SIGNS_KEYWORDS = [
    "ART", "ECG", "PLETH", "CO2", "AWP", "SpO2", "HR", "BIS",
    "Solar8000", "Primus", "Orchestra", "FiO2", "EtCO2",
    "NIBP", "ABP", "CVP", "PPV", "SV", "SVR",
    "MAC", "TEMP", "RR", "TV", "MV", "PEEP", "PIP",
    "Time", "time",
]

# Minimum CSV size to be considered valid (>100 bytes as per spec)
MIN_CSV_SIZE_BYTES = 100


def _try_count_events_sqlite(vital_path: str) -> Dict[str, Any]:
    """
    Open a .vital (SQLite) file and try to count events and read labels.

    Returns a dict with:
      - total_events: int
      - event_labels: list of str
      - event_table: str or None
      - tables: list of table names
      - error: str or None
    """
    result = {
        "total_events": 0,
        "event_labels": [],
        "event_table": None,
        "tables": [],
        "error": None,
    }

    try:
        conn = sqlite3.connect(vital_path)
        cursor = conn.cursor()

        # Get all tables
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = [row[0] for row in cursor.fetchall()]
        result["tables"] = tables

        # Search for the events table
        event_keywords = ["event", "marker", "annot"]
        event_table = None

        # First pass: exact name match
        for t in tables:
            tl = t.lower()
            for kw in event_keywords:
                if kw in tl:
                    event_table = t
                    break
            if event_table:
                break

        if not event_table:
            # Second pass: check column names for event-like data
            for t in tables:
                try:
                    cursor.execute(f"PRAGMA table_info([{t}])")
                    cols = [c[1].lower() for c in cursor.fetchall()]
                    if any(kw in " ".join(cols) for kw in event_keywords):
                        event_table = t
                        break
                except Exception:
                    continue

        if event_table:
            result["event_table"] = event_table

            # Count total events
            cursor.execute(f"SELECT COUNT(*) FROM [{event_table}]")
            result["total_events"] = cursor.fetchone()[0]

            # Try to get event labels from various possible column names
            cursor.execute(f"PRAGMA table_info([{event_table}])")
            col_info = cursor.fetchall()
            col_names = [c[1] for c in col_info]
            col_names_lower = [c.lower() for c in col_names]

            label_col_candidates = [
                "name", "label", "text", "description", "event_name",
                "event_text", "title", "comment", "value",
            ]

            labels_found = False
            for lc in label_col_candidates:
                if lc in col_names_lower:
                    idx = col_names_lower.index(lc)
                    actual_col = col_names[idx]
                    try:
                        cursor.execute(f"SELECT [{actual_col}] FROM [{event_table}]")
                        rows = cursor.fetchall()
                        result["event_labels"] = [
                            str(r[0]) for r in rows if r[0] is not None and str(r[0]).strip()
                        ]
                        labels_found = True
                        break
                    except Exception:
                        continue

            # If no label column found, try to get all data for inspection
            if not labels_found:
                try:
                    cursor.execute(f"SELECT * FROM [{event_table}] LIMIT 20")
                    rows = cursor.fetchall()
                    # Try to extract any string values as potential labels
                    for row in rows:
                        for val in row:
                            if isinstance(val, str) and val.strip() and len(val.strip()) > 1:
                                result["event_labels"].append(val.strip())
                except Exception:
                    pass

        conn.close()
    except Exception as exc:
        result["error"] = str(exc)

    return result


def _check_csv_contents(csv_path: str) -> Dict[str, Any]:
    """
    Read the CSV file and check for vital signs column names and data.

    Returns a dict with:
      - size_bytes: int
      - line_count: int
      - header_line: str
      - has_vital_signs_cols: bool
      - vital_signs_cols_found: list of str
      - error: str or None
    """
    result = {
        "size_bytes": 0,
        "line_count": 0,
        "header_line": "",
        "has_vital_signs_cols": False,
        "vital_signs_cols_found": [],
        "error": None,
    }

    try:
        result["size_bytes"] = os.path.getsize(csv_path)

        with open(csv_path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

        result["line_count"] = len(lines)

        if lines:
            header = lines[0].strip()
            result["header_line"] = header
            header_upper = header.upper()

            found_cols = []
            for kw in VITAL_SIGNS_KEYWORDS:
                if kw.upper() in header_upper:
                    found_cols.append(kw)

            result["vital_signs_cols_found"] = found_cols
            result["has_vital_signs_cols"] = len(found_cols) > 0

    except Exception as exc:
        result["error"] = str(exc)

    return result


def verify_annotate_hemodynamic_events(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Multi-criterion verification for the annotate_hemodynamic_events task.

    Uses copy_from_env to independently retrieve:
    1. The result JSON from export_result.ps1
    2. The .vital file (SQLite) to count events
    3. The CSV export file to verify contents

    Scoring:
      Criterion 1 (25): At least 1 new event marker added
      Criterion 2 (25): At least 3 new event markers added
      Criterion 3 (20): CSV export exists and >100 bytes
      Criterion 4 (15): New events have text labels
      Criterion 5 (15): CSV contains vital signs column names

    Output gate: If no new events AND no CSV, score=0.
    Pass threshold: 60/100
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available -- framework error",
        }

    metadata = task_info.get("metadata", {})
    initial_event_count = metadata.get("initial_event_count", INITIAL_EVENT_COUNT)
    pass_threshold = metadata.get("pass_threshold", 60)

    score = 0
    feedback_parts = []
    details = {}

    # ------------------------------------------------------------------
    # Step 1: Copy and parse result JSON from export_result.ps1
    # ------------------------------------------------------------------
    export_result = {}
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_result.close()
    try:
        result_vm_path = r"C:\Users\Docker\task_result_annotate.json"
        copy_from_env(result_vm_path, tmp_result.name)
        with open(tmp_result.name, "r", encoding="utf-8", errors="ignore") as f:
            export_result = json.load(f)
        logger.info("Loaded export result JSON from VM")
    except FileNotFoundError:
        logger.warning("Result JSON not found in VM -- will check files independently")
    except Exception as exc:
        logger.warning("Could not load result JSON: %s", exc)
    finally:
        try:
            os.unlink(tmp_result.name)
        except Exception:
            pass

    details["export_result"] = export_result

    # ------------------------------------------------------------------
    # Step 2: Independently copy the .vital file and count events
    # ------------------------------------------------------------------
    tmp_vital = tempfile.NamedTemporaryFile(delete=False, suffix=".vital")
    tmp_vital.close()
    vital_copied = False
    vital_event_data = {}

    try:
        vital_vm_path = r"C:\Users\Docker\Desktop\VitalRecorderData\0001.vital"
        copy_from_env(vital_vm_path, tmp_vital.name)
        vital_size = os.path.getsize(tmp_vital.name)
        if vital_size > 0:
            vital_copied = True
            vital_event_data = _try_count_events_sqlite(tmp_vital.name)
            logger.info(
                "Vital file copied (%d bytes), events: %d, labels: %s",
                vital_size,
                vital_event_data.get("total_events", 0),
                vital_event_data.get("event_labels", []),
            )
    except FileNotFoundError:
        logger.warning("Vital file not found in VM")
    except Exception as exc:
        logger.warning("Could not copy vital file: %s", exc)
    finally:
        try:
            os.unlink(tmp_vital.name)
        except Exception:
            pass

    details["vital_file_copied"] = vital_copied
    details["vital_event_data"] = vital_event_data

    # ------------------------------------------------------------------
    # Step 3: Independently copy the CSV export file
    # ------------------------------------------------------------------
    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
    tmp_csv.close()
    csv_copied = False
    csv_analysis = {}

    try:
        csv_vm_path = r"C:\Users\Docker\Desktop\annotated_0001.csv"
        copy_from_env(csv_vm_path, tmp_csv.name)
        csv_size = os.path.getsize(tmp_csv.name)
        if csv_size > 0:
            csv_copied = True
            csv_analysis = _check_csv_contents(tmp_csv.name)
            logger.info(
                "CSV copied (%d bytes), lines: %d, vital signs cols: %s",
                csv_analysis.get("size_bytes", 0),
                csv_analysis.get("line_count", 0),
                csv_analysis.get("vital_signs_cols_found", []),
            )
    except FileNotFoundError:
        logger.warning("CSV file not found in VM")
    except Exception as exc:
        logger.warning("Could not copy CSV file: %s", exc)
    finally:
        try:
            os.unlink(tmp_csv.name)
        except Exception:
            pass

    details["csv_copied"] = csv_copied
    details["csv_analysis"] = csv_analysis

    # ------------------------------------------------------------------
    # Determine event counts: prefer direct SQLite analysis, fall back
    # to export_result.ps1 data
    # ------------------------------------------------------------------
    total_events = 0
    new_event_count = 0
    event_labels: List[str] = []

    if vital_copied and vital_event_data.get("total_events", 0) > 0:
        total_events = vital_event_data["total_events"]
        new_event_count = max(0, total_events - initial_event_count)
        event_labels = vital_event_data.get("event_labels", [])
    elif export_result:
        total_events = export_result.get("total_event_count", 0)
        new_event_count = export_result.get("new_event_count", 0)
        event_labels = export_result.get("event_labels", [])

    details["total_events"] = total_events
    details["new_event_count"] = new_event_count
    details["event_labels"] = event_labels

    # Identify which labels are new (not in the initial set)
    new_labels = [
        lbl for lbl in event_labels
        if lbl.strip() and lbl.strip() not in INITIAL_EVENTS
    ]
    details["new_labels"] = new_labels

    # ------------------------------------------------------------------
    # OUTPUT GATE: If no new events AND no CSV exists, return score=0
    # ------------------------------------------------------------------
    has_any_new_events = new_event_count > 0 or len(new_labels) > 0
    has_csv = csv_copied and csv_analysis.get("size_bytes", 0) > MIN_CSV_SIZE_BYTES

    if not has_any_new_events and not has_csv:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "Output gate: No new events detected and no valid CSV export found. "
                f"Total events in file: {total_events} (initial: {initial_event_count}). "
                f"CSV copied: {csv_copied}, CSV size: {csv_analysis.get('size_bytes', 0)} bytes."
            ),
            "details": details,
        }

    # ==================================================================
    # CRITERION 1 (25 pts): At least 1 new event marker added
    # ==================================================================
    try:
        if new_event_count >= 1 or len(new_labels) >= 1:
            score += 25
            feedback_parts.append(
                f"At least 1 new event added (found {new_event_count} new events) (+25)"
            )
        else:
            feedback_parts.append(
                f"No new events detected (total: {total_events}, initial: {initial_event_count})"
            )
    except Exception as exc:
        feedback_parts.append(f"Criterion 1 error: {exc}")

    # ==================================================================
    # CRITERION 2 (25 pts): At least 3 new event markers added
    # ==================================================================
    try:
        if new_event_count >= 3 or len(new_labels) >= 3:
            score += 25
            feedback_parts.append(
                f"At least 3 new events added (found {max(new_event_count, len(new_labels))}) (+25)"
            )
        elif new_event_count >= 2 or len(new_labels) >= 2:
            # Partial credit for 2 events
            partial = 12
            score += partial
            feedback_parts.append(
                f"Only 2 new events (need 3 for full credit) (+{partial})"
            )
        elif new_event_count >= 1 or len(new_labels) >= 1:
            # Minimal partial credit for 1 event (already scored in criterion 1)
            partial = 5
            score += partial
            feedback_parts.append(
                f"Only 1 new event (need 3 for full credit) (+{partial})"
            )
        else:
            feedback_parts.append("No new events for criterion 2")
    except Exception as exc:
        feedback_parts.append(f"Criterion 2 error: {exc}")

    # ==================================================================
    # CRITERION 3 (20 pts): CSV export exists and >100 bytes
    # ==================================================================
    try:
        csv_size = csv_analysis.get("size_bytes", 0)
        if has_csv:
            score += 20
            feedback_parts.append(
                f"CSV export exists and is valid ({csv_size:,} bytes, "
                f"{csv_analysis.get('line_count', 0)} lines) (+20)"
            )
        elif csv_copied and csv_size > 0:
            # File exists but very small
            partial = 10
            score += partial
            feedback_parts.append(
                f"CSV exists but too small ({csv_size} bytes, need >{MIN_CSV_SIZE_BYTES}) (+{partial})"
            )
        else:
            feedback_parts.append("CSV export not found at expected path")
    except Exception as exc:
        feedback_parts.append(f"Criterion 3 error: {exc}")

    # ==================================================================
    # CRITERION 4 (15 pts): New events have text labels (not empty)
    # ==================================================================
    try:
        # Check if new labels have meaningful text
        meaningful_labels = [
            lbl for lbl in new_labels
            if len(lbl.strip()) > 1 and lbl.strip().lower() not in ("event", "new event", "marker", "new marker", "untitled")
        ]

        if len(meaningful_labels) >= 3:
            score += 15
            feedback_parts.append(
                f"New events have descriptive labels: {meaningful_labels[:5]} (+15)"
            )
        elif len(meaningful_labels) >= 1:
            # Partial credit for some labels
            partial = 8
            score += partial
            feedback_parts.append(
                f"Some events have labels ({len(meaningful_labels)} of {len(new_labels)} meaningful) (+{partial})"
            )
        elif len(new_labels) > 0:
            # Labels exist but are generic/empty
            partial = 3
            score += partial
            feedback_parts.append(
                f"Events have labels but they appear generic: {new_labels[:5]} (+{partial})"
            )
        else:
            if has_any_new_events:
                feedback_parts.append("New events exist but labels could not be extracted")
            else:
                feedback_parts.append("No new event labels found")
    except Exception as exc:
        feedback_parts.append(f"Criterion 4 error: {exc}")

    # ==================================================================
    # CRITERION 5 (15 pts): CSV contains vital signs column names
    # ==================================================================
    try:
        vital_cols = csv_analysis.get("vital_signs_cols_found", [])
        has_vital_cols = csv_analysis.get("has_vital_signs_cols", False)

        # Also check from export_result fallback
        if not has_vital_cols and export_result:
            has_vital_cols = export_result.get("csv_has_vital_signs_cols", False)
            if has_vital_cols:
                vital_cols = export_result.get("csv_vital_signs_cols", [])

        if has_vital_cols and len(vital_cols) >= 2:
            score += 15
            feedback_parts.append(
                f"CSV contains vital signs columns: {vital_cols[:10]} (+15)"
            )
        elif has_vital_cols and len(vital_cols) >= 1:
            partial = 8
            score += partial
            feedback_parts.append(
                f"CSV has some vital signs columns: {vital_cols} (+{partial})"
            )
        elif has_csv:
            # CSV exists but no recognizable vital signs columns
            partial = 5
            score += partial
            header_preview = csv_analysis.get("header_line", "")[:120]
            feedback_parts.append(
                f"CSV exists but no recognized vital signs columns. Header: '{header_preview}' (+{partial})"
            )
        else:
            feedback_parts.append("No CSV available to check for vital signs columns")
    except Exception as exc:
        feedback_parts.append(f"Criterion 5 error: {exc}")

    # ==================================================================
    # Clean up
    # ==================================================================
    for tmp_path in [tmp_vital.name, tmp_csv.name]:
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except Exception:
            pass

    # ==================================================================
    # Final assessment
    # ==================================================================
    passed = score >= pass_threshold

    details["score_breakdown"] = {
        "criterion_1_new_event_exists": min(25, score),
        "criterion_2_three_new_events": "see feedback",
        "criterion_3_csv_export": "see feedback",
        "criterion_4_event_labels": "see feedback",
        "criterion_5_csv_vital_cols": "see feedback",
        "total_score": score,
    }

    summary = f"Score: {score}/100"
    if passed:
        summary = f"PASSED -- {summary}"
    else:
        summary = f"FAILED (need >={pass_threshold}) -- {summary}"

    return {
        "passed": passed,
        "score": score,
        "feedback": summary + " | " + " | ".join(feedback_parts),
        "details": details,
    }
