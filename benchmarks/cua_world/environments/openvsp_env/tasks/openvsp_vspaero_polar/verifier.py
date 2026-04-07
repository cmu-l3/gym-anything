"""
Verifier for openvsp_vspaero_polar task.

Checks:
  1. VSPAero .polar output file exists with >= 7 data rows (40 pts)
  2. Report file /home/ga/Desktop/vspaero_report.txt exists (10 pts)
  3. Report contains a numeric L/D value in the physically plausible range [3, 35] (25 pts)
  4. Report mentions an alpha value in range [-5, 15] for max L/D (25 pts)

Pass threshold: 60.

Physical context: eCRM-001 is a research transport aircraft. Its max L/D at Mach 0.2
is expected to be in the range 8–20, at an alpha somewhere around 2–8 degrees.
The verifier uses wide tolerances to accept any reasonable analysis.
"""

import json
import os
import re
import tempfile


def _extract_numeric(text: str, keywords: list, value_range: tuple) -> float | None:
    """
    Search for a numeric value near any of the keywords in text.
    Returns the first value found within value_range.
    """
    # Patterns: keyword followed by colon/equals and a number
    patterns = [
        r'(?:' + '|'.join(re.escape(k) for k in keywords) + r')[^\d\-\.]*([+-]?\d+\.?\d*)',
        r'([+-]?\d+\.?\d*)[^\d]*(?:' + '|'.join(re.escape(k) for k in keywords) + r')',
    ]
    for pattern in patterns:
        for m in re.finditer(pattern, text, re.IGNORECASE):
            try:
                val = float(m.group(1))
                if value_range[0] <= val <= value_range[1]:
                    return val
            except (ValueError, IndexError):
                continue
    return None


def verify_openvsp_vspaero_polar(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_vspaero_polar_result.json"
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

    # --- Check 1: Polar file exists with >= 7 data rows (40 pts) ---
    polar_exists = data.get("polar_exists", False)
    polar_rows = data.get("polar_data_rows", 0)

    if not polar_exists:
        feedback_parts.append("VSPAero .polar file not found — analysis may not have run (+0).")
    elif polar_rows < 7:
        partial = min(20, polar_rows * 3)
        score += partial
        feedback_parts.append(
            f"Polar file found but only {polar_rows} data rows (need >= 7) (+{partial})."
        )
    else:
        score += 40
        feedback_parts.append(
            f"Polar file found with {polar_rows} data rows (+40)."
        )

    # --- Check 2: Report file exists (10 pts) ---
    report_exists = data.get("report_exists", False)
    report_content = data.get("report_content", "")
    # Unescape
    report_content = report_content.replace("\\n", "\n").replace("\\t", "\t")

    if not report_exists:
        feedback_parts.append("Report file /home/ga/Desktop/vspaero_report.txt not found (+0).")
    else:
        score += 10
        feedback_parts.append("Report file exists (+10).")

        # --- Check 3: Report contains L/D in [3, 35] (25 pts) ---
        ld_val = _extract_numeric(
            report_content,
            keywords=["L/D", "LD", "lift-to-drag", "lift to drag", "max l/d", "maximum l/d"],
            value_range=(3.0, 35.0),
        )
        if ld_val is not None:
            score += 25
            feedback_parts.append(f"Report contains L/D value {ld_val:.2f} in [3, 35] (+25).")
        else:
            # Try any number in the report in that range as fallback
            numbers = re.findall(r'[+-]?\d+\.?\d*', report_content)
            found_ld = False
            for n in numbers:
                try:
                    v = float(n)
                    if 3.0 <= v <= 35.0:
                        score += 15
                        feedback_parts.append(
                            f"Report contains number {v:.2f} in L/D range [3, 35] (partial, +15)."
                        )
                        found_ld = True
                        break
                except ValueError:
                    pass
            if not found_ld:
                feedback_parts.append("Report does not contain a recognizable L/D value in [3, 35] (+0).")

        # --- Check 4: Report mentions alpha at max L/D in [-5, 15] (25 pts) ---
        alpha_val = _extract_numeric(
            report_content,
            keywords=["alpha", "angle of attack", "AoA", "maximum", "max", "optimal"],
            value_range=(-5.0, 15.0),
        )
        if alpha_val is not None:
            score += 25
            feedback_parts.append(f"Report mentions alpha {alpha_val:.1f} deg in [-5, 15] (+25).")
        else:
            feedback_parts.append("Report does not contain a recognizable alpha value in [-5, 15] (+0).")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
