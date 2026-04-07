#!/usr/bin/env python3
"""
Verifier for Security Camera Daily Digest task.

Verifies:
1. Programmatic File Assessment (70 points)
   - Timelapses (15 points)
   - Extracted Frames (15 points) 
   - Incident Clips (20 points)
   - JSON Digest Manifest (20 points)
2. VLM Trajectory Assessment (30 points)
   - Verifies the agent actually processed files through tools/terminals.

Pass threshold: 60 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to ensure genuine completion (prevents blind script gaming)
TRAJECTORY_PROMPT = """You are verifying a video batch processing task.
Look at these chronological screenshots from the agent's trajectory.

The agent's goal was to process security camera footage (creating timelapses, extracting frames, and clipping videos). They might use VLC, a terminal (running ffmpeg/cvlc), or a text editor.

Analyze the images and respond with JSON:
{
    "media_tools_used": true/false, // Is there evidence of VLC, terminal, ffmpeg, or code editors being used?
    "meaningful_progression": true/false, // Do the frames show progress over time (e.g. typing commands, output scrolling, opening different files)?
    "confidence": "low"/"medium"/"high",
    "observations": "Brief explanation of what the agent is doing."
}
"""

def verify_daily_digest(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Fetch the main task result (metadata gathered via ffprobe)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Fetch the agent's generated manifest
    manifest_data = None
    temp_manifest = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        if result.get("manifest_exists"):
            copy_from_env("/home/ga/Videos/daily_digest/digest_manifest.json", temp_manifest.name)
            with open(temp_manifest.name, 'r') as f:
                manifest_data = json.load(f)
    except Exception as e:
        pass # Will be handled in scoring
    finally:
        if os.path.exists(temp_manifest.name):
            os.unlink(temp_manifest.name)

    # --- SCORE TIMELAPSES (15 points) ---
    timelapses = result.get("timelapses", {})
    tl_score = 0
    for cam in ['lobby', 'parking', 'loading']:
        tl = timelapses.get(cam, {})
        if tl.get("exists") and tl.get("newly_created"):
            cam_score = 0
            # duration should be around 30s (180s / 6 = 30s), allow generous margin for different ffmpeg filters
            if 15 <= tl.get("duration", 0) <= 45: cam_score += 2
            if tl.get("vcodec") == "h264": cam_score += 1
            if not tl.get("has_audio"): cam_score += 2
            tl_score += cam_score
    score += tl_score
    feedback_parts.append(f"Timelapses: {tl_score}/15")

    # --- SCORE FRAMES (15 points) ---
    frames = result.get("frames", [])
    valid_frames = [f for f in frames if f.get("size", 0) > 5000 and f.get("newly_created")]
    frame_score = 0
    if len(valid_frames) >= 15:
        frame_score += 5
    elif len(valid_frames) >= 5:
        frame_score += 2
        
    # Check camera variety in frames
    cams_found = set()
    for f in valid_frames:
        name = f.get("name", "").lower()
        for cam in ['lobby', 'parking', 'loading']:
            if cam in name:
                cams_found.add(cam)
    frame_score += len(cams_found) * 2  # up to 6 pts
    
    # Quality check awarded if they hit the count and variety
    if frame_score >= 11:
        frame_score += 4 # up to 15 total
        
    score += frame_score
    feedback_parts.append(f"Frames: {frame_score}/15")

    # --- SCORE INCIDENTS (20 points) ---
    incidents = result.get("incidents", {})
    expected_durs = {"incident_1": 20, "incident_2": 25, "incident_3": 25, "incident_4": 20}
    inc_score = 0
    for inc_name, expected_dur in expected_durs.items():
        inc = incidents.get(inc_name, {})
        if inc.get("exists") and inc.get("newly_created"):
            dur = inc.get("duration", 0)
            if abs(dur - expected_dur) <= 4:
                inc_score += 5
            elif abs(dur - expected_dur) <= 10:
                inc_score += 2
    score += inc_score
    feedback_parts.append(f"Incidents: {inc_score}/20")

    # --- SCORE MANIFEST (20 points) ---
    man_score = 0
    if manifest_data and isinstance(manifest_data, dict):
        man_score += 5  # Valid JSON
        
        if "cameras" in manifest_data and len(manifest_data["cameras"]) >= 3:
            man_score += 5
            
        if "incidents" in manifest_data and len(manifest_data["incidents"]) >= 4:
            man_score += 5
            
        if "frames_count" in manifest_data or "frames" in manifest_data:
            man_score += 5
            
    score += man_score
    feedback_parts.append(f"Manifest: {man_score}/20")

    # --- VLM TRAJECTORY VERIFICATION (30 points) ---
    vlm_score = 0
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    try:
        frames_to_check = sample_trajectory_frames(traj, n=4)
        if frames_to_check:
            vlm_res = query_vlm(images=frames_to_check, prompt=TRAJECTORY_PROMPT)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("media_tools_used"):
                    vlm_score += 15
                if parsed.get("meaningful_progression"):
                    vlm_score += 15
                feedback_parts.append(f"VLM verified process ({vlm_score}/30).")
            else:
                feedback_parts.append("VLM evaluation failed to parse/run.")
        else:
            feedback_parts.append("No trajectory frames available for VLM.")
    except Exception as e:
        logger.warning(f"VLM Verification error: {e}")
        feedback_parts.append("VLM error encountered.")
        
    score += vlm_score

    passed = score >= 60 and (inc_score > 0 or tl_score > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }