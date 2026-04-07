"""
Verifier for openvsp_wing_error_fix task.

Checks that the agent corrected three injected errors in the Cessna-210 NormalWing:
  1. Root section Sweep (ID: FRLKOYFIAPQ) — target range: [-3, +8] degrees
  2. Root section Twist (ID: KCGUTVSHARU) — target range: [-1, +6] degrees
  3. Outboard section Dihedral (ID: SURVMYSOGIV) — target range: [0, +8] degrees

Scoring (100 points total):
  - File exists and is valid XML: 10 pts
  - Root Sweep corrected (was 42 deg, must be in [-3, 8]): 30 pts
  - Root Twist corrected (was 22 deg, must be in [-1, 6]): 30 pts
  - Outboard Dihedral corrected (was -25 deg, must be in [0, 8]): 30 pts

Pass threshold: 70 (all three corrections required for pass).
"""

import json
import re
import xml.etree.ElementTree as ET
import tempfile
import os


# Injected error values — must NOT be present in the corrected file
INJECTED_SWEEP = 42.0
INJECTED_TWIST = 22.0
INJECTED_DIHEDRAL = -25.0

# Correct ranges (inclusive)
SWEEP_RANGE = (-3.0, 8.0)     # Leading-edge sweep for Cessna 210 root section
TWIST_RANGE = (-1.0, 6.0)     # Washout twist for root section
DIHEDRAL_RANGE = (0.0, 8.0)   # Positive dihedral for outboard section

# Parameter IDs in the NormalWing XSec elements
SWEEP_ID = "FRLKOYFIAPQ"
TWIST_ID = "KCGUTVSHARU"
DIHEDRAL_ID = "SURVMYSOGIV"


def _parse_param_value(content: str, param_id: str) -> float | None:
    """Extract the Value of an XML element with a given ID attribute."""
    pattern = rf'<\w+\s+Value="([^"]+)"\s+ID="{param_id}"'
    m = re.search(pattern, content)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            return None
    return None


def verify_openvsp_wing_error_fix(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_wing_error_fix_result.json"
    )

    # Pull result file from VM
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
            "feedback": "cessna210_corrupt.vsp3 not found — agent may not have saved the file.",
        }

    content = data.get("file_content", "")
    # Unescape if stored as escaped string
    content = content.replace("\\n", "\n").replace("\\t", "\t")

    # Validate it's XML
    try:
        ET.fromstring(content)
        score += 10
        feedback_parts.append("File is valid XML (+10).")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"File is not valid XML: {e}",
        }

    # --- Check 2: Root Sweep corrected (30 pts) ---
    sweep_val = _parse_param_value(content, SWEEP_ID)
    if sweep_val is None:
        feedback_parts.append(f"Root Sweep parameter (ID {SWEEP_ID}) not found in file (+0).")
    elif SWEEP_RANGE[0] <= sweep_val <= SWEEP_RANGE[1]:
        score += 30
        feedback_parts.append(
            f"Root Sweep corrected to {sweep_val:.1f} deg (target [{SWEEP_RANGE[0]}, {SWEEP_RANGE[1]}]) (+30)."
        )
    else:
        feedback_parts.append(
            f"Root Sweep = {sweep_val:.1f} deg — still outside target range "
            f"[{SWEEP_RANGE[0]}, {SWEEP_RANGE[1]}] (+0)."
        )

    # --- Check 3: Root Twist corrected (30 pts) ---
    twist_val = _parse_param_value(content, TWIST_ID)
    if twist_val is None:
        feedback_parts.append(f"Root Twist parameter (ID {TWIST_ID}) not found in file (+0).")
    elif TWIST_RANGE[0] <= twist_val <= TWIST_RANGE[1]:
        score += 30
        feedback_parts.append(
            f"Root Twist corrected to {twist_val:.1f} deg (target [{TWIST_RANGE[0]}, {TWIST_RANGE[1]}]) (+30)."
        )
    else:
        feedback_parts.append(
            f"Root Twist = {twist_val:.1f} deg — still outside target range "
            f"[{TWIST_RANGE[0]}, {TWIST_RANGE[1]}] (+0)."
        )

    # --- Check 4: Outboard Dihedral corrected (30 pts) ---
    dihedral_val = _parse_param_value(content, DIHEDRAL_ID)
    if dihedral_val is None:
        feedback_parts.append(f"Outboard Dihedral (ID {DIHEDRAL_ID}) not found in file (+0).")
    elif DIHEDRAL_RANGE[0] <= dihedral_val <= DIHEDRAL_RANGE[1]:
        score += 30
        feedback_parts.append(
            f"Outboard Dihedral corrected to {dihedral_val:.1f} deg (target [{DIHEDRAL_RANGE[0]}, {DIHEDRAL_RANGE[1]}]) (+30)."
        )
    else:
        feedback_parts.append(
            f"Outboard Dihedral = {dihedral_val:.1f} deg — still outside target range "
            f"[{DIHEDRAL_RANGE[0]}, {DIHEDRAL_RANGE[1]}] (+0)."
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
    }
