#!/usr/bin/env python3
"""Verifier for export_intraoperative_segment task.

MULTI-CRITERION SCORING (100 points total):
  Criterion 1 (25 pts): CSV export file exists at expected path with >100 bytes
  Criterion 2 (25 pts): CSV contains physiological data columns (ART, ECG, PLETH, etc.)
  Criterion 3 (20 pts): CSV data represents intraoperative period, not full recording
                         (row count significantly less than full-case export)
  Criterion 4 (15 pts): CSV has header row with recognizable vital signs track names
  Criterion 5 (15 pts): File was created after the task started (timestamp check)

Output gate: If no CSV file exists, return score=0 immediately.
Pass threshold: 60 points
"""

import csv
import io
import json
import logging
import os
import tempfile
import shutil
from typing import Any, Dict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Minimum file size to consider a real CSV export (not empty/stub)
MIN_CSV_SIZE_BYTES = 100

# Paths inside the Windows VM
CSV_PATH = r"C:\Users\Docker\Desktop\intraop_0001.csv"
RESULT_JSON_PATH = r"C:\Users\Docker\Desktop\task_result_intraop.json"
BASELINE_JSON_PATH = r"C:\Users\Docker\task_baseline_intraop.json"

# Known physiological signal column name fragments from Vital Recorder / VitalDB
# These are substrings that may appear in CSV column headers
PHYSIO_COLUMN_KEYWORDS = [
    "ART",       # arterial blood pressure
    "ECG",       # electrocardiogram leads
    "PLETH",     # pulse oximetry plethysmograph
    "CO2",       # capnography (end-tidal CO2)
    "AWP",       # airway pressure
    "BIS",       # bispectral index (depth of anesthesia)
    "SEVO",      # sevoflurane (anesthetic agent)
    "HR",        # heart rate
    "SPO2",      # peripheral oxygen saturation
    "RR",        # respiratory rate
    "BT",        # body temperature
    "NIBP",      # non-invasive blood pressure
    "TV",        # tidal volume
    "PEEP",      # positive end-expiratory pressure
    "FIO2",      # fraction of inspired oxygen
    "MV",        # minute ventilation
    "INSP",      # inspired agent concentration
    "EXP",       # expired agent concentration
    "AGENT",     # anesthetic agent
    "TEMP",      # temperature
    "CVP",       # central venous pressure
    "PPV",       # pulse pressure variation
    "SV",        # stroke volume
    "CI",        # cardiac index
    "PIP",       # peak inspiratory pressure
]

# The full case 0001.vital is ~3h12m = ~11542 seconds.
# At 1-second intervals, a full export would have ~11542 data rows.
# The intraoperative segment is ~145 min = ~8700 seconds.
# So the intraop fraction should be roughly 0.50 to 0.90 of total.
FULL_CASE_APPROX_ROWS = 11542
INTRAOP_FRACTION_MIN = 0.40  # generous lower bound
INTRAOP_FRACTION_MAX = 0.95  # must be less than full export


def _try_copy(copy_from_env, remote_path: str, local_path: str) -> bool:
    """Attempt to copy a file from the VM; return True on success."""
    try:
        copy_from_env(remote_path, local_path)
        return os.path.exists(local_path) and os.path.getsize(local_path) > 0
    except Exception as exc:
        logger.debug("copy_from_env(%s) failed: %s", remote_path, exc)
        return False


def _count_physio_columns(column_names):
    """Count how many column names match known physiological signal keywords."""
    matches = []
    for col in column_names:
        col_upper = col.strip().strip('"').upper()
        for keyword in PHYSIO_COLUMN_KEYWORDS:
            if keyword in col_upper:
                matches.append(col.strip().strip('"'))
                break
    return matches


