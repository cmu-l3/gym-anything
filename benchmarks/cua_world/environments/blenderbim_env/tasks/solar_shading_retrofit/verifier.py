#!/usr/bin/env python3
"""
Verifier for solar_shading_retrofit task.

The agent must model at least 3 exterior shading devices, assign them as IfcShadingDevice,
set valid PredefinedTypes (AWNING/LOUVER/SHUTTER), and assign them to a spatial container.

Scoring rubric (100 points total, pass threshold = 75):
  - file_is_new                  : 15 pts (gate)
  - n_shading_devices >= 3       : 25 pts (partial: >=2 is 15 pts, 1 is 8 pts)
  - valid_predefined_type >= 1   : 10 pts
  - geometry_present >= 1        : 15 pts
  - spatial_containment >= 1     : 15 pts
  - VLM: Visual evidence of shades : 20 pts (partial: 1-2 shades is 10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an architectural 3D modeling task in Blender.
The agent was asked to model exterior solar shading devices (e.g., awnings, louvers, or blocks) 
over the exterior windows of the pre-loaded residential building.

Review the provided screenshots of the user interface.
Assess the following:
1. Are there newly created 3D geometric objects placed on the exterior facade of the building, specifically above or near the windows, intended to act as solar shades?
2. If so, approximately how many different windows have these shades applied?

Respond ONLY in valid JSON format:
{
    "shading_visible": true/false,
    "confidence": "high/medium/low",
    "windows_shaded": <integer_count>,
    "observations": "Brief explanation of what you see"
}
"""

def verify_solar_shading_retrofit(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available."}

    # ── 1. Read exported result JSON ──────────────────────────────────────
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/solar_shading_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # ── 2. Check File Constraints ─────────────────────────────────────────
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Output IFC file /home/ga/BIMProjects/fzk_solar_shading.ifc was not created. Score: 0/100."
        }

    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    if task_start > 0 and file_mtime > task_start:
        score += 15
        feedback_lines.append("PASS: Output IFC was created during this task session. (+15)")
    else:
        feedback_lines.append(f"FAIL: Output file not modified during task. (+0)")

    # ── 3. Check Programmatic BIM Metrics ─────────────────────────────────
    n_devices = result.get("n_shading_devices", 0)
    n_valid_type = result.get("n_valid_predefined_type", 0)
    n_geometry = result.get("n_with_geometry", 0)
    n_contained = result.get("n_contained_in_storey", 0)

    # IfcShadingDevice count (25 pts)
    if n_devices >= 3:
        score += 25
        feedback_lines.append(f"PASS: {n_devices} IfcShadingDevice entities found (>= 3 required). (+25)")
    elif n_devices == 2:
        score += 15
        feedback_lines.append(f"PARTIAL: {n_devices}/3 IfcShadingDevice entities found. (+15)")
    elif n_devices == 1:
        score += 8
        feedback_lines.append(f"PARTIAL: {n_devices}/3 IfcShadingDevice entities found. (+8)")
    else:
        feedback_lines.append("FAIL: No IfcShadingDevice entities found. (+0)")

    # PredefinedType (10 pts)
    if n_valid_type >= 1:
        score += 10
        feedback_lines.append(f"PASS: {n_valid_type} device(s) have valid PredefinedType (AWNING/LOUVER/SHUTTER). (+10)")
    else:
        feedback_lines.append("FAIL: No device has a valid PredefinedType set. (+0)")

    # Geometry Representation (15 pts)
    if n_geometry >= 1:
        score += 15
        feedback_lines.append(f"PASS: {n_geometry} device(s) possess 3D Representation/geometry. (+15)")
    else:
        feedback_lines.append("FAIL: No device possesses 3D geometry (empty entities). (+0)")

    # Spatial Containment (15 pts)
    if n_contained >= 1:
        score += 15
        feedback_lines.append(f"PASS: {n_contained} device(s) are contained within the building spatial structure. (+15)")
    else:
        feedback_lines.append("FAIL: No device is assigned to a spatial container (e.g. Storey). (+0)")

    # ── 4. VLM Visual Verification ────────────────────────────────────────
    query_vlm = env_info.get("query_vlm")
    vlm_score = 0
    if query_vlm and traj:
        try:
            # Safely attempt to gather frames from the framework utilities if available
            images = []
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(traj, n=3)
                final_frame = get_final_screenshot(traj)
                if frames:
                    images.extend(frames)
                if final_frame:
                    images.append(final_frame)
            except ImportError:
                # Fallback: Just grab the last observation if helper is missing
                if len(traj.steps) > 0 and 'screenshot' in traj.steps[-1].obs:
                    images.append(traj.steps[-1].obs['screenshot'])

            if images:
                vlm_resp = query_vlm(prompt=VLM_PROMPT, images=images)
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    shading_visible = parsed.get("shading_visible", False)
                    windows_shaded = parsed.get("windows_shaded", 0)
                    
                    if shading_visible and windows_shaded >= 3:
                        vlm_score = 20
                        feedback_lines.append(f"PASS (VLM): Confirmed shading devices placed on {windows_shaded} windows. (+20)")
                    elif shading_visible and windows_shaded > 0:
                        vlm_score = 10
                        feedback_lines.append(f"PARTIAL (VLM): Confirmed shading devices placed on {windows_shaded} windows. (+10)")
                    else:
                        feedback_lines.append("FAIL (VLM): No visible shading devices detected by VLM. (+0)")
                else:
                    feedback_lines.append("WARNING: VLM query failed or did not return valid format.")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_lines.append("WARNING: VLM verification encountered an error.")
    else:
        feedback_lines.append("WARNING: VLM verification skipped (query_vlm not available).")

    score += vlm_score
    passed = score >= 75
    
    feedback_lines.append(f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 75).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }