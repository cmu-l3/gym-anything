"""
Verifier for openvsp_degengeom_analysis task.

Checks:
  1. DegenGeom CSV exported to correct path (30 pts)
  2. Report file exists with content (15 pts)
  3. Report contains wingspan in [5, 20] m (20 pts)
  4. Report contains aspect ratio in [4, 20] (20 pts)
  5. Report contains MAC in [0.5, 5.0] m (15 pts)

Pass threshold: 60.

Physical context for eCRM-001:
  The eCRM-001 has a wing with span ~11 m, AR ~10, MAC ~1.1 m (approximate).
  Wide tolerances accept any reasonable output from the DegenGeom tool.
"""

import json
import os
import re
import tempfile


def _find_number_in_range(text: str, lo: float, hi: float,
                          context_keywords: list | None = None) -> float | None:
    """
    Find a number in text that falls within [lo, hi].
    If context_keywords provided, prefers numbers near those keywords.
    """
    text_lower = text.lower()

    if context_keywords:
        for kw in context_keywords:
            idx = text_lower.find(kw.lower())
            if idx >= 0:
                # Search in a window around the keyword
                window = text[max(0, idx - 10): idx + 80]
                nums = re.findall(r'[+-]?\d+\.?\d*', window)
                for n in nums:
                    try:
                        v = float(n)
                        if lo <= v <= hi:
                            return v
                    except ValueError:
                        pass

    # Fallback: any number in range
    for n in re.findall(r'[+-]?\d+\.?\d*', text):
        try:
            v = float(n)
            if lo <= v <= hi:
                return v
        except ValueError:
            pass
    return None


def verify_openvsp_degengeom_analysis(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_degengeom_analysis_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_file, local_tmp)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found — export script may not have run: {e}",
        }

    with open(local_tmp, "r") as f:
        data = json.load(f)
    os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- Check 1: DegenGeom CSV exists (30 pts) ---
    csv_exists = data.get("csv_exists", False)
    csv_size = data.get("csv_size", 0)
    csv_first = data.get("csv_first_lines", "").replace("\\n", "\n")

    if not csv_exists:
        feedback_parts.append("DegenGeom CSV not found — analysis may not have run (+0).")
    elif csv_size < 100:
        feedback_parts.append(f"DegenGeom CSV found but too small ({csv_size} bytes) (+0).")
    else:
        score += 30
        feedback_parts.append(
            f"DegenGeom CSV found ({csv_size} bytes, {data.get('csv_row_count', 0)} rows) (+30)."
        )

    # --- Check 2: Report exists (15 pts) ---
    report_exists = data.get("report_exists", False)
    report_content = data.get("report_content", "").replace("\\n", "\n").replace("\\t", "\t")

    if not report_exists or len(report_content.strip()) < 20:
        feedback_parts.append("Report /home/ga/Desktop/degengeom_report.txt not found or empty (+0).")
    else:
        score += 15
        feedback_parts.append("Report file found (+15).")

        # --- Check 3: Report contains wingspan in [5, 20] m (20 pts) ---
        span_val = _find_number_in_range(
            report_content, lo=5.0, hi=20.0,
            context_keywords=["span", "wingspan", "wing span"]
        )
        if span_val is not None:
            score += 20
            feedback_parts.append(f"Report: wingspan {span_val:.2f} m in [5, 20] (+20).")
        else:
            feedback_parts.append("Report: no wingspan value in [5, 20] m (+0).")

        # --- Check 4: Report contains aspect ratio in [4, 20] (20 pts) ---
        ar_val = _find_number_in_range(
            report_content, lo=4.0, hi=20.0,
            context_keywords=["aspect ratio", "ar", "a/r", "aspect"]
        )
        if ar_val is not None:
            score += 20
            feedback_parts.append(f"Report: aspect ratio {ar_val:.2f} in [4, 20] (+20).")
        else:
            feedback_parts.append("Report: no aspect ratio value in [4, 20] (+0).")

        # --- Check 5: Report contains MAC in [0.5, 5.0] m (15 pts) ---
        mac_val = _find_number_in_range(
            report_content, lo=0.5, hi=5.0,
            context_keywords=["mac", "mean aerodynamic chord", "mean chord", "chord"]
        )
        if mac_val is not None:
            score += 15
            feedback_parts.append(f"Report: MAC {mac_val:.3f} m in [0.5, 5.0] (+15).")
        else:
            feedback_parts.append("Report: no MAC value in [0.5, 5.0] m (+0).")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
