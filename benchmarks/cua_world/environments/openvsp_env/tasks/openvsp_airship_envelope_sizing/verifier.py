#!/usr/bin/env python3

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_openvsp_airship_envelope(traj, env_info, task_info):
    """
    Multi-criteria verification for the Airship Sizing task.
    Evaluates file metadata, XML constraints mathematically, user text report, 
    and verifies active usage via VLM trajectory frames.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/openvsp_airship_result.json", local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback = []

    task_start = data.get("task_start", 0)
    vsp_exists = data.get("vsp_exists", False)
    vsp_mtime = data.get("vsp_mtime", 0)
    report_exists = data.get("report_exists", False)
    
    # Check if files created after task start (Anti-gaming check)
    if not vsp_exists:
        return {"passed": False, "score": 0, "feedback": "haps_airship.vsp3 was not saved."}
        
    if vsp_mtime < task_start:
        feedback.append("Warning: haps_airship.vsp3 appears to be older than task start.")
    else:
        score += 10
        feedback.append("VSP3 file successfully created. (+10)")

    vsp_content = data.get("vsp_content", "")
    report_content = data.get("report_content", "")

    # XML Parsing / Math Evaluation
    # Extract Length
    lengths = [float(x) for x in re.findall(r'<Length\s+Value="([^"]+)"', vsp_content)]
    fuse_length = max(lengths) if lengths else 0

    # Extract Max Width/Height to find envelope Diameter
    widths = [float(x) for x in re.findall(r'<Width\s+Value="([^"]+)"', vsp_content)]
    heights = [float(x) for x in re.findall(r'<Height\s+Value="([^"]+)"', vsp_content)]
    max_diam = max(widths + heights + [0])
    
    # Check for Wings (Empennage)
    has_wing = "WingGeom" in vsp_content
    x_locs = [float(x) for x in re.findall(r'<X_Rel\s+Value="([^"]+)"', vsp_content)] + \
             [float(x) for x in re.findall(r'<X_Location\s+Value="([^"]+)"', vsp_content)]
    max_x_loc = max(x_locs) if x_locs else 0

    if fuse_length > 0 and max_diam > 0:
        score += 10
        feedback.append(f"Fuselage detected (Length: {fuse_length:.1f}, Max Diameter: {max_diam:.1f}). (+10)")
        
        # Check Fineness Ratio
        fr = fuse_length / max_diam
        if 4.7 <= fr <= 5.3:
            score += 15
            feedback.append(f"Fineness ratio {fr:.2f} is within target 5.0 ± 0.3. (+15)")
        else:
            feedback.append(f"Fineness ratio {fr:.2f} missed target 5.0. (+0)")
            
        # Check overall volume plausibility for 75,000 m^3 target envelope
        # Formula approximation: target volume leads to a Length around 150-160 and Diameter 30-32
        if 135 <= fuse_length <= 175 and 26 <= max_diam <= 35:
            score += 15
            feedback.append("Dimensions match the 75,000 m^3 target envelope mathematically. (+15)")
        else:
            feedback.append("Dimensions do not mathematically match the 75,000 m^3 target. (+0)")
    else:
        feedback.append("Could not extract meaningful Length/Diameter from VSP3. (+0)")
        
    # Check fins (attached to aft region)
    if has_wing:
        if fuse_length > 0 and max_x_loc >= fuse_length * 0.6:
            score += 10
            feedback.append(f"WingGeom (empennage) positioned aft (X={max_x_loc:.1f}). (+10)")
        else:
            score += 5
            feedback.append("WingGeom found, but position is not clearly aft. (+5)")
    else:
        feedback.append("No empennage (WingGeom) found. (+0)")

    # Report checking
    if report_exists:
        score += 5
        feedback.append("Report file exists. (+5)")
        
        # Look for numbers indicative of roughly 75,000
        vol_match = re.search(r'7[0-9],?[0-9]{3}', report_content) or re.search(r'7[0-9]\.?[0-9]*', report_content)
        # Look for length around 150
        len_match = re.search(r'1[3-7][0-9]', report_content)
        
        if vol_match and len_match:
            score += 15
            feedback.append("Report contains accurate geometry numbers. (+15)")
        else:
            feedback.append("Report numbers are missing or do not match targets. (+0)")
    else:
        feedback.append("Report file not created. (+0)")

    # VLM Trajectory Verification
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are verifying an OpenVSP CAD task.
The user was asked to build a large airship envelope (long cylindrical fuselage) with tail fins.
Review the trajectory screenshots.
Did the agent actively use the OpenVSP UI to add and adjust a Fuselage/Pod and Wing/Fin components?
Respond in JSON format with a single boolean key 'active_vsp_usage':
{
    "active_vsp_usage": true/false
}"""
            vlm_resp = query_vlm(prompt=prompt, images=images)
            if vlm_resp and vlm_resp.get("parsed", {}).get("active_vsp_usage", False):
                score += 20
                feedback.append("VLM confirms active OpenVSP usage. (+20)")
            else:
                feedback.append("VLM did not detect active OpenVSP usage. (+0)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback.append("VLM verification skipped/failed. (+0)")
    else:
        feedback.append("VLM query function not available. (+0)")

    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }