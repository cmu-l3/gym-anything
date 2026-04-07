#!/usr/bin/env python3
"""
Verifier for legacy_camera_stream_transcode_relay task.

Evaluates programmatic streams (RTSP and local file format compliance) and
process conditions to ensure VLC was used correctly for the relay.
Includes VLM checks to verify the agent actively scripted and operated the terminal.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prompt to ensure VLM confirms terminal usage and workflow, not just a static screen.
VLM_PROMPT = """
Analyze these chronological screenshots from an agent's workflow. 
The agent's goal was to construct a VLC command and save it to a bash script before executing it.
1. Is there evidence of the agent using a text editor (like nano, vim, or gedit) or writing commands into a bash script?
2. Is there evidence of the agent using the terminal to execute commands?

Respond strictly in this JSON format:
{
    "used_editor_or_scripting": true/false,
    "used_terminal": true/false,
    "confidence": "high/medium/low"
}
"""

def verify_transcode_relay(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    feedback_parts = []
    score = 0
    
    # 1. Anti-Gaming & VLC Process Check (15 pts)
    vlc_running = result.get('vlc_running', False)
    agent_used_ffmpeg = result.get('agent_used_ffmpeg', False)
    
    if agent_used_ffmpeg:
        feedback_parts.append("FAIL: Agent used ffmpeg instead of VLC for the relay.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    if vlc_running:
        score += 15
        feedback_parts.append("VLC stream output process is running.")
    else:
        feedback_parts.append("VLC is NOT running in the background.")

    # 2. Script Documentation Check (10 pts)
    if result.get('script_exists', False):
        score += 10
        feedback_parts.append("Script start_relay.sh created.")
    else:
        feedback_parts.append("Script start_relay.sh is missing.")

    # 3. RTSP Stream Checks (35 pts)
    rtsp_data = result.get('rtsp_probe', {})
    rtsp_streams = rtsp_data.get('streams', [])
    
    if rtsp_streams:
        codecs = [s.get('codec_name', '').lower() for s in rtsp_streams]
        has_h264 = 'h264' in codecs
        has_aac = 'aac' in codecs
        
        if has_h264 and has_aac:
            score += 35
            feedback_parts.append("RTSP stream is accessible with correct H.264/AAC codecs.")
        elif has_h264 or has_aac:
            score += 15
            feedback_parts.append(f"RTSP stream accessible but missing codecs. Found: {codecs}")
        else:
            feedback_parts.append(f"RTSP stream accessible but wrong format. Found: {codecs}")
    else:
        feedback_parts.append("RTSP stream is NOT accessible or empty.")

    # 4. Archive File Checks (25 pts)
    archive_exists = result.get('archive_exists', False)
    archive_mtime = result.get('archive_mtime', 0)
    task_start = result.get('task_start_time', 0)
    archive_size = result.get('archive_size_bytes', 0)
    
    file_data = result.get('file_probe', {})
    file_streams = file_data.get('streams', [])
    
    if archive_exists:
        if archive_mtime >= task_start:
            if archive_size > 5000:  # > 5KB to ensure it's not a dummy blank file
                file_codecs = [s.get('codec_name', '').lower() for s in file_streams]
                if 'h264' in file_codecs and 'aac' in file_codecs:
                    score += 25
                    feedback_parts.append("Archive file actively created with correct H.264/AAC codecs.")
                else:
                    score += 10
                    feedback_parts.append(f"Archive file created but wrong format. Found: {file_codecs}")
            else:
                feedback_parts.append("Archive file exists but is empty/too small.")
        else:
            feedback_parts.append("Archive file exists but predates task start (stale).")
    else:
        feedback_parts.append("Archive file missing.")

    # 5. VLM Trajectory Verification (15 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_res and vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('used_editor_or_scripting', False):
                        vlm_score += 10
                        feedback_parts.append("VLM: Scripting activity confirmed.")
                    if parsed.get('used_terminal', False):
                        vlm_score += 5
                        feedback_parts.append("VLM: Terminal execution confirmed.")
            score += vlm_score
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            # Do not completely fail the agent if VLM is simply unavailable, but note it.
            feedback_parts.append("VLM verification skipped/failed.")

    # Determine Pass/Fail Status
    # Must have at least 70 points AND the RTSP stream must be accessible.
    rtsp_accessible = len(rtsp_streams) > 0
    passed = score >= 70 and rtsp_accessible and vlc_running
    
    if passed and not rtsp_accessible:
        feedback_parts.append("GATE FAILED: RTSP stream must be accessible.")

    return {
        "passed": bool(passed),
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }