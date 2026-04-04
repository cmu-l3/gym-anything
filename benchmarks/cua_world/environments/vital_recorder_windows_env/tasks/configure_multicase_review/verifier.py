#!/usr/bin/env python3
"""Verifier for configure_multicase_review task.

Scoring (100 points total, pass >= 60):
  Criterion 1 (20 pts): CSV export exists at expected path with >100 bytes
  Criterion 2 (20 pts): CSV contains anesthetic monitoring columns
                         (INSP_SEVO, EXP_SEVO, or COMPLIANCE among headers)
  Criterion 3 (20 pts): Screenshot file exists at expected path with >10 KB
  Criterion 4 (20 pts): CSV has a header row with valid track names
  Criterion 5 (20 pts): CSV has substantial data (>50 data rows)

Output gate: If neither CSV nor screenshot exists, return score=0 immediately.

Anti-tamper: The verifier independently copies files from the VM via
copy_from_env, rather than relying solely on the result JSON from
export_result.ps1.
"""

import csv
import json
import logging
import os
import shutil
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VM paths (forward-slash form accepted by copy_from_env)
CSV_PATH = "C:/Users/Docker/Desktop/case_0003_review.csv"
SCREENSHOT_PATH = "C:/Users/Docker/Desktop/monitor_view_0003.png"
RESULT_JSON_PATH = "C:/Users/Docker/task_result_multicase.json"

# Minimum sizes
MIN_CSV_SIZE_BYTES = 100
MIN_SCREENSHOT_SIZE_BYTES = 10 * 1024  # 10 KB
MIN_DATA_ROWS = 50

# Known Vital Recorder track names that should appear in the CSV header
KNOWN_TRACK_NAMES = {
    "ECG_II", "ECG_V5", "PLETH", "COMPLIANCE",
    "INSP_SEVO", "EXP_SEVO", "PAMB_MBAR", "MAWP_MBAR", "PPLAT_MBAR",
    "ART", "CO2", "AWP", "HR", "SpO2", "NIBP_SYS", "NIBP_DIA", "NIBP_MEAN",
    "ST_II", "ST_V5", "BIS", "BT", "VENT_TV", "VENT_PEEP", "VENT_RR",
}

# The anesthetic monitoring columns we specifically look for
ANESTHETIC_COLUMNS = {"INSP_SEVO", "EXP_SEVO", "COMPLIANCE"}


def _try_copy(copy_from_env, remote_path, local_path):
    """Attempt to copy a file from the VM; return True on success."""
    try:
        copy_from_env(remote_path, local_path)
        return os.path.exists(local_path) and os.path.getsize(local_path) > 0
    except Exception as exc:
        logger.debug("copy_from_env(%s) failed: %s", remote_path, exc)
        return False


def verify_configure_multicase_review(traj, env_info, task_info):
    """
    Multi-criterion verification for the configure_multicase_review task.

    Scoring:
      Criterion 1 (20): CSV file exists with >100 bytes
      Criterion 2 (20): CSV contains anesthetic monitoring columns
      Criterion 3 (20): Screenshot exists with >10 KB
      Criterion 4 (20): CSV header has valid track names
      Criterion 5 (20): CSV has >50 data rows

    Pass threshold: 60/100
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available -- framework error",
        }

    score = 0
    feedback_parts = []
    all_details = {}

    temp_dir = tempfile.mkdtemp(prefix="verify_multicase_review_")

    try:
        # ==============================================================
        # Copy result JSON from export_result.ps1 (informational only)
        # ==============================================================
        result = {}
        result_local = os.path.join(temp_dir, "task_result_multicase.json")
        if _try_copy(copy_from_env, RESULT_JSON_PATH, result_local):
            try:
                with open(result_local, "r", encoding="utf-8-sig") as fh:
                    result = json.load(fh)
                logger.debug("Result JSON loaded: %s", result)
            except Exception as exc:
                logger.warning("Failed to parse result JSON: %s", exc)
        all_details["export_result"] = result

        # ==============================================================
        # Independently copy CSV file for anti-tamper verification
        # ==============================================================
        csv_local = os.path.join(temp_dir, "case_0003_review.csv")
        csv_copied = _try_copy(copy_from_env, CSV_PATH, csv_local)
        csv_size = os.path.getsize(csv_local) if csv_copied else 0

        all_details["csv_copied"] = csv_copied
        all_details["csv_size_bytes"] = csv_size

        # ==============================================================
        # Independently copy screenshot for anti-tamper verification
        # ==============================================================
        screenshot_local = os.path.join(temp_dir, "monitor_view_0003.png")
        screenshot_copied = _try_copy(copy_from_env, SCREENSHOT_PATH, screenshot_local)
        screenshot_size = os.path.getsize(screenshot_local) if screenshot_copied else 0

        all_details["screenshot_copied"] = screenshot_copied
        all_details["screenshot_size_bytes"] = screenshot_size

        # ==============================================================
        # OUTPUT GATE: If neither CSV nor screenshot exists, return 0
        # ==============================================================
        if not csv_copied and not screenshot_copied:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Neither CSV export nor monitor screenshot found -- no work done",
                "details": all_details,
            }

        # ==============================================================
        # Parse CSV for header and data analysis
        # ==============================================================
        csv_header = []
        csv_data_rows = []

        if csv_copied and csv_size > 0:
            try:
                with open(csv_local, encoding="utf-8", errors="replace") as f:
                    reader = csv.reader(f)
                    rows = list(reader)

                if rows:
                    csv_header = [h.strip().strip('"') for h in rows[0]]
                    # Data rows: skip header, exclude empty rows
                    csv_data_rows = [
                        r for r in rows[1:]
                        if any(cell.strip() for cell in r)
                    ]
            except Exception as exc:
                logger.warning("Failed to parse CSV: %s", exc)
                all_details["csv_parse_error"] = str(exc)

        all_details["csv_header"] = csv_header
        all_details["csv_data_row_count"] = len(csv_data_rows)

        # ==============================================================
        # CRITERION 1 (20 pts): CSV file exists with >100 bytes
        # ==============================================================
        try:
            if csv_copied and csv_size > MIN_CSV_SIZE_BYTES:
                score += 20
                feedback_parts.append(
                    f"CSV file exists ({csv_size:,} bytes) (+20)"
                )
            elif csv_copied and csv_size > 0:
                score += 8
                feedback_parts.append(
                    f"CSV file exists but small ({csv_size:,} bytes, "
                    f"need >{MIN_CSV_SIZE_BYTES}) (+8)"
                )
            else:
                feedback_parts.append("CSV file not found or empty (+0)")
        except Exception as e:
            feedback_parts.append(f"CSV existence check error: {e}")

        # ==============================================================
        # CRITERION 2 (20 pts): CSV contains anesthetic monitoring columns
        # ==============================================================
        try:
            header_upper = {h.upper() for h in csv_header}
            anesthetic_found = ANESTHETIC_COLUMNS & header_upper
            all_details["anesthetic_columns_found"] = list(anesthetic_found)

            if len(anesthetic_found) >= 2:
                score += 20
                feedback_parts.append(
                    f"Anesthetic columns found: {', '.join(sorted(anesthetic_found))} (+20)"
                )
            elif len(anesthetic_found) == 1:
                score += 12
                feedback_parts.append(
                    f"Only 1 anesthetic column found: {', '.join(anesthetic_found)} "
                    f"(expected 2+ of INSP_SEVO, EXP_SEVO, COMPLIANCE) (+12)"
                )
            elif csv_copied and csv_size > 0:
                # Check if any known track names are in header at all
                # (partial credit if CSV has data but not the specific columns)
                known_in_header = KNOWN_TRACK_NAMES & header_upper
                if known_in_header:
                    score += 5
                    feedback_parts.append(
                        f"No anesthetic columns but has tracks: "
                        f"{', '.join(sorted(list(known_in_header)[:5]))} (+5)"
                    )
                else:
                    feedback_parts.append(
                        "CSV exists but no anesthetic monitoring columns found (+0)"
                    )
            else:
                feedback_parts.append("No CSV to check for anesthetic columns (+0)")
        except Exception as e:
            feedback_parts.append(f"Anesthetic column check error: {e}")

        # ==============================================================
        # CRITERION 3 (20 pts): Screenshot exists with >10 KB
        # ==============================================================
        try:
            if screenshot_copied and screenshot_size >= MIN_SCREENSHOT_SIZE_BYTES:
                score += 20
                feedback_parts.append(
                    f"Monitor screenshot exists ({screenshot_size:,} bytes) (+20)"
                )
            elif screenshot_copied and screenshot_size > 0:
                score += 10
                feedback_parts.append(
                    f"Screenshot exists but small ({screenshot_size:,} bytes, "
                    f"need >{MIN_SCREENSHOT_SIZE_BYTES:,}) (+10)"
                )
            else:
                feedback_parts.append("Monitor screenshot not found or empty (+0)")
        except Exception as e:
            feedback_parts.append(f"Screenshot check error: {e}")

        # ==============================================================
        # CRITERION 4 (20 pts): CSV has a header row with valid track names
        # ==============================================================
        try:
            if csv_header:
                header_upper = {h.upper() for h in csv_header}
                known_in_header = KNOWN_TRACK_NAMES & header_upper

                if len(known_in_header) >= 3:
                    score += 20
                    feedback_parts.append(
                        f"CSV header has {len(known_in_header)} valid track names "
                        f"({', '.join(sorted(list(known_in_header)[:6]))}) (+20)"
                    )
                elif len(known_in_header) >= 1:
                    score += 10
                    feedback_parts.append(
                        f"CSV header has {len(known_in_header)} valid track name(s) "
                        f"(expected 3+) (+10)"
                    )
                else:
                    # Header exists but no recognized track names
                    # Could be a time column only or different naming
                    if len(csv_header) >= 2:
                        score += 5
                        feedback_parts.append(
                            f"CSV has {len(csv_header)} header columns but no "
                            f"recognized track names (+5)"
                        )
                    else:
                        feedback_parts.append(
                            "CSV header does not contain valid track names (+0)"
                        )
            else:
                feedback_parts.append("No CSV header to validate (+0)")
        except Exception as e:
            feedback_parts.append(f"Header validation error: {e}")

        # ==============================================================
        # CRITERION 5 (20 pts): CSV has substantial data (>50 data rows)
        # ==============================================================
        try:
            num_data_rows = len(csv_data_rows)

            if num_data_rows > MIN_DATA_ROWS:
                score += 20
                feedback_parts.append(
                    f"CSV has {num_data_rows:,} data rows (+20)"
                )
            elif num_data_rows > 10:
                score += 12
                feedback_parts.append(
                    f"CSV has {num_data_rows} data rows "
                    f"(expected >{MIN_DATA_ROWS}) (+12)"
                )
            elif num_data_rows > 0:
                score += 5
                feedback_parts.append(
                    f"CSV has only {num_data_rows} data rows "
                    f"(expected >{MIN_DATA_ROWS}) (+5)"
                )
            else:
                feedback_parts.append("CSV has no data rows (+0)")
        except Exception as e:
            feedback_parts.append(f"Data row count error: {e}")

    finally:
        try:
            shutil.rmtree(temp_dir)
        except Exception:
            pass

    # ==================================================================
    # Final assessment
    # ==================================================================
    pass_threshold = 60
    passed = score >= pass_threshold

    all_details["score_breakdown"] = {
        "csv_exists": 20,
        "anesthetic_columns": 20,
        "screenshot_exists": 20,
        "valid_header": 20,
        "substantial_data": 20,
        "total_score": score,
        "pass_threshold": pass_threshold,
    }

    summary = f"Score: {score}/100"
    if passed:
        summary = f"PASSED -- {summary}"
    else:
        summary = f"FAILED (need >={pass_threshold}) -- {summary}"

    logger.info("Score: %d/100 | Passed: %s | %s", score, passed, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary + " | " + " | ".join(feedback_parts),
        "details": all_details,
    }
