#!/usr/bin/env python3
"""Verifier for compare_surgical_cases task.

Multi-criterion scoring (100 points total):
  Criterion 1 (20 pts): CSV export of case 0001 exists with >100 bytes
  Criterion 2 (20 pts): CSV export of case 0002 exists with >100 bytes
  Criterion 3 (20 pts): Comparison summary file exists with >200 bytes
  Criterion 4 (20 pts): Summary mentions both case identifiers (0001 and 0002)
  Criterion 5 (20 pts): Summary contains duration info or track names from real data

Output gate: If no output files exist at all (no CSVs and no summary),
return score=0 immediately.

Pass threshold: 60 points

The verifier independently copies files from the VM via copy_from_env
(does not rely solely on the export_result.ps1 JSON).
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Minimum file sizes
CSV_MIN_SIZE = 100          # 100 bytes -- a real CSV export will be much larger
SUMMARY_MIN_SIZE = 200      # 200 bytes -- a meaningful comparison text
PASS_THRESHOLD = 60

# Known track names from the real VitalDB cases (for criterion 5 matching)
KNOWN_TRACKS_0001 = [
    "ART", "ECG_II", "ECG_V5", "PLETH", "CO2", "AWP",
    "INSP_SEVO", "EXP_SEVO", "sevoflurane",
]
KNOWN_TRACKS_0002 = [
    "HR", "ST_II", "ST_V5", "NIBP", "SpO2",
    "VENT_TV", "VENT_PEEP", "VENT_RR", "ventilator",
]
# Duration-related patterns (any reasonable mention of time lengths)
DURATION_PATTERNS = [
    r"\b3\s*h",            # "3h", "3 h", "3 hours"
    r"\b4\s*h",            # "4h", "4 h", "4 hours"
    r"\b3.*hour",          # "3 hours", "approximately 3 hours"
    r"\b4.*hour",          # "4 hours", "approximately 4 hours"
    r"\b192\b",            # 192 minutes
    r"\b262\b",            # 262 minutes
    r"\b11[5-9]\d{2}\b",  # 11542 seconds (approx case 0001)
    r"\b15[5-9]\d{2}\b",  # 15740 seconds (approx case 0002)
    r"duration",           # generic mention of "duration"
    r"recording.{0,20}length",
    r"recording.{0,20}time",
    r"\b3:1[0-5]\b",      # "3:12" or similar time format
    r"\b4:2[0-5]\b",      # "4:22" or similar time format
]


def _safe_copy(copy_from_env, remote_path, local_path):
    """Attempt to copy a file from the VM. Returns True on success."""
    try:
        copy_from_env(remote_path, local_path)
        return os.path.exists(local_path) and os.path.getsize(local_path) > 0
    except Exception as e:
        logger.warning("Failed to copy %s: %s", remote_path, e)
        return False


def verify_compare_surgical_cases(traj, env_info, task_info):
    """Multi-criterion verifier for the compare_surgical_cases task."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    score = 0
    feedback_parts = []

    # ------------------------------------------------------------------
    # Step A: Retrieve the export JSON produced by export_result.ps1
    # ------------------------------------------------------------------
    result_json = {}
    tmp_json_path = tempfile.mktemp(suffix=".json")
    try:
        if _safe_copy(
            copy_from_env,
            r"C:\Users\Docker\task_result_compare.json",
            tmp_json_path,
        ):
            with open(tmp_json_path, "r", encoding="utf-8-sig") as f:
                result_json = json.load(f)
        else:
            feedback_parts.append("Export JSON not retrieved (post_task may not have run)")
    except Exception as e:
        feedback_parts.append(f"Export JSON parse error: {e}")
    finally:
        try:
            os.unlink(tmp_json_path)
        except OSError:
            pass

    # ------------------------------------------------------------------
    # Step B: Independently copy the output files for anti-tamper checks
    # ------------------------------------------------------------------

    # CSV 0001
    csv1_size = 0
    csv1_exists = False
    tmp_csv1 = tempfile.mktemp(suffix=".csv")
    try:
        if _safe_copy(
            copy_from_env,
            r"C:\Users\Docker\Desktop\case_0001_data.csv",
            tmp_csv1,
        ):
            csv1_size = os.path.getsize(tmp_csv1)
            csv1_exists = True
    finally:
        try:
            os.unlink(tmp_csv1)
        except OSError:
            pass

    # CSV 0002
    csv2_size = 0
    csv2_exists = False
    tmp_csv2 = tempfile.mktemp(suffix=".csv")
    try:
        if _safe_copy(
            copy_from_env,
            r"C:\Users\Docker\Desktop\case_0002_data.csv",
            tmp_csv2,
        ):
            csv2_size = os.path.getsize(tmp_csv2)
            csv2_exists = True
    finally:
        try:
            os.unlink(tmp_csv2)
        except OSError:
            pass

    # Summary text file
    summary_size = 0
    summary_exists = False
    summary_content = ""
    tmp_summary = tempfile.mktemp(suffix=".txt")
    try:
        if _safe_copy(
            copy_from_env,
            r"C:\Users\Docker\Desktop\case_comparison.txt",
            tmp_summary,
        ):
            summary_size = os.path.getsize(tmp_summary)
            summary_exists = True
            try:
                with open(tmp_summary, "r", encoding="utf-8", errors="replace") as f:
                    summary_content = f.read()
            except Exception as e:
                logger.warning("Failed to read summary content: %s", e)
    finally:
        try:
            os.unlink(tmp_summary)
        except OSError:
            pass

    # ------------------------------------------------------------------
    # Output gate: if nothing exists at all, return 0 immediately
    # ------------------------------------------------------------------
    if not csv1_exists and not csv2_exists and not summary_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output gate: no output files found (no CSVs and no summary). Score is 0.",
        }

    # ------------------------------------------------------------------
    # Criterion 1 (20 pts): CSV export of case 0001 exists with >100 bytes
    # ------------------------------------------------------------------
    try:
        if csv1_exists and csv1_size > CSV_MIN_SIZE:
            score += 20
            feedback_parts.append(
                f"CSV 0001 exists and substantial ({csv1_size:,} bytes)"
            )
        elif csv1_exists and csv1_size > 0:
            score += 10
            feedback_parts.append(
                f"CSV 0001 exists but too small ({csv1_size:,} bytes, need >{CSV_MIN_SIZE})"
            )
        else:
            feedback_parts.append("CSV 0001 not found or empty")
    except Exception as e:
        feedback_parts.append(f"CSV 0001 check error: {e}")

    # ------------------------------------------------------------------
    # Criterion 2 (20 pts): CSV export of case 0002 exists with >100 bytes
    # ------------------------------------------------------------------
    try:
        if csv2_exists and csv2_size > CSV_MIN_SIZE:
            score += 20
            feedback_parts.append(
                f"CSV 0002 exists and substantial ({csv2_size:,} bytes)"
            )
        elif csv2_exists and csv2_size > 0:
            score += 10
            feedback_parts.append(
                f"CSV 0002 exists but too small ({csv2_size:,} bytes, need >{CSV_MIN_SIZE})"
            )
        else:
            feedback_parts.append("CSV 0002 not found or empty")
    except Exception as e:
        feedback_parts.append(f"CSV 0002 check error: {e}")

    # ------------------------------------------------------------------
    # Criterion 3 (20 pts): Comparison summary file exists with >200 bytes
    # ------------------------------------------------------------------
    try:
        if summary_exists and summary_size > SUMMARY_MIN_SIZE:
            score += 20
            feedback_parts.append(
                f"Summary file exists and substantial ({summary_size:,} bytes)"
            )
        elif summary_exists and summary_size > 0:
            score += 10
            feedback_parts.append(
                f"Summary file exists but too small ({summary_size:,} bytes, need >{SUMMARY_MIN_SIZE})"
            )
        else:
            feedback_parts.append("Summary file not found or empty")
    except Exception as e:
        feedback_parts.append(f"Summary check error: {e}")

    # ------------------------------------------------------------------
    # Criterion 4 (20 pts): Summary mentions both case identifiers
    # ------------------------------------------------------------------
    try:
        if summary_content:
            has_0001 = "0001" in summary_content
            has_0002 = "0002" in summary_content
            if has_0001 and has_0002:
                score += 20
                feedback_parts.append("Summary mentions both case identifiers (0001 and 0002)")
            elif has_0001 or has_0002:
                score += 10
                mentioned = "0001" if has_0001 else "0002"
                missing = "0002" if has_0001 else "0001"
                feedback_parts.append(
                    f"Summary mentions case {mentioned} but not case {missing}"
                )
            else:
                feedback_parts.append("Summary does not mention either case identifier")
        else:
            feedback_parts.append("No summary content to check for case identifiers")
    except Exception as e:
        feedback_parts.append(f"Case identifier check error: {e}")

    # ------------------------------------------------------------------
    # Criterion 5 (20 pts): Summary contains duration info or track names
    # ------------------------------------------------------------------
    try:
        if summary_content:
            summary_lower = summary_content.lower()

            # Check for duration-related patterns
            has_duration = False
            for pattern in DURATION_PATTERNS:
                if re.search(pattern, summary_content, re.IGNORECASE):
                    has_duration = True
                    break

            # Check for known track names from either case
            track_matches = []
            all_known_tracks = KNOWN_TRACKS_0001 + KNOWN_TRACKS_0002
            for track in all_known_tracks:
                if track.lower() in summary_lower:
                    track_matches.append(track)

            has_tracks = len(track_matches) >= 2  # at least 2 track names

            if has_duration and has_tracks:
                score += 20
                feedback_parts.append(
                    f"Summary contains duration info and track names "
                    f"(matched tracks: {', '.join(track_matches[:6])})"
                )
            elif has_duration:
                score += 15
                feedback_parts.append(
                    "Summary contains duration info but few/no specific track names"
                )
            elif has_tracks:
                score += 15
                feedback_parts.append(
                    f"Summary contains track names ({', '.join(track_matches[:6])}) "
                    f"but no clear duration info"
                )
            else:
                # Partial credit if summary is long enough to be substantive
                if len(summary_content) > 500:
                    score += 5
                    feedback_parts.append(
                        "Summary is substantive but lacks specific duration/track info"
                    )
                else:
                    feedback_parts.append(
                        "Summary lacks both duration info and track names"
                    )
        else:
            feedback_parts.append("No summary content to check for duration/track data")
    except Exception as e:
        feedback_parts.append(f"Duration/track check error: {e}")

    # ------------------------------------------------------------------
    # Final verdict
    # ------------------------------------------------------------------
    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
