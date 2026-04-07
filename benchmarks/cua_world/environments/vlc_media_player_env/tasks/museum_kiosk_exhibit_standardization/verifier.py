#!/usr/bin/env python3
"""
Verifier for Museum Kiosk Exhibit Standardization task.
Checks video parameters, script commands, playlist validity, and visual watermark.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_museum_kiosk(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch the main result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    start_time = result.get("task_start_time", 0)

    # ---------------------------------------------------------
    # CRITERION 1: Video Standardization (Max 30 pts)
    # ---------------------------------------------------------
    videos = result.get("videos", {})
    all_standardized = True
    standardization_score = 0
    videos_found = 0

    for i in ["1", "2", "3"]:
        v = videos.get(i, {})
        if not v.get("exists", False):
            feedback_parts.append(f"exhibit_0{i}.mp4 missing")
            all_standardized = False
            continue
        
        # Anti-gaming: Ensure file was modified during the task
        if v.get("mtime", 0) < start_time:
            feedback_parts.append(f"exhibit_0{i}.mp4 was not newly generated")
            all_standardized = False
            continue

        videos_found += 1
        probe = v.get("ffprobe", {})
        streams = probe.get("streams", [])
        
        has_h264 = False
        has_aac = False
        is_1080p = False

        for stream in streams:
            if stream.get("codec_type") == "video":
                if stream.get("codec_name") == "h264":
                    has_h264 = True
                if stream.get("width") == 1920 and stream.get("height") == 1080:
                    is_1080p = True
            elif stream.get("codec_type") == "audio":
                if stream.get("codec_name") == "aac":
                    has_aac = True

        if is_1080p:
            standardization_score += 6.66  # ~20 points total for resolution
        else:
            all_standardized = False
            
        if has_h264 and has_aac:
            standardization_score += 3.33  # ~10 points total for codecs
        else:
            all_standardized = False

    score += int(standardization_score)
    if videos_found == 3:
        if all_standardized:
            feedback_parts.append("Videos standardized correctly (1080p/H.264/AAC)")
        else:
            feedback_parts.append("Videos found but formatting/resolution incorrect")

    # ---------------------------------------------------------
    # CRITERION 2: Playlist (Max 15 pts)
    # ---------------------------------------------------------
    playlist = result.get("playlist", {})
    if playlist.get("exists", False):
        content = playlist.get("content", "")
        # Basic XSPF parse via regex to avoid namespace hell
        tracks = re.findall(r'<location>([^<]+)</location>', content, re.IGNORECASE)
        # Check if the three files are present in order
        expected = ["exhibit_01.mp4", "exhibit_02.mp4", "exhibit_03.mp4"]
        
        # Extract just the filenames from the paths
        actual = [t.split('/')[-1] for t in tracks]
        
        if len(actual) >= 3 and expected == actual[:3]:
            score += 15
            feedback_parts.append("Valid XSPF playlist authored")
        elif all(e in content for e in expected):
            score += 5
            feedback_parts.append("Playlist exists but format/order is flawed")
        else:
            feedback_parts.append("Playlist exists but missing target files")
    else:
        feedback_parts.append("ocean_loop.xspf missing")

    # ---------------------------------------------------------
    # CRITERION 3: Deployment Script (Max 25 pts)
    # ---------------------------------------------------------
    script = result.get("script", {})
    if script.get("exists", False):
        if script.get("executable", False):
            score += 5
        else:
            feedback_parts.append("start_kiosk.sh is not executable")
            
        content = script.get("content", "")
        script_score = 0
        
        # Binary execution check
        if "vlc" in content or "cvlc" in content:
            # Flags check
            if "-f" in content or "--fullscreen" in content:
                script_score += 5
            if "-L" in content or "--loop" in content:
                script_score += 5
            if "--no-osd" in content:
                script_score += 5
            if "--no-video-title-show" in content:
                script_score += 5
                
            score += script_score
            feedback_parts.append(f"Script flag score: {script_score}/20")
        else:
            feedback_parts.append("start_kiosk.sh does not invoke VLC")
    else:
        feedback_parts.append("start_kiosk.sh missing")

    # ---------------------------------------------------------
    # CRITERION 4: Visual Watermark Burn-in (Max 30 pts)
    # ---------------------------------------------------------
    watermark_score = 0
    if result.get("frame_extracted", False):
        temp_frame = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_logo = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/watermark_frame.png", temp_frame.name)
            copy_from_env("/tmp/museum_logo.png", temp_logo.name)
            
            try:
                import cv2
                import numpy as np
                frame = cv2.imread(temp_frame.name)
                logo = cv2.imread(temp_logo.name)
                
                if frame is not None and logo is not None:
                    # Look at the bottom right quadrant
                    h, w = frame.shape[:2]
                    quadrant = frame[h//2:, w//2:]
                    
                    # Template match
                    res = cv2.matchTemplate(quadrant, logo, cv2.TM_CCOEFF_NORMED)
                    if np.max(res) >= 0.7:  # Threshold for visible watermark presence
                        watermark_score = 30
                        feedback_parts.append("Watermark burn-in verified (OpenCV)")
                    else:
                        feedback_parts.append("Watermark not detected in bottom-right")
            except ImportError:
                # If CV2 is not available, we use VLM on the trajectory/frame
                from gym_anything.vlm import query_vlm, get_final_screenshot
                final_img = get_final_screenshot(traj)
                
                prompt = "Look at the screenshot. Does it show VLC or a video frame with a circular blue 'MUSEUM OCEAN' logo permanently burned into the bottom-right corner?"
                try:
                    vlm_res = query_vlm(prompt=prompt, image=final_img)
                    if vlm_res.get("success") and "yes" in str(vlm_res.get("response", "")).lower():
                        watermark_score = 30
                        feedback_parts.append("Watermark burn-in verified (VLM fallback)")
                    else:
                        feedback_parts.append("Watermark burn-in unverified visually")
                except Exception:
                    feedback_parts.append("Watermark visual verification skipped (No CV2/VLM)")
        finally:
            if os.path.exists(temp_frame.name):
                os.unlink(temp_frame.name)
            if os.path.exists(temp_logo.name):
                os.unlink(temp_logo.name)
    else:
        feedback_parts.append("Could not extract frame for watermark check")

    score += watermark_score

    # Determine Pass/Fail
    # To pass, they need at least 70 points AND must have successfully watermarked + created playlist
    passed = score >= 70 and watermark_score > 0 and playlist.get("exists", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }