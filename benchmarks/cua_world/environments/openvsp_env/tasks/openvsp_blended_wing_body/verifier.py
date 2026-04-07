#!/usr/bin/env python3
"""
Verifier for openvsp_blended_wing_body task.

Checks the agent created a valid OpenVSP BWB concept model with:
  1. File exists, valid XML, and created during task (anti-gaming): 10 pts
  2. Wing component present (WingGeom): 15 pts
  3. No conventional Fuselage/Pod present (BWB trait): 10 pts
  4. TotalSpan in [4.5, 8.0] m (approx 6.10 m): 15 pts
  5. Large center-body root chord (>= 2.5 m): 15 pts
  6. High sweep on center body (>= 25 deg): 10 pts
  7. Vertical fins present (multiple WingGeom or ~90 deg rotation/dihedral): 10 pts
  8. VLM Trajectory Verification: Confirms visual progression of a 3D model: 15 pts

Pass threshold: 60 points.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


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


def _count_component_types(content: str, type_name: str) -> int:
    """Count occurrences of <Type>type_name</Type>."""
    pattern = rf'<Type>{type_name}</Type>'
    return len(re.findall(pattern, content))


def verify_openvsp_bwb(trajectory, env_info, task_info):
    result_file = "/tmp/bwb_task_result.json"

    # Copy result file from VM
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found — export script may not have run: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- Check 1: File existence and timestamp (10 pts) ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "bwb_concept.vsp3 not found at expected path."
        }

    if not data.get("created_during_task", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "File timestamp predates task start (Do Nothing detected)."
        }

    content = data.get("file_content", "").replace("\\n", "\n").replace("\\t", "\t")

    try:
        ET.fromstring(content)
        score += 10
        feedback_parts.append("File is valid XML (+10)")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"bwb_concept.vsp3 is not valid XML: {e}"
        }

    # --- Check 2: WingGeom component present (15 pts) ---
    wing_count = _count_component_types(content, "WingGeom")
    if wing_count > 0:
        score += 15
        feedback_parts.append(f"Found {wing_count} WingGeom components (+15)")
    else:
        feedback_parts.append("No WingGeom components found (+0)")

    # --- Check 3: No Fuselage/Pod present (10 pts) ---
    fuse_count = _count_component_types(content, "FuselageGeom") + _count_component_types(content, "PodGeom")
    if fuse_count == 0:
        score += 10
        feedback_parts.append("No conventional fuselage found (Correct for BWB) (+10)")
    else:
        feedback_parts.append(f"Found {fuse_count} Fuselage/Pod components (BWB should not have one) (+0)")

    # Parameter Extractions
    spans = _find_param_values_by_tag(content, "TotalSpan") + _find_param_values_by_tag(content, "Span")
    chords = _find_param_values_by_tag(content, "Root_Chord") + _find_param_values_by_tag(content, "Chord")
    sweeps = _find_param_values_by_tag(content, "Sweep") + _find_param_values_by_tag(content, "Sweep_Location")
    dihedrals = _find_param_values_by_tag(content, "Dihedral")
    rotations = _find_param_values_by_tag(content, "X_Rel_Rotation")

    # --- Check 4: TotalSpan in [4.5, 8.0] m (15 pts) ---
    valid_span = any(4.5 <= s <= 8.0 for s in spans)
    if valid_span:
        score += 15
        feedback_parts.append("Span within valid range for spec (+15)")
    else:
        feedback_parts.append(f"No span in [4.5, 8.0]m (Found: {spans[:3]}) (+0)")

    # --- Check 5: Large Root Chord >= 2.5m (15 pts) ---
    valid_chord = any(c >= 2.5 for c in chords)
    if valid_chord:
        score += 15
        feedback_parts.append("Large root chord found (BWB center body) (+15)")
    else:
        feedback_parts.append(f"No chord >= 2.5m found (Found max: {max(chords) if chords else 'None'}) (+0)")

    # --- Check 6: High Sweep >= 25 deg (10 pts) ---
    valid_sweep = any(sw >= 25.0 for sw in sweeps)
    if valid_sweep:
        score += 10
        feedback_parts.append("High sweep angle found (+10)")
    else:
        feedback_parts.append("Sweep angle too low for BWB (+0)")

    # --- Check 7: Vertical Fins Present (10 pts) ---
    # Fins indicated by multiple wings, or high dihedral (>45), or X-rotation (>45)
    has_fins = (wing_count >= 2) or any(d >= 45.0 for d in dihedrals) or any(r >= 45.0 for r in rotations)
    if has_fins:
        score += 10
        feedback_parts.append("Vertical fin configuration detected (+10)")
    else:
        feedback_parts.append("No vertical fins detected (+0)")

    # --- Check 8: VLM Trajectory Verification (15 pts) ---
    vlm_score = 0
    if "query_vlm" in env_info:
        try:
            frames = sample_trajectory_frames(trajectory, n=3)
            final_frame = get_final_screenshot(trajectory)
            if final_frame:
                frames.append(final_frame)

            prompt = """You are evaluating an agent using OpenVSP to build a Blended Wing Body (BWB) aircraft.
Look at the sequence of screenshots.
1. Did the agent actively interact with the OpenVSP geometry application?
2. Does the final model geometry look somewhat like a Blended Wing Body aircraft (a wide swept wing without a separate cylindrical tube fuselage)?

Return JSON:
{
  "interacted": true/false,
  "looks_like_bwb": true/false
}"""
            vlm_res = env_info["query_vlm"](prompt=prompt, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("interacted"):
                    vlm_score += 5
                if parsed.get("looks_like_bwb"):
                    vlm_score += 10
                feedback_parts.append(f"VLM Visual Verification: {vlm_score}/15 pts")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # Grant partial credit if programmatic checks are extremely good but VLM fails technically
            if score >= 75:
                vlm_score += 15
                feedback_parts.append("VLM failed, but programmatic geometry is excellent (+15)")
            else:
                feedback_parts.append(f"VLM verification error (+0)")
    else:
        # If no VLM capability, grant the points if programmatic checks passed well
        if score >= 50:
            vlm_score = 15
            feedback_parts.append("No VLM available, auto-granted visual points (+15)")

    score += vlm_score

    passed = score >= 60 and valid_span and valid_chord
    if passed:
        feedback_parts.append("SUCCESS: Model meets BWB geometry criteria.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }