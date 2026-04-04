#!/usr/bin/env python3
"""Verifier for arterial_pressure_case_audit task.

Scoring (100 points total):
  Criterion 1 (25 pts): CSV export exists with ART waveform data in header
  Criterion 2 (20 pts): Audit report exists with substantial content (>=300 bytes)
  Criterion 3 (20 pts): Report correctly identifies case 0001 as having ART monitoring
  Criterion 4 (20 pts): Report notes excluded cases (0002 and/or 0003 lack ART)
  Criterion 5 (15 pts): Report contains clinical rationale with hemodynamic/monitoring terminology

Output gate: If neither CSV nor report exists, return score=0 immediately.
Pass threshold: 60 points

Why this is hard:
  - Agent must open all 3 case files to discover which has ART (not told in advance)
  - Only case 0001 has an invasive arterial line; 0002 has NIBP (non-invasive); 0003 has no BP
  - Agent must write a clinically substantive report, not just acknowledge the task
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# ---- Constants ----
CSV_MIN_SIZE        = 100    # bytes — real export is hundreds of KB
REPORT_MIN_SIZE     = 300    # bytes — meaningful audit document
PASS_THRESHOLD      = 60

# Arterial-pressure column keywords that appear in VitalDB CSV exports
ART_COLUMN_KEYWORDS = ["ART", "IBP", "ABP", "arterial"]

# Clinical terms expected in a credible audit report
CLINICAL_TERMS = [
    "hemodynamic", "haemodynamic",
    "mean arterial", "MAP", "blood pressure",
    "invasive", "arterial line", "A-line", "radial",
    "monitoring", "hypotension", "perfusion",
    "noncardiac", "anesthesia", "anaesthesia",
    "intraoperative", "intra-operative",
]

# Report must mention that other cases were reviewed and excluded
EXCLUSION_TERMS = [
    "no ART", "does not contain ART", "lacks ART", "without ART",
    "non-invasive", "NIBP", "excluded", "not eligible",
    "not included", "does not have", "no invasive",
    "no arterial", "absent",
]


def _safe_copy(copy_from_env, remote_path, local_path):
    try:
        copy_from_env(remote_path, local_path)
        return os.path.exists(local_path) and os.path.getsize(local_path) > 0
    except Exception as exc:
        logger.warning("copy_from_env(%s) failed: %s", remote_path, exc)
        return False


def verify_arterial_pressure_case_audit(traj, env_info, task_info):
    """Multi-criterion verifier for the arterial_pressure_case_audit task."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # ------------------------------------------------------------------
    # Collect export JSON (supplemental signal — primary checks are file-based)
    # ------------------------------------------------------------------
    result_json = {}
    tmp_json = tempfile.mktemp(suffix=".json")
    try:
        if _safe_copy(copy_from_env, r"C:\Users\Docker\task_result_art_audit.json", tmp_json):
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
    # Independently copy and inspect the CSV export
    # ------------------------------------------------------------------
    csv_size = 0
    csv_exists = False
    csv_header = ""
    tmp_csv = tempfile.mktemp(suffix=".csv")
    try:
        if _safe_copy(copy_from_env, r"C:\Users\Docker\Desktop\art_case_export.csv", tmp_csv):
            csv_size = os.path.getsize(tmp_csv)
            csv_exists = True
            try:
                with open(tmp_csv, "r", encoding="utf-8", errors="replace") as f:
                    csv_header = f.readline().strip()
            except Exception:
                pass
    finally:
        try:
            os.unlink(tmp_csv)
        except OSError:
            pass

    # Fallback to export-JSON values if direct copy was not available
    if not csv_exists and result_json.get("csv_exists"):
        csv_exists = True
        csv_size   = result_json.get("csv_size_bytes", 0)
        csv_header = result_json.get("csv_header", "")

    # ------------------------------------------------------------------
    # Independently copy and read the audit report
    # ------------------------------------------------------------------
    report_size = 0
    report_exists = False
    report_content = ""
    tmp_report = tempfile.mktemp(suffix=".txt")
    try:
        if _safe_copy(copy_from_env, r"C:\Users\Docker\Desktop\art_audit_report.txt", tmp_report):
            report_size = os.path.getsize(tmp_report)
            report_exists = True
            try:
                with open(tmp_report, "r", encoding="utf-8", errors="replace") as f:
                    report_content = f.read()
            except Exception:
                pass
    finally:
        try:
            os.unlink(tmp_report)
        except OSError:
            pass

    if not report_exists and result_json.get("report_exists"):
        report_exists = True
        report_size   = result_json.get("report_size_bytes", 0)
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
    # Criterion 1 (25 pts): CSV with ART waveform columns exists
    # ------------------------------------------------------------------
    header_upper = csv_header.upper()
    has_art_col = any(kw.upper() in header_upper for kw in ART_COLUMN_KEYWORDS)

    if csv_exists and csv_size >= CSV_MIN_SIZE and has_art_col:
        score += 25
        feedback_parts.append(f"CSV export with ART column found ({csv_size:,} bytes)")
    elif csv_exists and csv_size >= CSV_MIN_SIZE:
        # CSV exists but no ART column — wrong case was exported
        score += 10
        feedback_parts.append(
            f"CSV exists ({csv_size:,} bytes) but no ART column in header — wrong case exported? "
            f"(header: {csv_header[:120]})"
        )
    elif csv_exists:
        score += 5
        feedback_parts.append(f"CSV exists but too small ({csv_size} bytes) or no ART column")
    else:
        feedback_parts.append("CSV export not found at expected path")

    # ------------------------------------------------------------------
    # Criterion 2 (20 pts): Audit report exists with substantial content
    # ------------------------------------------------------------------
    if report_exists and report_size >= REPORT_MIN_SIZE:
        score += 20
        feedback_parts.append(f"Audit report exists with substantial content ({report_size:,} bytes)")
    elif report_exists:
        score += 8
        feedback_parts.append(f"Audit report exists but too brief ({report_size} bytes, need >={REPORT_MIN_SIZE})")
    else:
        feedback_parts.append("Audit report not found at expected path")

    report_lower = report_content.lower()

    # ------------------------------------------------------------------
    # Criterion 3 (20 pts): Report identifies case 0001 as the ART case
    # ------------------------------------------------------------------
    if report_content:
        has_0001 = "0001" in report_content
        # Also accept generic "case 1" or "first case" references
        has_art_mention = any(
            kw.lower() in report_lower
            for kw in ["ART", "arterial", "invasive", "a-line"]
        )
        if has_0001 and has_art_mention:
            score += 20
            feedback_parts.append("Report correctly links case 0001 to ART monitoring")
        elif has_0001:
            score += 10
            feedback_parts.append("Report mentions case 0001 but unclear ART association")
        elif has_art_mention:
            score += 8
            feedback_parts.append("Report mentions ART/arterial but does not cite case 0001")
        else:
            feedback_parts.append("Report does not identify case 0001 as having ART")
    else:
        feedback_parts.append("No report content available for case-identification check")

    # ------------------------------------------------------------------
    # Criterion 4 (20 pts): Report notes excluded cases (0002/0003 lack ART)
    # ------------------------------------------------------------------
    if report_content:
        mentions_0002 = "0002" in report_content
        mentions_0003 = "0003" in report_content
        has_exclusion = any(term.lower() in report_lower for term in EXCLUSION_TERMS)

        if (mentions_0002 or mentions_0003) and has_exclusion:
            score += 20
            cases_noted = ", ".join(
                c for c in ["0002", "0003"] if c in report_content
            )
            feedback_parts.append(f"Report notes excluded cases ({cases_noted}) with appropriate exclusion language")
        elif mentions_0002 or mentions_0003:
            score += 10
            cases_noted = ", ".join(
                c for c in ["0002", "0003"] if c in report_content
            )
            feedback_parts.append(f"Report mentions {cases_noted} but lacks explicit exclusion rationale")
        elif has_exclusion:
            score += 8
            feedback_parts.append("Report has exclusion language but does not cite specific case numbers")
        else:
            feedback_parts.append("Report does not address excluded cases (0002/0003 without ART)")
    else:
        feedback_parts.append("No report content available for exclusion check")

    # ------------------------------------------------------------------
    # Criterion 5 (15 pts): Report contains clinical rationale
    # ------------------------------------------------------------------
    if report_content:
        matched_clinical = [t for t in CLINICAL_TERMS if t.lower() in report_lower]
        if len(matched_clinical) >= 3:
            score += 15
            feedback_parts.append(
                f"Report contains clinical rationale (matched terms: {', '.join(matched_clinical[:5])})"
            )
        elif len(matched_clinical) >= 1:
            score += 7
            feedback_parts.append(
                f"Report has some clinical content ({', '.join(matched_clinical)}) "
                f"but lacks depth (need >=3 distinct clinical terms)"
            )
        else:
            feedback_parts.append("Report lacks clinical rationale (no hemodynamic/monitoring terminology found)")
    else:
        feedback_parts.append("No report content available for clinical-rationale check")

    # ------------------------------------------------------------------
    # Final verdict
    # ------------------------------------------------------------------
    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
