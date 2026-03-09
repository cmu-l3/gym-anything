#!/usr/bin/env python3
"""Verifier for respiratory_mechanics_lung_protection_review task.

Scoring (100 points total):
  Criterion 1 (25 pts): CSV exists with respiratory mechanics columns
                        (COMPLIANCE, MAWP_MBAR, PPLAT_MBAR, or PAMB_MBAR in header)
  Criterion 2 (20 pts): CSV represents intraop segment only — row count less than
                        full case 0003 total (~4,394 rows at 1 Hz)
  Criterion 3 (20 pts): Ventilation review report exists with substantial content (>=300 bytes)
  Criterion 4 (20 pts): Report identifies case 0003 and its respiratory parameters
  Criterion 5 (15 pts): Report contains clinical LPV assessment (lung protection terms)

Output gate: score=0 if no output files exist.
Pass threshold: 60 points

Ground truth:
  Case 0003.vital is the only recording with:
    COMPLIANCE (dynamic lung compliance, mL/cmH2O)
    MAWP_MBAR (mean airway pressure, mbar)
    PPLAT_MBAR (plateau pressure, mbar)
    PAMB_MBAR (ambient pressure, mbar)
  Cases 0001 and 0002 have no lung compliance monitoring.
  Case 0003 total duration ≈ 4,394 seconds; intraop segment should be 40-95% of that.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD  = 60
CSV_MIN_SIZE    = 100
REPORT_MIN_SIZE = 300

# Respiratory mechanics track keywords
RESP_MECH_KEYWORDS = [
    "COMPLIANCE", "MAWP", "PPLAT", "PAMB",
    "AIRWAY_PRESSURE", "AIRWAY PRESSURE",
    "PLATEAU", "MEAN AIRWAY",
]

# Case 0003 total rows approximation (duration in seconds at 1 Hz)
FULL_CASE_ROWS_APPROX = 4394
INTRAOP_FRAC_MIN      = 0.35   # ~15 min minimum intraop (generous)
INTRAOP_FRAC_MAX      = 0.95

# Terms for clinical LPV assessment
LPV_TERMS = [
    "lung protective", "lung-protective", "lung protection",
    "tidal volume", "PEEP", "plateau", "compliance",
    "ventilator-induced", "vili", "low tidal",
    "protective ventilation", "alveolar recruitment",
    "pressure-controlled", "volume-controlled",
    "driving pressure", "transpulmonary",
]

# Report must mention case 0003 and respiratory parameters
RESP_PARAM_TERMS = [
    "compliance", "mawp", "pplat", "plateau", "airway pressure",
    "mean airway", "respiratory mechanics", "ventilat",
    "compliance track", "mbar",
]


def _safe_copy(copy_from_env, remote_path, local_path):
    try:
        copy_from_env(remote_path, local_path)
        return os.path.exists(local_path) and os.path.getsize(local_path) > 0
    except Exception as exc:
        logger.warning("copy_from_env(%s) failed: %s", remote_path, exc)
        return False


def verify_respiratory_mechanics_lung_protection_review(traj, env_info, task_info):
    """Multi-criterion verifier for respiratory_mechanics_lung_protection_review."""

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
        if _safe_copy(copy_from_env, r"C:\Users\Docker\task_result_resp_mechanics.json", tmp_json):
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
    csv_exists = False
    csv_size   = 0
    csv_header = ""
    csv_rows   = 0
    tmp_csv    = tempfile.mktemp(suffix=".csv")
    try:
        if _safe_copy(copy_from_env, r"C:\Users\Docker\Desktop\lung_protection_intraop.csv", tmp_csv):
            csv_exists = True
            csv_size   = os.path.getsize(tmp_csv)
            with open(tmp_csv, "r", encoding="utf-8", errors="replace") as f:
                csv_header = f.readline().strip()
            with open(tmp_csv, "r", encoding="utf-8", errors="replace") as f:
                csv_rows = sum(1 for _ in f) - 1  # subtract header
    except Exception as exc:
        logger.warning("CSV read error: %s", exc)
    finally:
        try:
            os.unlink(tmp_csv)
        except OSError:
            pass

    if not csv_exists and result_json.get("csv_exists"):
        csv_exists = True
        csv_size   = result_json.get("csv_size_bytes", 0)
        csv_header = result_json.get("csv_header", "")
        csv_rows   = result_json.get("csv_line_count", 1) - 1

    # ------------------------------------------------------------------
    # Independently copy report
    # ------------------------------------------------------------------
    report_exists  = False
    report_size    = 0
    report_content = ""
    tmp_report     = tempfile.mktemp(suffix=".txt")
    try:
        if _safe_copy(copy_from_env, r"C:\Users\Docker\Desktop\ventilation_review.txt", tmp_report):
            report_exists  = True
            report_size    = os.path.getsize(tmp_report)
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
    # Criterion 1 (25 pts): CSV has respiratory mechanics columns
    # ------------------------------------------------------------------
    header_upper = csv_header.upper()
    matched_resp = [kw for kw in RESP_MECH_KEYWORDS if kw in header_upper]

    if csv_exists and csv_size >= CSV_MIN_SIZE and matched_resp:
        score += 25
        feedback_parts.append(
            f"CSV has respiratory mechanics columns ({', '.join(matched_resp[:4])}, {csv_size:,} bytes)"
        )
    elif csv_exists and csv_size >= CSV_MIN_SIZE:
        score += 8
        feedback_parts.append(
            f"CSV exists ({csv_size:,} bytes) but no respiratory mechanics columns found "
            f"(header: {csv_header[:120]}) — may be wrong case"
        )
    elif csv_exists:
        score += 4
        feedback_parts.append(f"CSV found but too small ({csv_size} bytes)")
    else:
        feedback_parts.append("CSV (lung_protection_intraop.csv) not found")

    # ------------------------------------------------------------------
    # Criterion 2 (20 pts): CSV is intraop segment (not full recording)
    # ------------------------------------------------------------------
    if csv_exists and csv_rows > 0:
        frac = csv_rows / FULL_CASE_ROWS_APPROX
        if INTRAOP_FRAC_MIN <= frac < INTRAOP_FRAC_MAX:
            score += 20
            feedback_parts.append(
                f"CSV row count ({csv_rows:,}) consistent with intraop segment "
                f"({frac:.1%} of case 0003 full recording)"
            )
        elif frac >= INTRAOP_FRAC_MAX:
            score += 8
            feedback_parts.append(
                f"CSV rows ({csv_rows:,}) = {frac:.1%} of full case — appears to be full recording, "
                f"not intraop segment only (expected <{INTRAOP_FRAC_MAX:.0%})"
            )
        elif csv_rows > 100:
            score += 10
            feedback_parts.append(
                f"CSV rows ({csv_rows:,}) = {frac:.1%} of full case — shorter than expected intraop segment"
            )
        else:
            feedback_parts.append(f"CSV too few rows ({csv_rows}) to represent a surgical segment")
    elif csv_exists:
        feedback_parts.append("Could not determine CSV row count")
    else:
        feedback_parts.append("CSV not available for segment validation")

    report_lower = report_content.lower()

    # ------------------------------------------------------------------
    # Criterion 3 (20 pts): Ventilation report with substantial content
    # ------------------------------------------------------------------
    if report_exists and report_size >= REPORT_MIN_SIZE:
        score += 20
        feedback_parts.append(f"Ventilation report exists with substantial content ({report_size:,} bytes)")
    elif report_exists:
        score += 8
        feedback_parts.append(f"Ventilation report too brief ({report_size} bytes, need >={REPORT_MIN_SIZE})")
    else:
        feedback_parts.append("Ventilation review report not found")

    # ------------------------------------------------------------------
    # Criterion 4 (20 pts): Report identifies case 0003 + respiratory tracks
    # ------------------------------------------------------------------
    if report_content:
        has_0003 = "0003" in report_content
        matched_resp_terms = [t for t in RESP_PARAM_TERMS if t in report_lower]
        has_resp_terms = len(matched_resp_terms) >= 2

        if has_0003 and has_resp_terms:
            score += 20
            feedback_parts.append(
                f"Report identifies case 0003 with respiratory parameters "
                f"({', '.join(matched_resp_terms[:4])})"
            )
        elif has_0003:
            score += 10
            feedback_parts.append("Report mentions case 0003 but lacks respiratory parameter detail")
        elif has_resp_terms:
            score += 8
            feedback_parts.append(
                f"Report has respiratory terms ({', '.join(matched_resp_terms[:4])}) "
                f"but doesn't cite case 0003"
            )
        else:
            feedback_parts.append("Report doesn't identify case 0003 or its respiratory mechanics tracks")
    else:
        feedback_parts.append("No report content for case/track identification check")

    # ------------------------------------------------------------------
    # Criterion 5 (15 pts): Report contains LPV clinical assessment
    # ------------------------------------------------------------------
    if report_content:
        matched_lpv = [t for t in LPV_TERMS if t.lower() in report_lower]
        if len(matched_lpv) >= 3:
            score += 15
            feedback_parts.append(
                f"Report contains clinical LPV assessment (matched: {', '.join(matched_lpv[:5])})"
            )
        elif len(matched_lpv) >= 1:
            score += 7
            feedback_parts.append(
                f"Report has some LPV content ({', '.join(matched_lpv)}) — could be more clinically detailed"
            )
        else:
            feedback_parts.append("Report lacks clinical LPV assessment terminology")
    else:
        feedback_parts.append("No report content for LPV assessment check")

    # ------------------------------------------------------------------
    # Final verdict
    # ------------------------------------------------------------------
    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
