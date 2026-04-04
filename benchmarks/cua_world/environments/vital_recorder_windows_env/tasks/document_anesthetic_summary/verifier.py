#!/usr/bin/env python3
"""Verifier for document_anesthetic_summary task.

Scoring (100 points, 5 criteria at 20 points each):
  1. CSV export exists at C:\\Users\\Docker\\Desktop\\case_0002_vitals.csv with >100 bytes
  2. Summary document exists at C:\\Users\\Docker\\Desktop\\anesthetic_summary_0002.txt with >300 bytes
  3. Summary mentions case 0002 and contains duration information
  4. Summary lists at least 3 monitored physiological parameters by name
  5. Summary contains a narrative section (>100 chars of continuous prose)

Output gate: If neither CSV nor summary exists, return score=0.
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

CSV_PATH = "C:/Users/Docker/Desktop/case_0002_vitals.csv"
SUMMARY_PATH = "C:/Users/Docker/Desktop/anesthetic_summary_0002.txt"
RESULT_JSON_PATH = "C:/Users/Docker/task_result_summary.json"

# Known physiological parameter names that may appear in the summary.
# We check case-insensitively and allow partial matches.
KNOWN_PARAMETERS = [
    "ECG",
    "PLETH",
    "HR",
    "heart rate",
    "SPO2",
    "oxygen saturation",
    "ST_V5",
    "ST segment",
    "VENT_RR",
    "respiratory rate",
    "VENT_MV",
    "minute ventilation",
    "PLETH_HR",
    "PLETH_SPO2",
    "ECG_II",
    "ECG_V5",
    "pulse oximetry",
]

# Duration-related keywords
DURATION_KEYWORDS = [
    r"\d+\s*h",               # e.g. "4h", "4 h"
    r"\d+\s*hour",            # e.g. "4 hours"
    r"\d+\s*min",             # e.g. "22 min", "215 minutes"
    r"\d+:\d+",               # e.g. "4:22", "00:28:41"
    r"duration",              # the word itself
    r"surgical\s+time",
    r"operating\s+time",
    r"case\s+length",
    r"recording\s+length",
    r"surgery\s+started.*surgery\s+finished",
]


def _find_longest_prose_run(text):
    """Find the longest run of continuous prose (sentences, not list items).

    We define 'prose' as a sequence of characters that:
    - Contains at least one period followed by a space and an uppercase letter
      (sentence boundary) OR
    - Is a continuous block of text >100 chars without a leading bullet/dash/number

    Returns the length of the longest such run.
    """
    # Split text into paragraphs
    paragraphs = re.split(r'\n\s*\n', text)

    max_prose_len = 0
    for para in paragraphs:
        para = para.strip()
        if not para:
            continue

        # Skip paragraphs that are purely list items (every line starts with - or * or digit.)
        lines = para.split('\n')
        list_lines = sum(
            1 for line in lines
            if re.match(r'^\s*[-*\u2022]\s', line) or re.match(r'^\s*\d+[.)]\s', line)
        )
        # If more than half the lines are list items, skip
        if len(lines) > 0 and list_lines / len(lines) > 0.5:
            continue

        # Combine the paragraph into one block
        block = ' '.join(line.strip() for line in lines)
        if len(block) > max_prose_len:
            max_prose_len = len(block)

    return max_prose_len


def verify_document_anesthetic_summary(traj, env_info, task_info):
    """Multi-criterion verifier for the document_anesthetic_summary task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    # ------------------------------------------------------------------
    # Attempt to copy both output files from the VM independently
    # ------------------------------------------------------------------
    csv_local = None
    summary_local = None
    summary_text = ""

    # Copy CSV
    try:
        tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        tmp_csv.close()
        copy_from_env(CSV_PATH, tmp_csv.name)
        csv_size = os.path.getsize(tmp_csv.name)
        csv_local = tmp_csv.name
    except Exception as e:
        logger.info(f"CSV copy failed: {e}")
        csv_local = None
        csv_size = 0
        try:
            os.unlink(tmp_csv.name)
        except Exception:
            pass

    # Copy summary
    try:
        tmp_summary = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_summary.close()
        copy_from_env(SUMMARY_PATH, tmp_summary.name)
        summary_size = os.path.getsize(tmp_summary.name)
        summary_local = tmp_summary.name
        with open(tmp_summary.name, 'r', encoding='utf-8', errors='replace') as f:
            summary_text = f.read()
    except Exception as e:
        logger.info(f"Summary copy failed: {e}")
        summary_local = None
        summary_size = 0
        summary_text = ""
        try:
            os.unlink(tmp_summary.name)
        except Exception:
            pass

    # ------------------------------------------------------------------
    # OUTPUT GATE: if neither file exists, return 0
    # ------------------------------------------------------------------
    csv_exists = csv_local is not None and csv_size > 0
    summary_exists = summary_local is not None and summary_size > 0

    if not csv_exists and not summary_exists:
        # Clean up temp files
        _cleanup(csv_local, summary_local)
        return {
            "passed": False,
            "score": 0,
            "feedback": "Neither CSV export nor summary document found -- no work detected"
        }

    score = 0
    feedback_parts = []

    # ------------------------------------------------------------------
    # Criterion 1 (20 pts): CSV export exists with >100 bytes
    # ------------------------------------------------------------------
    try:
        if csv_exists and csv_size > 100:
            score += 20
            feedback_parts.append(f"CSV export found ({csv_size} bytes) (+20)")
        elif csv_exists:
            score += 5
            feedback_parts.append(f"CSV export found but small ({csv_size} bytes) (+5)")
        else:
            feedback_parts.append("CSV export not found (0)")
    except Exception as e:
        feedback_parts.append(f"CSV check error: {e}")

    # ------------------------------------------------------------------
    # Criterion 2 (20 pts): Summary document exists with >300 bytes
    # ------------------------------------------------------------------
    try:
        if summary_exists and summary_size > 300:
            score += 20
            feedback_parts.append(f"Summary document found ({summary_size} bytes) (+20)")
        elif summary_exists:
            score += 5
            feedback_parts.append(f"Summary document found but small ({summary_size} bytes) (+5)")
        else:
            feedback_parts.append("Summary document not found (0)")
    except Exception as e:
        feedback_parts.append(f"Summary existence check error: {e}")

    # ------------------------------------------------------------------
    # Criterion 3 (20 pts): Summary mentions case 0002 and duration info
    # ------------------------------------------------------------------
    try:
        if summary_text:
            text_lower = summary_text.lower()
            c3_score = 0

            # Check for case identifier "0002"
            has_case_id = "0002" in summary_text
            if has_case_id:
                c3_score += 10

            # Check for duration information
            has_duration = False
            for pattern in DURATION_KEYWORDS:
                if re.search(pattern, text_lower):
                    has_duration = True
                    break
            if has_duration:
                c3_score += 10

            score += c3_score
            parts = []
            parts.append(f"case_id={'Y' if has_case_id else 'N'}")
            parts.append(f"duration={'Y' if has_duration else 'N'}")
            feedback_parts.append(f"Case ID & duration: {', '.join(parts)} (+{c3_score})")
        else:
            feedback_parts.append("No summary text to analyze for case ID and duration (0)")
    except Exception as e:
        feedback_parts.append(f"Case ID / duration check error: {e}")

    # ------------------------------------------------------------------
    # Criterion 4 (20 pts): Summary lists at least 3 physiological params
    # ------------------------------------------------------------------
    try:
        if summary_text:
            text_lower = summary_text.lower()
            matched_params = set()
            for param in KNOWN_PARAMETERS:
                if param.lower() in text_lower:
                    # Normalize to avoid double-counting variants
                    # Group: ECG covers ECG_II, ECG_V5
                    # Group: HR covers heart rate, PLETH_HR
                    # Group: SPO2 covers PLETH_SPO2, oxygen saturation
                    # Group: PLETH covers pulse oximetry
                    # Group: VENT_RR covers respiratory rate
                    # Group: VENT_MV covers minute ventilation
                    # Group: ST covers ST_V5, ST segment
                    normalized = param.lower()
                    if "ecg" in normalized:
                        matched_params.add("ECG")
                    elif normalized in ("hr", "heart rate", "pleth_hr"):
                        matched_params.add("HR")
                    elif normalized in ("spo2", "pleth_spo2", "oxygen saturation"):
                        matched_params.add("SPO2")
                    elif "pleth" in normalized and "spo2" not in normalized and "hr" not in normalized:
                        matched_params.add("PLETH")
                    elif "vent_rr" in normalized or "respiratory rate" in normalized:
                        matched_params.add("VENT_RR")
                    elif "vent_mv" in normalized or "minute ventilation" in normalized:
                        matched_params.add("VENT_MV")
                    elif "st" in normalized:
                        matched_params.add("ST")
                    else:
                        matched_params.add(param)

            param_count = len(matched_params)
            if param_count >= 5:
                c4_score = 20
            elif param_count >= 3:
                c4_score = 20
            elif param_count >= 2:
                c4_score = 12
            elif param_count >= 1:
                c4_score = 6
            else:
                c4_score = 0

            score += c4_score
            feedback_parts.append(
                f"Physiological params: {param_count} unique groups found "
                f"({', '.join(sorted(matched_params))}) (+{c4_score})"
            )
        else:
            feedback_parts.append("No summary text to analyze for parameters (0)")
    except Exception as e:
        feedback_parts.append(f"Parameter check error: {e}")

    # ------------------------------------------------------------------
    # Criterion 5 (20 pts): Narrative section (>100 chars continuous prose)
    # ------------------------------------------------------------------
    try:
        if summary_text:
            longest_prose = _find_longest_prose_run(summary_text)
            if longest_prose >= 100:
                c5_score = 20
            elif longest_prose >= 50:
                c5_score = 10
            else:
                c5_score = 0

            score += c5_score
            feedback_parts.append(
                f"Narrative prose: longest block {longest_prose} chars (+{c5_score})"
            )
        else:
            feedback_parts.append("No summary text to analyze for narrative (0)")
    except Exception as e:
        feedback_parts.append(f"Narrative check error: {e}")

    # ------------------------------------------------------------------
    # Cleanup and return
    # ------------------------------------------------------------------
    _cleanup(csv_local, summary_local)

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }


def _cleanup(*paths):
    """Remove temporary files, ignoring errors."""
    for p in paths:
        if p:
            try:
                os.unlink(p)
            except Exception:
                pass
