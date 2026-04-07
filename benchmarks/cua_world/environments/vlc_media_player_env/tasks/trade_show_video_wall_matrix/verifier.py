#!/usr/bin/env python3
"""
Verifier for trade_show_video_wall_matrix task.

Uses multi-criteria programmatic evaluation combined with VLM trajectory verification.
Programmatic Checks (70 pts):
- Files exist and were created during task (10 pts)
- Video Dimensions = 1920x1080 (10 pts)
- Audio Stripped = 0 audio streams (10 pts)
- Duration match = ~30s (10 pts)
- SSIM >= 0.95: Proves genuine spatial cropping instead of squishing (20 pts)
- JSON Manifest valid format and contents (10 pts)

VLM Trajectory Check (30 pts):
- Verifies that the agent actually executed proper FFmpeg/VLC commands and edited the JSON file.
"""

import json
import tempfile
import os
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent's trajectory for a video processing task.
The agent was asked to slice a 4K video into four 1080p quadrants using exact spatial cropping and strip the audio. They were also asked to write a JSON manifest.
Review these sampled screenshots spanning the task's timeline.

Assess the following:
1. Did the agent use a terminal tool (like `ffmpeg`, `ffprobe`, or `vlc` via CLI) to process the video? You should see commands specifying crop filters (e.g. `crop=1920:1080:0:0` or similar syntax).
2. Is there evidence that the agent stripped audio (e.g. `-an` or `-c:a none` in ffmpeg)?
3. Did the agent open an editor (like nano, vim, gedit) to construct a JSON file `wall_manifest.json`?

Return your findings in valid JSON format:
{
    "used_video_cli_tool": true/false,
    "used_crop_filters": true/false,
    "stripped_audio_in_command": true/false,
    "edited_json_manifest": true/false,
    "confidence": "low|medium|high",
    "reasoning": "Brief explanation of what is visible in the terminal or editor"
}
"""

def verify_trade_show_video_wall_matrix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch evaluated metrics from the container
    matrix_result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/matrix_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            matrix_result = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Failed to read exported results: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Programmatic Evaluation
    task_start = matrix_result.get("task_start", 0)
    panels = matrix_result.get("panels", {})
    
    EXPECTED_DUR = task_info.get("metadata", {}).get("expected_duration", 30.0)
    
    panels_found = 0
    good_dims = 0
    good_audio = 0
    good_dur = 0
    good_ssim = 0
    
    for key in ["TL", "TR", "BL", "BR"]:
        panel = panels.get(key, {})
        if not panel.get("exists", False):
            feedback_parts.append(f"Panel {key} missing.")
            continue
            
        mtime = panel.get("mtime", 0)
        if mtime < task_start:
            feedback_parts.append(f"Panel {key} was not created during this task (cheating).")
            continue
            
        panels_found += 1
        
        # Dimensions check
        w, h = panel.get("width", 0), panel.get("height", 0)
        if w == 1920 and h == 1080:
            good_dims += 1
        else:
            feedback_parts.append(f"Panel {key} bad dims: {w}x{h}.")
            
        # Audio check
        if panel.get("audio_count", 1) == 0:
            good_audio += 1
        else:
            feedback_parts.append(f"Panel {key} audio not stripped.")
            
        # Duration check
        dur = panel.get("duration", 0)
        if abs(dur - EXPECTED_DUR) <= 1.0:
            good_dur += 1
        else:
            feedback_parts.append(f"Panel {key} bad duration: {dur:.1f}s.")
            
        # SSIM check (gate against scaling hack)
        ssim = panel.get("ssim", 0.0)
        if ssim >= 0.95:
            good_ssim += 1
        else:
            feedback_parts.append(f"Panel {key} failed spatial integrity SSIM ({ssim:.3f}). Scaled instead of cropped?")
            
    # Tally Programmatic Scores
    score += panels_found * 2.5     # max 10
    score += good_dims * 2.5        # max 10
    score += good_audio * 2.5       # max 10
    score += good_dur * 2.5         # max 10
    score += good_ssim * 5.0        # max 20
    
    # 3. Check JSON Manifest
    manifest_data = None
    temp_manifest = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/wall_manifest.json", temp_manifest.name)
        with open(temp_manifest.name, 'r') as f:
            manifest_data = json.load(f)
    except Exception as e:
        feedback_parts.append("Manifest file missing or invalid JSON.")
    finally:
        if os.path.exists(temp_manifest.name):
            os.unlink(temp_manifest.name)

    if manifest_data:
        try:
            m_panels = manifest_data.get("panels", {})
            if manifest_data.get("master_video") == "tradeshow_master_4k.mp4" and len(m_panels) == 4:
                # Basic schema check
                valid = True
                expected_offsets = {"TL": [0,0], "TR": [1920,0], "BL": [0,1080], "BR": [1920,1080]}
                for p_key, p_val in expected_offsets.items():
                    data = m_panels.get(p_key, {})
                    if data.get("resolution") != "1920x1080" or data.get("offset_x") != p_val[0] or data.get("offset_y") != p_val[1]:
                        valid = False
                if valid:
                    score += 10.0
                    feedback_parts.append("Manifest verified.")
                else:
                    feedback_parts.append("Manifest contents incorrect offsets/res.")
        except Exception as e:
            feedback_parts.append("Manifest structure invalid.")
            
    # 4. VLM Trajectory Verification (30 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        if frames:
            try:
                result = query_vlm(prompt=VLM_PROMPT, images=frames)
                if result and result.get("success"):
                    parsed = result.get("parsed", {})
                    if parsed.get("used_video_cli_tool", False): vlm_score += 10
                    if parsed.get("used_crop_filters", False): vlm_score += 10
                    if parsed.get("edited_json_manifest", False): vlm_score += 10
                    
                    feedback_parts.append(f"VLM verified workflow: {vlm_score}/30 pts.")
                else:
                    feedback_parts.append("VLM query failed to parse.")
            except Exception as e:
                feedback_parts.append(f"VLM exception: {str(e)}")
    
    score += vlm_score
    
    # Assess pass threshold
    # Must achieve 75+ points and all 4 panels must pass SSIM spatial integrity (genuine crop)
    passed = (score >= 75) and (good_ssim == 4)
    
    if passed:
        feedback_parts.append("SUCCESS: All video wall panels perfectly sliced and verified.")
    elif good_ssim < 4 and panels_found == 4:
        feedback_parts.append("FAILED: Outputs generated but spatial integrity failed. Do not scale/squish video; use precise cropping.")
        
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }