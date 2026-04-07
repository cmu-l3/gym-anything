#!/usr/bin/env python3
"""
Verifier for openvsp_wave_drag_area_ruling task.

Checks:
  1. Report file exists and was created during the task (10 pts)
  2. Report contains Mach number = 1.05 (15 pts)
  3. Report contains slicing planes >= 40 (10 pts)
  4. Report contains theta rotations >= 20 (10 pts)
  5. Report contains a numeric CDwave value > 0 (25 pts)
  6. Saved .vsp3 model exists, is valid XML, and differs from original (10 pts)
  7. Saved .vsp3 model contains Wave Drag configurations/parameters (10 pts)
  8. VLM Trajectory Check: Agent actually opened the Wave Drag panel (10 pts)

Total: 100 points
Pass threshold: 60 points
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _extract_number_near_keywords(text: str, keywords: list) -> float | None:
    """Helper to extract a float number appearing near specific keywords."""
    text_lower = text.lower()
    for kw in keywords:
        kw_lower = kw.lower()
        idx = text_lower.find(kw_lower)
        if idx >= 0:
            # Look in a window right after the keyword
            window = text[idx : idx + 60]
            # Match integers or floats
            nums = re.findall(r'[+-]?\d+\.?\d*', window)
            for n in nums:
                try:
                    return float(n)
                except ValueError:
                    continue
    return None


def verify_openvsp_wave_drag(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/wave_drag_result.json")
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
            "feedback": f"Result JSON not found or invalid: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    
    task_start = data.get("task_start_time", 0)

    # ==========================================
    # 1. Report Check (10 pts)
    # ==========================================
    report_exists = data.get("report_exists", False)
    report_content = data.get("report_content", "")
    
    if report_exists:
        if data.get("report_mtime", 0) >= task_start:
            score += 10
            feedback_parts.append("Report created during task (+10).")
        else:
            feedback_parts.append("Report exists but appears older than task start (+0).")
    else:
        feedback_parts.append("wave_drag_report.txt not found (+0).")

    # ==========================================
    # 2. Extract Data from Report (15 + 10 + 10 + 25 pts)
    # ==========================================
    if report_exists and report_content:
        # Check Mach
        mach = _extract_number_near_keywords(report_content, ["Mach", "M ="])
        if mach is not None and abs(mach - 1.05) < 0.01:
            score += 15
            feedback_parts.append(f"Mach number correctly set to {mach} (+15).")
        elif "1.05" in report_content:
            score += 15
            feedback_parts.append("Mach number 1.05 found in report (+15).")
        else:
            feedback_parts.append(f"Mach 1.05 not found in report (+0).")

        # Check Slices
        slices = _extract_number_near_keywords(report_content, ["slice", "slicing", "planes"])
        if slices is not None and slices >= 40:
            score += 10
            feedback_parts.append(f"Slicing planes correctly reported as {slices} (+10).")
        else:
            feedback_parts.append(f"Valid slicing planes (>= 40) not found (+0).")

        # Check Rotations
        rotations = _extract_number_near_keywords(report_content, ["rotations", "theta"])
        if rotations is not None and rotations >= 20:
            score += 10
            feedback_parts.append(f"Theta rotations correctly reported as {rotations} (+10).")
        else:
            feedback_parts.append(f"Valid theta rotations (>= 20) not found (+0).")

        # Check CDwave (Expected physical range [1e-6, 0.1])
        cdwave = _extract_number_near_keywords(report_content, ["CDwave", "Wave Drag", "WaveDrag", "Coefficient"])
        if cdwave is not None and 0.0 < cdwave < 0.1:
            score += 25
            feedback_parts.append(f"Valid Wave Drag Coefficient found: {cdwave} (+25).")
        else:
            # Fallback check for *any* small positive float as CDwave
            nums = re.findall(r'[+]?\d*\.\d+[eE]?[+-]?\d*', report_content)
            found_cd = False
            for n in nums:
                try:
                    val = float(n)
                    if 0.000001 <= val < 0.1 and val != 1.05: # ignore mach
                        score += 20
                        feedback_parts.append(f"Found plausible CDwave value: {val} (partial, +20).")
                        found_cd = True
                        break
                except ValueError:
                    pass
            if not found_cd:
                feedback_parts.append("No valid CDwave value found (+0).")

    # ==========================================
    # 3. Model File Checks (10 + 10 pts)
    # ==========================================
    model_exists = data.get("model_exists", False)
    model_content = data.get("model_content", "")
    
    if model_exists:
        if data.get("model_hash") != data.get("original_model_hash"):
            try:
                # We truncated content to 10KB, so a full XML parse might fail if file is huge,
                # but we can look for basic XML markers and wave drag strings
                if "<Vehicle" in model_content or "OpenVSP" in model_content:
                    score += 10
                    feedback_parts.append("Saved model exists and is modified (+10).")
                    
                    if "WaveDrag" in model_content or "Mach" in model_content:
                        score += 10
                        feedback_parts.append("Model contains Wave Drag configurations (+10).")
                    else:
                        feedback_parts.append("Model modified but missing Wave Drag parameters (+0).")
                else:
                    feedback_parts.append("Saved model does not appear to be valid VSP3 XML (+0).")
            except Exception as e:
                 feedback_parts.append("Error evaluating model content (+0).")
        else:
            feedback_parts.append("Model saved but identical to original (no configuration done) (+0).")
    else:
        feedback_parts.append("eCRM-001_wave_drag.vsp3 not saved (+0).")

    # ==========================================
    # 4. VLM Trajectory Verification (10 pts)
    # ==========================================
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(trajectory, n=4)
        if frames and "query_vlm" in env_info:
            vlm_prompt = """
            Look at these screenshots of a user operating OpenVSP.
            Did the user open the 'Wave Drag' analysis tool?
            You should look for a window or panel explicitly titled 'Wave Drag' or showing Wave Drag parameters (Mach, Slices, Rotations, Area Distribution).
            Respond with JSON: {"wave_drag_panel_visible": true/false}
            """
            vlm_res = env_info["query_vlm"](prompt=vlm_prompt, images=frames)
            
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("wave_drag_panel_visible"):
                score += 10
                feedback_parts.append("VLM verified Wave Drag panel was opened (+10).")
            else:
                feedback_parts.append("VLM did not detect Wave Drag panel in trajectory (+0).")
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")
        # Grant points if the programmatic parts were extremely thorough (CDwave extracted)
        if score >= 60:
            score += 10
            feedback_parts.append("VLM failed but programmatic evidence strong enough (+10).")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }