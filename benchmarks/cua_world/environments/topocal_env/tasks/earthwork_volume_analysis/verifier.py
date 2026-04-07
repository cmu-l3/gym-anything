#!/usr/bin/env python3
"""
Verifier for earthwork_volume_analysis task.

Scoring (total 100 pts, pass threshold 60):
  30 pts — volume_report.txt exists AND was created after task start
  20 pts — report has at least 5 lines of substantive content
  25 pts — report has >=3 lines and contains a plausible volume number (>=100)
  25 pts — report mentions both cut/desmonte AND fill/relleno (any language)
"""

import json
import re
from datetime import datetime, timezone


def _parse_dt(s):
    """Parse an ISO-8601 datetime string, return UTC-aware datetime or None."""
    if not s:
        return None
    s = s.strip()
    # Python < 3.11 fromisoformat doesn't handle trailing Z
    s = s.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(s)
    except Exception:
        return None


def verify_earthwork_volume_analysis(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result_path = (
        task_info.get("metadata", {}).get("result_file")
        or "C:\\Users\\Docker\\earthwork_volume_analysis_result.json"
    )

    # Pull the result JSON from the VM
    import tempfile, os
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        env_info["copy_from_env"](result_path, tmp.name)
    except Exception as exc:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {exc}",
        }

    try:
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as exc:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file is not valid JSON: {exc}",
        }
    finally:
        os.unlink(tmp.name)

    start_dt = _parse_dt(result.get("start_time", ""))
    report_exists = bool(result.get("report_exists"))
    report_mod_time = _parse_dt(result.get("report_mod_time", ""))
    report_size = int(result.get("report_size_bytes") or 0)
    report_lines = int(result.get("report_lines") or 0)

    # Unescape stored content (PowerShell double-escapes newlines in JSON strings)
    raw_content = result.get("report_content", "") or ""
    content = raw_content.replace("\\n", "\n").replace("\\t", "\t")
    content_lower = content.lower()

    # ── Criterion 1: file exists and was created after task start (30 pts) ──
    file_new = False
    if report_exists and report_mod_time and start_dt:
        # Normalise both to UTC for comparison
        if report_mod_time.tzinfo is None:
            report_mod_time = report_mod_time.replace(tzinfo=timezone.utc)
        if start_dt.tzinfo is None:
            start_dt = start_dt.replace(tzinfo=timezone.utc)
        file_new = report_mod_time > start_dt

    if report_exists and file_new:
        score += 30
        feedback_parts.append("PASS(30): volume_report.txt exists and is newer than task start")
    elif report_exists:
        score += 10
        feedback_parts.append("PARTIAL(10): volume_report.txt exists but may predate task start")
    else:
        feedback_parts.append("FAIL(0): volume_report.txt not found")

    # ── Criterion 2: substantive content — at least 5 non-blank lines (20 pts) ──
    non_blank_lines = [l for l in content.split("\n") if l.strip()]
    if len(non_blank_lines) >= 5:
        score += 20
        feedback_parts.append(f"PASS(20): report has {len(non_blank_lines)} non-blank lines")
    elif len(non_blank_lines) >= 2:
        score += 8
        feedback_parts.append(f"PARTIAL(8): report has only {len(non_blank_lines)} non-blank lines")
    else:
        feedback_parts.append(f"FAIL(0): report has too little content ({len(non_blank_lines)} lines)")

    # ── Criterion 3: at least one plausible volume number (25 pts) ──
    # A "plausible" volume is a number >= 100 appearing on a line with
    # volume-related context (m3, volume, cut, fill, etc.). This prevents
    # elevation or date numbers from triggering this criterion.
    vol_line_keywords = [
        "volume", "volumen", "m3", "m³", "cubic", "cubico", "cúbico",
        "cut", "corte", "desmonte", "fill", "relleno", "net", "neto",
    ]
    has_volume_numbers = False
    if len(non_blank_lines) >= 3:
        for line in non_blank_lines:
            line_lower = line.lower()
            if any(kw in line_lower for kw in vol_line_keywords):
                for n in re.findall(r"[\d]+(?:[.,]\d+)*", line):
                    try:
                        v = float(n.replace(",", ""))
                        if v >= 100.0:
                            has_volume_numbers = True
                            break
                    except ValueError:
                        pass
            if has_volume_numbers:
                break

    if has_volume_numbers:
        score += 25
        feedback_parts.append("PASS(25): report contains plausible numeric volume value(s)")
    else:
        feedback_parts.append("FAIL(0): no plausible volume numbers found in report")

    # ── Criterion 4: mentions cut AND fill (25 pts) ──
    cut_keywords  = ["cut", "corte", "desmonte", "excavacion", "excavación"]
    fill_keywords = ["fill", "relleno", "terrapl", "terraplén"]

    has_cut  = any(kw in content_lower for kw in cut_keywords)
    has_fill = any(kw in content_lower for kw in fill_keywords)

    if has_cut and has_fill:
        score += 25
        feedback_parts.append("PASS(25): report mentions both cut and fill volumes")
    elif has_cut or has_fill:
        score += 10
        which = "cut/corte" if has_cut else "fill/relleno"
        feedback_parts.append(f"PARTIAL(10): report mentions {which} but not the other")
    else:
        feedback_parts.append("FAIL(0): report does not mention cut or fill volumes")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
