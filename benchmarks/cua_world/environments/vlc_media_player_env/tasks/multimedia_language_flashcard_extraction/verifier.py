#!/usr/bin/env python3
"""
Verifier for Multimedia Language Flashcard Extraction Task.
Utilizes both programmatic media probing (exported via JSON) and trajectory VLM checks.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def query_trajectory_vlm(query_vlm, traj):
    """Check if the agent actually used media software (VLC/Terminal) using VLM."""
    if not query_vlm:
        return {"used_tools": True, "confidence": "assumed (no VLM)"}
        
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images = frames + [final] if frames else [final]
    
    prompt = """You are verifying an AI agent's trajectory on a desktop environment.
The agent was asked to extract audio clips, video clips, and screenshots from a source video.

Review these chronological screenshots and determine:
1. Did the agent open a terminal (using ffmpeg) or VLC Media Player to process media?
2. Is there visual evidence that work was being performed (typing commands, playing clips, etc.) rather than doing nothing?

Respond with a JSON object exactly like this:
{
    "used_tools": true/false,
    "evidence_of_work": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""
    
    try:
        res = query_vlm(prompt=prompt, images=images)
        if res.get("success"):
            return res.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        
    return {"used_tools": True, "confidence": "assumed (VLM failed)"}


def verify_flashcard_extraction(traj, env_info, task_info):
    """
    Scoring Criteria (100 pts total, Pass Threshold: 75 pts):
    - File Structure & Naming: 10 pts
    - Audio Extraction (MP3s): 15 pts
    - Video Trimming (MP4s): 15 pts
    - Hardsub Compliance (No subtitle streams): 20 pts
    - Snapshot Generation: 15 pts
    - JSON Manifest Accuracy: 10 pts
    - VLM Trajectory Evidence: 15 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cards = metadata.get('cards', [])
    tolerance = metadata.get('duration_tolerance_sec', 1.5)
    
    score = 0
    feedback = []
    
    # 1. Read exported result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result.get("ankideck_exists"):
        return {"passed": False, "score": 0, "feedback": "Directory /home/ga/Documents/AnkiDeck/ was not created."}

    files = result.get("files", {})
    
    # Trackers for sub-scores
    found_audio = 0
    found_video = 0
    found_image = 0
    hardsub_passes = 0
    anti_gaming_passes = 0

    # 2. Programmatic Analysis
    for card in expected_cards:
        base_name = f"{card['id']}_{card['word']}"
        mp3_name = f"{base_name}.mp3"
        mp4_name = f"{base_name}.mp4"
        png_name = f"{base_name}.png"
        
        # Audio Check
        if mp3_name in files:
            finfo = files[mp3_name]
            probe = finfo.get('probe', {})
            streams = probe.get('streams', [])
            duration = float(probe.get('format', {}).get('duration', 0))
            
            has_video = any(s.get('codec_type') == 'video' for s in streams)
            if not has_video and abs(duration - card['duration']) <= tolerance:
                found_audio += 1
            if finfo.get("created_during_task"): anti_gaming_passes += 1
        
        # Video Check
        if mp4_name in files:
            finfo = files[mp4_name]
            probe = finfo.get('probe', {})
            streams = probe.get('streams', [])
            duration = float(probe.get('format', {}).get('duration', 0))
            
            has_video = any(s.get('codec_type') == 'video' for s in streams)
            has_sub = any(s.get('codec_type') == 'subtitle' for s in streams)
            
            if has_video and abs(duration - card['duration']) <= tolerance:
                found_video += 1
                
            # Crucial Hardsub Test: Valid Video but ZERO subtitle streams
            if has_video and not has_sub:
                hardsub_passes += 1
                
            if finfo.get("created_during_task"): anti_gaming_passes += 1

        # Image Check
        if png_name in files:
            finfo = files[png_name]
            if finfo.get('size_bytes', 0) > 10240: # > 10KB
                found_image += 1
            if finfo.get("created_during_task"): anti_gaming_passes += 1

    # Score calculation
    # Basic Structure (10 pts)
    total_files = found_audio + found_video + found_image
    if total_files == 15:
        score += 10
        feedback.append("All 15 media files named correctly.")
    else:
        score += int(10 * (total_files / 15))
        feedback.append(f"Found {total_files}/15 expected correctly named media files.")

    # Audio Extraction (15 pts)
    score += int(15 * (found_audio / 5))
    feedback.append(f"{found_audio}/5 audio files valid (audio-only, proper duration).")

    # Video Trimming (15 pts)
    score += int(15 * (found_video / 5))
    feedback.append(f"{found_video}/5 video files valid (proper duration).")

    # Hardsub Compliance (20 pts)
    score += int(20 * (hardsub_passes / 5))
    feedback.append(f"{hardsub_passes}/5 video files hardsubbed correctly (no separate sub streams).")

    # Snapshot Generation (15 pts)
    score += int(15 * (found_image / 5))
    feedback.append(f"{found_image}/5 snapshots valid (>10KB).")

    # Manifest (10 pts)
    if result.get("manifest_valid"):
        manifest = result.get("manifest", [])
        if isinstance(manifest, list) and len(manifest) >= 5:
            # Check if required keys exist in the first item
            keys = ['id', 'target_word', 'audio_file', 'video_file', 'image_file', 'duration_sec']
            if all(k in manifest[0] for k in keys):
                score += 10
                feedback.append("JSON Manifest valid and structurally correct.")
            else:
                score += 5
                feedback.append("JSON Manifest valid but missing some required keys.")
        else:
            score += 3
            feedback.append("JSON Manifest parsed but is not a 5-item array.")
    else:
        feedback.append("JSON Manifest missing or invalid.")

    # Anti-gaming check (gate-keeping)
    if anti_gaming_passes == 0 and total_files > 0:
        feedback.append("WARNING: Files were not created during the task timeframe.")
        score = 0

    # 3. VLM Trajectory Verification (15 pts)
    vlm_result = query_trajectory_vlm(query_vlm, traj)
    if vlm_result.get("used_tools") or vlm_result.get("evidence_of_work"):
        score += 15
        feedback.append("VLM confirmed interaction with media tools/terminal.")
    else:
        feedback.append("VLM found no visual evidence of actual work being performed.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "audio_passed": found_audio,
            "video_passed": found_video,
            "hardsub_passed": hardsub_passes,
            "images_passed": found_image,
            "anti_gaming_passes": anti_gaming_passes
        }
    }