#!/usr/bin/env python3
"""
Verifier for openvsp_cruise_to_landing_transition.

Verification Strategy:
1. XML check: File exists and modified during task (anti-gaming).
2. XML check: parses the .vsp3 content to find the Wing <SubSurface> Flap Angle ≈ 35.0.
3. XML check: parses the .vsp3 content to find the Tail <Y_Rel_Rotation> Pitch ≈ -3.0.
4. VLM check: Uses trajectory frames to verify GUI interaction with the 'Sub' and 'XForm' tabs.
"""

import os
import json
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected targets
TARGET_FLAP_ANGLE = 35.0
TARGET_TAIL_PITCH = -3.0
TOLERANCE = 1.0


def extract_parameter_from_block(block: str, param_regex: str) -> float:
    """Helper to extract a float parameter from an XML text block."""
    m = re.search(param_regex, block)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            pass
    return None


def verify_openvsp_landing_transition(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. File State Verification
    if not result.get('output_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Model was not saved to /home/ga/Documents/OpenVSP/eCRM001_landing.vsp3"
        }
    
    score += 15
    feedback_parts.append("File saved successfully (+15)")

    if result.get('file_created_during_task', False):
        score += 15
        feedback_parts.append("File saved during task (+15)")
    else:
        feedback_parts.append("WARNING: File timestamp predates task start (0)")

    # 3. XML Content Parsing
    content = result.get('file_content', '')
    # Split XML by <Geom> to isolate components
    geom_blocks = content.split('<Geom>')
    
    flap_found_valid = False
    tail_pitch_found_valid = False

    for block in geom_blocks:
        # Check Wing block for Subsurfaces
        if '<Name>Wing</Name>' in block or 'eCRM-001_Wing' in block:
            if '<SubSurface>' in block:
                # Find the angle value inside the subsurface
                # Example: <Angle Value="35.000000000000000000e+00" ID="..."/>
                angle_val = extract_parameter_from_block(block, r'<Angle\s+Value="([^"]+)"')
                if angle_val is not None:
                    if abs(angle_val - TARGET_FLAP_ANGLE) <= TOLERANCE:
                        flap_found_valid = True
                        score += 25
                        feedback_parts.append(f"Wing flap set to {angle_val:.1f} degrees (+25)")
                    else:
                        feedback_parts.append(f"Wing flap angle incorrect ({angle_val:.1f} != {TARGET_FLAP_ANGLE})")
            else:
                feedback_parts.append("No SubSurface found in Wing component")

        # Check Tail block for XForm Pitch
        if 'Tail' in block or 'HTail' in block:
            pitch_val = extract_parameter_from_block(block, r'<Y_Rel_Rotation\s+Value="([^"]+)"')
            if pitch_val is not None:
                if abs(pitch_val - TARGET_TAIL_PITCH) <= TOLERANCE:
                    tail_pitch_found_valid = True
                    score += 25
                    feedback_parts.append(f"Tail pitch set to {pitch_val:.1f} degrees (+25)")
                else:
                    feedback_parts.append(f"Tail pitch incorrect ({pitch_val:.1f} != {TARGET_TAIL_PITCH})")

    if not flap_found_valid and not any('Flap' in p for p in feedback_parts):
        feedback_parts.append("Failed to find correctly configured Flap Subsurface in Wing")
    if not tail_pitch_found_valid and not any('Tail pitch' in p for p in feedback_parts):
        feedback_parts.append("Failed to find correctly configured Tail Y-rotation (Pitch)")

    # 4. VLM Trajectory Verification
    vlm_query_fn = env_info.get('query_vlm')
    vlm_score = 0
    if vlm_query_fn and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            if final_img:
                frames.append(final_img)
            
            frames = [f for f in frames if f is not None]
            
            if frames:
                prompt = (
                    "You are verifying an agent using OpenVSP CAD software. "
                    "Did the agent use the graphical interface to configure the landing setup? "
                    "Look for evidence of two things across these frames:\n"
                    "1. The 'Sub' (Subsurface) tab being opened for the Wing to add a Flap.\n"
                    "2. The 'XForm' tab being opened for the Tail to adjust rotation/pitch.\n"
                    "Respond with JSON: {\"used_gui\": true/false, \"reason\": \"...\"}"
                )
                
                vlm_resp = vlm_query_fn(prompt=prompt, images=frames)
                if vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("used_gui", False):
                        vlm_score = 20
                        feedback_parts.append("VLM verified GUI interactions (+20)")
                    else:
                        feedback_parts.append("VLM did not detect required GUI interactions (0)")
                else:
                    feedback_parts.append("VLM verification failed to process")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification encountered an error")
    else:
        feedback_parts.append("VLM query function or trajectory not available")

    score += vlm_score

    # 5. Final Determination
    # Must have saved the file AND gotten at least one parameter right to pass
    key_criteria_met = result.get('output_exists', False) and (flap_found_valid or tail_pitch_found_valid)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }