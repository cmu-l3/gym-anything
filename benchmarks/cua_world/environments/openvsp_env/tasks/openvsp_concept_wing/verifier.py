"""
Verifier for openvsp_concept_wing task.

Checks the agent created a valid OpenVSP concept model with:
  1. File exists and is valid XML: 10 pts
  2. WingGeom component present: 20 pts
  3. TotalSpan in [10.5, 14.5] m (±15% around 12.40 m): 25 pts
  4. Any WingSect Dihedral in [2.0, 9.0] deg: 25 pts
  5. Any non-wing component (fuselage/pod): 20 pts

Pass threshold: 60 (wing geometry must be correct).
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET


# Specification values and tolerances
SPEC_SPAN = 12.40   # meters
SPAN_RANGE = (10.5, 14.5)   # ±15% of spec
DIHEDRAL_RANGE = (2.0, 9.0)  # degrees


def _find_param_values_by_tag(content: str, tag: str) -> list[float]:
    """Find all Value attributes for elements with the given tag name."""
    pattern = rf'<{tag}\s+Value="([^"]+)"'
    vals = []
    for m in re.finditer(pattern, content):
        try:
            vals.append(float(m.group(1)))
        except ValueError:
            pass
    return vals


def verify_openvsp_concept_wing(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_concept_wing_result.json"
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

    # --- Check 1: File exists (10 pts) ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "concept_wing.vsp3 not found at /home/ga/Documents/OpenVSP/concept_wing.vsp3.",
        }

    content = data.get("file_content", "")
    content = content.replace("\\n", "\n").replace("\\t", "\t")

    try:
        ET.fromstring(content)
        score += 10
        feedback_parts.append("File is valid XML (+10).")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"concept_wing.vsp3 is not valid XML: {e}",
        }

    # --- Check 2: WingGeom component present (20 pts) ---
    has_wing = "<WingGeom>" in content or "WingGeom" in content
    if has_wing:
        score += 20
        feedback_parts.append("WingGeom component found (+20).")
    else:
        feedback_parts.append("No WingGeom component found in model (+0).")

    # --- Check 3: TotalSpan in [10.5, 14.5] m (25 pts) ---
    span_vals = _find_param_values_by_tag(content, "TotalSpan")
    best_span = None
    for sv in span_vals:
        if SPAN_RANGE[0] <= sv <= SPAN_RANGE[1]:
            best_span = sv
            break

    if best_span is not None:
        score += 25
        feedback_parts.append(
            f"TotalSpan = {best_span:.2f} m, within [{SPAN_RANGE[0]}, {SPAN_RANGE[1]}] m (+25)."
        )
    elif span_vals:
        closest = min(span_vals, key=lambda v: abs(v - SPEC_SPAN))
        if abs(closest - SPEC_SPAN) < SPEC_SPAN * 0.30:
            score += 10
            feedback_parts.append(
                f"TotalSpan = {closest:.2f} m, outside tolerance but close (+10)."
            )
        else:
            feedback_parts.append(
                f"TotalSpan values found: {span_vals} — none within [{SPAN_RANGE[0]}, {SPAN_RANGE[1]}] m (+0)."
            )
    else:
        feedback_parts.append("No TotalSpan parameter found in model (+0).")

    # --- Check 4: WingSect Dihedral in [2.0, 9.0] deg (25 pts) ---
    dihedral_vals = _find_param_values_by_tag(content, "Dihedral")
    best_dihedral = None
    for dv in dihedral_vals:
        if DIHEDRAL_RANGE[0] <= dv <= DIHEDRAL_RANGE[1]:
            best_dihedral = dv
            break

    if best_dihedral is not None:
        score += 25
        feedback_parts.append(
            f"Wing Dihedral = {best_dihedral:.1f} deg, within [{DIHEDRAL_RANGE[0]}, {DIHEDRAL_RANGE[1]}] (+25)."
        )
    elif dihedral_vals:
        feedback_parts.append(
            f"Dihedral values found: {dihedral_vals[:5]} — none within [{DIHEDRAL_RANGE[0]}, {DIHEDRAL_RANGE[1]}] (+0)."
        )
    else:
        feedback_parts.append("No Dihedral parameter found in model (+0).")

    # --- Check 5: Non-wing component (fuselage/pod) present (20 pts) ---
    has_fuselage = (
        "FuselageGeom" in content
        or "PodGeom" in content
        or "BodyOfRevolutionGeom" in content
    )
    if has_fuselage:
        score += 20
        feedback_parts.append("Fuselage/Pod component found (+20).")
    else:
        feedback_parts.append("No FuselageGeom or PodGeom found — fuselage required (+0).")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