def verify_export_intraoperative_segment(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Multi-criterion verifier for the export_intraoperative_segment task.

    Uses copy_from_env to independently retrieve the CSV file and result JSON
    from the VM, then applies multi-criterion scoring.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available -- framework error",
        }

    metadata = task_info.get("metadata", {})
    pass_threshold = metadata.get("pass_threshold", 60)

    temp_dir = tempfile.mkdtemp(prefix="verify_intraop_export_")
    feedback_parts = []
    score = 0
    details = {}

    try:
        # ==============================================================
        # Step 1: Fetch the result JSON produced by export_result.ps1
        # ==============================================================
        result_json_local = os.path.join(temp_dir, "task_result_intraop.json")
        result_data = None

        if _try_copy(copy_from_env, RESULT_JSON_PATH, result_json_local):
            try:
                with open(result_json_local, "r", encoding="utf-8-sig") as fh:
                    result_data = json.load(fh)
                logger.debug("Result JSON loaded successfully")
            except Exception as exc:
                logger.warning("Failed to parse result JSON: %s", exc)

        details["export_result_loaded"] = result_data is not None

        # ==============================================================
        # Step 2: Fetch the baseline JSON (task start timestamp)
        # ==============================================================
        baseline_json_local = os.path.join(temp_dir, "task_baseline_intraop.json")
        baseline_data = None

        if _try_copy(copy_from_env, BASELINE_JSON_PATH, baseline_json_local):
            try:
                with open(baseline_json_local, "r", encoding="utf-8-sig") as fh:
                    baseline_data = json.load(fh)
            except Exception as exc:
                logger.warning("Failed to parse baseline JSON: %s", exc)

        task_start_unix = 0
        if baseline_data:
            task_start_unix = baseline_data.get("task_start_unix", 0)
        elif result_data:
            task_start_unix = result_data.get("task_start_unix", 0)

        details["task_start_unix"] = task_start_unix

        # ==============================================================
        # Step 3: Independently copy the CSV file (anti-tamper)
        # ==============================================================
        csv_local = os.path.join(temp_dir, "intraop_0001.csv")
        csv_copied = _try_copy(copy_from_env, CSV_PATH, csv_local)
        csv_size = os.path.getsize(csv_local) if csv_copied else 0

        details["csv_copied"] = csv_copied
        details["csv_size_bytes"] = csv_size

        # ==============================================================
        # OUTPUT GATE: If no CSV file exists, return score=0 immediately
        # ==============================================================
        if not csv_copied or csv_size < MIN_CSV_SIZE_BYTES:
            details["gate"] = "No CSV file found or file too small"
            size_info = f"{csv_size} bytes" if csv_copied else "not found"
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    f"OUTPUT GATE FAIL: CSV export file not found or too small "
                    f"({size_info}, need >{MIN_CSV_SIZE_BYTES} bytes) at "
                    f"{CSV_PATH}"
                ),
                "details": details,
            }

        # ==============================================================
        # Parse CSV content for analysis
        # ==============================================================
        header_line = ""
        column_names = []
        data_line_count = 0
        csv_parse_error = None

        try:
            with open(csv_local, "r", encoding="utf-8-sig") as fh:
                lines = fh.readlines()

            total_lines = len(lines)

            if total_lines > 0:
                header_line = lines[0].strip()
                # Parse column names -- handle both comma-separated and tab-separated
                if "\t" in header_line:
                    column_names = [c.strip().strip('"') for c in header_line.split("\t")]
                else:
                    column_names = [c.strip().strip('"') for c in header_line.split(",")]

            # Count non-empty data lines (skip header)
            data_line_count = sum(
                1 for line in lines[1:] if line.strip()
            )
        except Exception as exc:
            csv_parse_error = str(exc)
            logger.warning("Failed to parse CSV: %s", exc)

        details["header_line"] = header_line[:200]  # truncate for safety
        details["column_names"] = column_names
        details["column_count"] = len(column_names)
        details["data_line_count"] = data_line_count
        details["csv_parse_error"] = csv_parse_error

        # ==============================================================
        # CRITERION 1 (25 pts): CSV file exists with >100 bytes
        # ==============================================================
        try:
            csv_size_kb = csv_size / 1024.0
            if csv_copied and csv_size > MIN_CSV_SIZE_BYTES:
                score += 25
                feedback_parts.append(
                    f"Criterion 1 PASS: CSV exists ({csv_size_kb:.1f} KB, "
                    f"{data_line_count} data rows) (+25)"
                )
            else:
                feedback_parts.append(
                    f"Criterion 1 FAIL: CSV too small ({csv_size_kb:.1f} KB)"
                )
            details["criterion_1_csv_size_kb"] = csv_size_kb
        except Exception as e:
            feedback_parts.append(f"Criterion 1 ERROR: {str(e)[:80]}")

        # ==============================================================
        # CRITERION 2 (25 pts): CSV contains physiological data columns
        # ==============================================================
        try:
            physio_matches = _count_physio_columns(column_names)
            physio_count = len(physio_matches)

            details["physio_columns_found"] = physio_matches
            details["physio_column_count"] = physio_count

            if physio_count >= 4:
                score += 25
                feedback_parts.append(
                    f"Criterion 2 PASS: {physio_count} physiological columns "
                    f"({', '.join(physio_matches[:6])}) (+25)"
                )
            elif physio_count >= 2:
                score += 15
                feedback_parts.append(
                    f"Criterion 2 PARTIAL: {physio_count} physiological columns "
                    f"({', '.join(physio_matches)}) (+15)"
                )
            elif physio_count >= 1:
                score += 8
                feedback_parts.append(
                    f"Criterion 2 PARTIAL: only {physio_count} physiological "
                    f"column(s) ({', '.join(physio_matches)}) (+8)"
                )
            else:
                feedback_parts.append(
                    "Criterion 2 FAIL: no recognizable physiological data columns "
                    f"in header. Columns found: {column_names[:10]}"
                )
        except Exception as e:
            feedback_parts.append(f"Criterion 2 ERROR: {str(e)[:80]}")

        # ==============================================================
        # CRITERION 3 (20 pts): Data represents intraoperative period
        #   (not the full recording -- row count check)
        # ==============================================================
        try:
            # The full case at 1s intervals would be ~11542 rows.
            # Intraop segment is ~8700 seconds = ~8700 rows at 1s intervals.
            # We check that the exported rows are significantly less than the
            # full recording and within the expected intraop fraction range.
            #
            # However, the sampling interval may vary. We use the fraction
            # heuristic: if the data_line_count is between 40% and 95% of
            # FULL_CASE_APPROX_ROWS (or of a proportional estimate), the
            # agent likely exported only the intraop segment.
            #
            # Also check result_data from export_result.ps1 for cross-validation.

            result_data_lines = 0
            if result_data:
                result_data_lines = result_data.get("csv_data_line_count", 0)

            effective_data_lines = max(data_line_count, result_data_lines)

            details["effective_data_lines"] = effective_data_lines
            details["full_case_approx_rows"] = FULL_CASE_APPROX_ROWS

            if effective_data_lines == 0:
                feedback_parts.append(
                    "Criterion 3 FAIL: CSV has no data rows"
                )
            elif effective_data_lines > 0:
                # Calculate fraction relative to full case
                fraction = effective_data_lines / FULL_CASE_APPROX_ROWS
                details["intraop_fraction"] = round(fraction, 4)

                # The intraop period is ~75% of total case duration.
                # A truly segment-only export should have noticeably fewer
                # rows than a full export. We give full credit if fraction
                # is between 0.40 and 0.90 (generous bounds).
                # We also accept if the agent exported at a different
                # sampling rate, so we just check the fraction is not ~1.0.
                if INTRAOP_FRACTION_MIN <= fraction <= INTRAOP_FRACTION_MAX:
                    score += 20
                    feedback_parts.append(
                        f"Criterion 3 PASS: {effective_data_lines} data rows "
                        f"({fraction:.1%} of full case) -- intraop segment (+20)"
                    )
                elif fraction < INTRAOP_FRACTION_MIN and effective_data_lines > 100:
                    # Fewer rows than expected but still substantial data.
                    # Could be higher sampling interval or partial segment.
                    score += 12
                    feedback_parts.append(
                        f"Criterion 3 PARTIAL: {effective_data_lines} data rows "
                        f"({fraction:.1%} of full case) -- smaller than expected "
                        f"intraop window (+12)"
                    )
                elif fraction > INTRAOP_FRACTION_MAX:
                    # Too close to full recording -- agent may have exported
                    # everything instead of just the intraop segment.
                    score += 5
                    feedback_parts.append(
                        f"Criterion 3 PARTIAL: {effective_data_lines} data rows "
                        f"({fraction:.1%} of full case) -- may include pre/post-op "
                        f"periods (+5)"
                    )
                else:
                    # Very few rows
                    score += 3
                    feedback_parts.append(
                        f"Criterion 3 PARTIAL: only {effective_data_lines} data "
                        f"rows ({fraction:.1%} of full case) (+3)"
                    )
        except Exception as e:
            feedback_parts.append(f"Criterion 3 ERROR: {str(e)[:80]}")

        # ==============================================================
        # CRITERION 4 (15 pts): CSV has header row with recognizable
        #   vital signs track names
        # ==============================================================
        try:
            # A valid header should have multiple column names that look
            # like vital signs track names (not just generic "col1, col2")
            has_header = bool(header_line) and len(column_names) >= 2
            track_name_matches = _count_physio_columns(column_names)

            details["has_header"] = has_header
            details["header_track_names"] = track_name_matches

            if has_header and len(track_name_matches) >= 3:
                score += 15
                feedback_parts.append(
                    f"Criterion 4 PASS: header has {len(track_name_matches)} "
                    f"track names (+15)"
                )
            elif has_header and len(track_name_matches) >= 1:
                score += 8
                feedback_parts.append(
                    f"Criterion 4 PARTIAL: header has {len(track_name_matches)} "
                    f"track name(s) (+8)"
                )
            elif has_header:
                # Header exists but no recognized track names
                score += 3
                feedback_parts.append(
                    f"Criterion 4 PARTIAL: header exists but no recognizable "
                    f"track names. Columns: {column_names[:8]} (+3)"
                )
            else:
                feedback_parts.append(
                    "Criterion 4 FAIL: no header row detected"
                )
        except Exception as e:
            feedback_parts.append(f"Criterion 4 ERROR: {str(e)[:80]}")

        # ==============================================================
        # CRITERION 5 (15 pts): File created after task start
        # ==============================================================
        try:
            csv_created_after = False
            csv_last_write = 0

            # Get timestamp from result_data (export_result.ps1)
            if result_data:
                csv_created_after = result_data.get(
                    "csv_created_after_start", False
                )
                csv_last_write = result_data.get("csv_last_write_unix", 0)

            # Also check directly from copied file's modification time
            if csv_copied:
                local_mtime = os.path.getmtime(csv_local)
                # The local mtime won't match VM time, so rely on result_data

            details["csv_created_after_start"] = csv_created_after
            details["csv_last_write_unix"] = csv_last_write

            if csv_created_after:
                score += 15
                feedback_parts.append(
                    "Criterion 5 PASS: CSV created after task start (+15)"
                )
            elif csv_last_write > 0 and task_start_unix > 0:
                # File exists with a timestamp but before task start --
                # could be clock skew
                time_diff = csv_last_write - task_start_unix
                if time_diff >= -60:  # allow 60s clock skew
                    score += 15
                    feedback_parts.append(
                        f"Criterion 5 PASS: CSV timestamp within tolerance "
                        f"(diff={time_diff}s) (+15)"
                    )
                else:
                    score += 5
                    feedback_parts.append(
                        f"Criterion 5 PARTIAL: CSV exists but timestamp "
                        f"precedes task start by {abs(time_diff)}s (+5)"
                    )
            elif csv_last_write > 0:
                # Timestamp exists but no baseline to compare
                score += 10
                feedback_parts.append(
                    "Criterion 5 PARTIAL: CSV has timestamp but baseline "
                    "unavailable for comparison (+10)"
                )
            else:
                feedback_parts.append(
                    "Criterion 5 FAIL: cannot verify file creation time"
                )
        except Exception as e:
            feedback_parts.append(f"Criterion 5 ERROR: {str(e)[:80]}")

    finally:
        try:
            shutil.rmtree(temp_dir)
        except Exception:
            pass

    # ==================================================================
    # Final assessment
    # ==================================================================
    passed = score >= pass_threshold

    details["score_breakdown"] = {
        "criterion_1_csv_exists": "25 pts max",
        "criterion_2_physio_columns": "25 pts max",
        "criterion_3_intraop_segment": "20 pts max",
        "criterion_4_header_track_names": "15 pts max",
        "criterion_5_created_after_start": "15 pts max",
        "total_score": score,
        "pass_threshold": pass_threshold,
    }

    summary = f"Score: {score}/100"
    if passed:
        summary = f"PASSED -- {summary}"
    else:
        summary = f"FAILED (need >={pass_threshold}) -- {summary}"

    logger.info(
        "export_intraoperative_segment: %s | %s",
        summary,
        " | ".join(feedback_parts),
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": summary + " | " + " | ".join(feedback_parts),
        "details": details,
    }
