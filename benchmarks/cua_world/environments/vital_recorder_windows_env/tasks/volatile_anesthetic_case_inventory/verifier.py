#!/usr/bin/env python3
"""Verifier for volatile_anesthetic_case_inventory task.

Scoring (100 points total):
  Criterion 1 (25 pts): CSV for case 0001 exists with INSP_SEVO/EXP_SEVO in header
  Criterion 2 (25 pts): CSV for case 0003 exists with INSP_SEVO/EXP_SEVO in header
  Criterion 3 (20 pts): Inventory report exists with substantial content (>=400 bytes)
  Criterion 4 (15 pts): Report identifies case 0002 as lacking sevoflurane data
  Criterion 5 (15 pts): Report contains clinical content about volatile anesthetic monitoring

Output gate: score=0 if no output files exist at all.
Pass threshold: 60 points

Ground truth:
  Cases 0001 and 0003 have INSP_SEVO and EXP_SEVO channels.
  Case 0002 has cardiovascular/ventilation tracks ONLY — no anesthetic agent monitoring.
  The agent must open all three files to discover this.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD   = 60
CSV_MIN_SIZE     = 100
REPORT_MIN_SIZE  = 400

# Sevoflurane track keywords in VitalDB CSV headers
SEVO_KEYWORDS = ["INSP_SEVO", "EXP_SEVO", "SEVO", "SEVOFLURANE", "SEVO_INSP", "SEVO_EXP"]

# Clinical terms for anesthetic monitoring
CLINICAL_TERMS = [
    "sevoflurane", "inspired", "expired", "alveolar",
    "MAC", "minimum alveolar", "anesthetic", "anaesthetic",
    "volatile", "washout", "uptake", "concentration",
    "depth of anesthesia", "anesthetic agent",
    "induction", "maintenance", "emergence",
]

# Exclusion language for case 0002
EXCLUSION_TERMS = [
    "no sevo", "does not contain", "lacking", "without", "absent",
    "not available", "excluded", "not eligible", "no volatile",
    "no anesthetic agent", "cardiovascular only", "does not have",
    "no insp", "no exp", "not included",
]


def _safe_copy(copy_from_env, remote_path, local_path):
    try:
        copy_from_env(remote_path, local_path)
        return os.path.exists(local_path) and os.path.getsize(local_path) > 0
    except Exception as exc:
        logger.warning("copy_from_env(%s) failed: %s", remote_path, exc)
        return False


def _check_csv_for_sevo(copy_from_env, remote_path, label):
    """
    Copy a CSV from VM and check its header for SEVO columns.
    Returns (exists: bool, size: int, header: str, has_sevo: bool).
    """
    tmp = tempfile.mktemp(suffix=".csv")
    try:
        if _safe_copy(copy_from_env, remote_path, tmp):
            size = os.path.getsize(tmp)
            with open(tmp, "r", encoding="utf-8", errors="replace") as f:
                header = f.readline().strip()
            header_upper = header.upper()
            has_sevo = any(kw in header_upper for kw in SEVO_KEYWORDS)
            logger.info("%s: size=%d, has_sevo=%s, header=%s", label, size, has_sevo, header[:120])
            return True, size, header, has_sevo
        return False, 0, "", False
    except Exception as exc:
        logger.warning("CSV check for %s failed: %s", label, exc)
        return False, 0, "", False
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def verify_volatile_anesthetic_case_inventory(traj, env_info, task_info):
    """Multi-criterion verifier for volatile_anesthetic_case_inventory."""

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
        if _safe_copy(copy_from_env, r"C:\Users\Docker\task_result_sevo_inventory.json", tmp_json):
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
    # Inspect CSV for case 0001
    # ------------------------------------------------------------------
    csv0001_exists, csv0001_size, csv0001_header, csv0001_has_sevo = _check_csv_for_sevo(
        copy_from_env,
        r"C:\Users\Docker\Desktop\case_0001_sevo.csv",
        "CSV-0001"
    )
    # Fallback to export JSON
    if not csv0001_exists and result_json.get("csv_0001_exists"):
        csv0001_exists   = True
        csv0001_size     = result_json.get("csv_0001_size_bytes", 0)
        csv0001_header   = result_json.get("csv_0001_header", "")
        csv0001_has_sevo = any(kw in csv0001_header.upper() for kw in SEVO_KEYWORDS)

    # ------------------------------------------------------------------
    # Inspect CSV for case 0003
    # ------------------------------------------------------------------
    csv0003_exists, csv0003_size, csv0003_header, csv0003_has_sevo = _check_csv_for_sevo(
        copy_from_env,
        r"C:\Users\Docker\Desktop\case_0003_sevo.csv",
        "CSV-0003"
    )
    if not csv0003_exists and result_json.get("csv_0003_exists"):
        csv0003_exists   = True
        csv0003_size     = result_json.get("csv_0003_size_bytes", 0)
        csv0003_header   = result_json.get("csv_0003_header", "")
        csv0003_has_sevo = any(kw in csv0003_header.upper() for kw in SEVO_KEYWORDS)

    # ------------------------------------------------------------------
    # Inspect report
    # ------------------------------------------------------------------
    report_exists  = False
    report_size    = 0
    report_content = ""
    tmp_report     = tempfile.mktemp(suffix=".txt")
    try:
        if _safe_copy(copy_from_env, r"C:\Users\Docker\Desktop\anesthetic_inventory.txt", tmp_report):
            report_exists = True
            report_size   = os.path.getsize(tmp_report)
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
    if not csv0001_exists and not csv0003_exists and not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output gate: no output files found at all. Score=0.",
        }

    # ------------------------------------------------------------------
    # Criterion 1 (25 pts): CSV for case 0001 with SEVO columns
    # ------------------------------------------------------------------
    if csv0001_exists and csv0001_size >= CSV_MIN_SIZE and csv0001_has_sevo:
        score += 25
        feedback_parts.append(f"CSV-0001 has SEVO columns ({csv0001_size:,} bytes)")
    elif csv0001_exists and csv0001_size >= CSV_MIN_SIZE:
        score += 10
        feedback_parts.append(
            f"CSV-0001 exists ({csv0001_size:,} bytes) but no SEVO column detected "
            f"(header: {csv0001_header[:100]})"
        )
    elif csv0001_exists:
        score += 5
        feedback_parts.append(f"CSV-0001 found but too small ({csv0001_size} bytes)")
    else:
        feedback_parts.append("CSV for case 0001 (case_0001_sevo.csv) not found")

    # ------------------------------------------------------------------
    # Criterion 2 (25 pts): CSV for case 0003 with SEVO columns
    # ------------------------------------------------------------------
    if csv0003_exists and csv0003_size >= CSV_MIN_SIZE and csv0003_has_sevo:
        score += 25
        feedback_parts.append(f"CSV-0003 has SEVO columns ({csv0003_size:,} bytes)")
    elif csv0003_exists and csv0003_size >= CSV_MIN_SIZE:
        score += 10
        feedback_parts.append(
            f"CSV-0003 exists ({csv0003_size:,} bytes) but no SEVO column detected "
            f"(header: {csv0003_header[:100]})"
        )
    elif csv0003_exists:
        score += 5
        feedback_parts.append(f"CSV-0003 found but too small ({csv0003_size} bytes)")
    else:
        feedback_parts.append("CSV for case 0003 (case_0003_sevo.csv) not found")

    report_lower = report_content.lower()

    # ------------------------------------------------------------------
    # Criterion 3 (20 pts): Inventory report with substantial content
    # ------------------------------------------------------------------
    if report_exists and report_size >= REPORT_MIN_SIZE:
        score += 20
        feedback_parts.append(f"Inventory report exists with substantial content ({report_size:,} bytes)")
    elif report_exists:
        score += 8
        feedback_parts.append(f"Inventory report too brief ({report_size} bytes, need >={REPORT_MIN_SIZE})")
    else:
        feedback_parts.append("Inventory report (anesthetic_inventory.txt) not found")

    # ------------------------------------------------------------------
    # Criterion 4 (15 pts): Report identifies case 0002 as lacking sevo
    # ------------------------------------------------------------------
    if report_content:
        has_0002 = "0002" in report_content
        has_exclusion = any(term in report_lower for term in EXCLUSION_TERMS)
        no_sevo_in_context = (
            "0002" in report_content and
            any(kw in report_lower for kw in ["no sevo", "not contain sevo", "sevo" + "flurane",
                                               "without sevo", "lacking sevo", "no volatile",
                                               "does not", "excluded", "not eligible",
                                               "absent"])
        )
        if has_0002 and has_exclusion:
            score += 15
            feedback_parts.append("Report correctly notes case 0002 lacks sevoflurane with exclusion language")
        elif has_0002:
            score += 7
            feedback_parts.append("Report mentions case 0002 but unclear exclusion rationale for sevo")
        elif has_exclusion:
            score += 5
            feedback_parts.append("Report has exclusion language but doesn't cite case 0002 explicitly")
        else:
            feedback_parts.append("Report does not address case 0002 as the non-sevo case")
    else:
        feedback_parts.append("No report content to check for case-0002 exclusion")

    # ------------------------------------------------------------------
    # Criterion 5 (15 pts): Report has clinical anesthetic monitoring content
    # ------------------------------------------------------------------
    if report_content:
        matched = [t for t in CLINICAL_TERMS if t.lower() in report_lower]
        if len(matched) >= 4:
            score += 15
            feedback_parts.append(
                f"Report has substantive clinical anesthetic content (matched: {', '.join(matched[:6])})"
            )
        elif len(matched) >= 2:
            score += 8
            feedback_parts.append(
                f"Report has some clinical content ({', '.join(matched)}) — could be more detailed"
            )
        elif len(matched) == 1:
            score += 4
            feedback_parts.append(f"Report mentions '{matched[0]}' but lacks clinical depth")
        else:
            feedback_parts.append("Report lacks clinical content about volatile anesthetic monitoring")
    else:
        feedback_parts.append("No report content for clinical terminology check")

    # ------------------------------------------------------------------
    # Final verdict
    # ------------------------------------------------------------------
    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
