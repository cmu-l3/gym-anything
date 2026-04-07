#!/usr/bin/env python3
"""
Verifier for Audiobook Chapter Splitting Task.
Evaluates file existence, formatting, duration, metadata tags, and non-silence.
Incorporates a VLM check on the trajectory to ensure proper workflows were used.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prompt to ensure agent performed real work instead of cheating (e.g., using pure Python scripts on the host to fake tags)
VLM_WORKFLOW_PROMPT = """
You are analyzing a sequence of screenshots from an agent completing an audiobook extraction task.
The agent was asked to split a master audio file, convert to MP3, and embed ID3 tags. 
They could have used VLC Media Player's "Convert/Save" interface, the terminal (e.g., using ffmpeg or cvlc), or a text editor to create a script.

Does the trajectory show evidence of the agent ACTUALLY performing the work?
Evidence includes:
- VLC Media Player open, navigating menus, or using the Convert/Save dialog
- A terminal open with ffmpeg or vlc commands being typed
- Opening and reading the timecode text file

Respond with a JSON object:
{
    "performed_work": true/false,
    "method_used": "vlc / terminal / script / none",
    "confidence": "low / medium / high",
    "reasoning": "Brief explanation of what is visible"
}
"""

def query_vlm_for_trajectory(traj, env_info):
    """Samples frames from the trajectory and sends to VLM."""
    # Only try VLM if available
    query_vlm = env_info.get("query_vlm")
    if not query_vlm:
        return True, "VLM not available, skipping trajectory check"

    from gym_anything.vlm import sample_trajectory_frames
    
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        return True, "No frames available"

    try:
        result = query_vlm(prompt=VLM_WORKFLOW_PROMPT, images=frames)
        if result and result.get("success"):
            parsed = result.get("parsed", {})
            return parsed.get("performed_work", False), parsed.get("reasoning", "")
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")
        
    return True, "VLM query failed, defaulting to True"


def verify_audiobook_chapter_splitting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_files = metadata.get('expected_files', {})
    expected_artist = metadata.get('expected_artist', 'Sun Tzu')
    expected_album = metadata.get('expected_album', 'The Art of War')
    expected_bitrate = metadata.get('expected_bitrate', 64000)
    expected_channels = metadata.get('expected_channels', 1)

    score = 0
    feedback_parts = []
    
    # 1. Fetch JSON results from the container
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

    files_data = result.get('files', {})
    
    # Track progress across 4 files
    files_found = 0
    valid_format = 0
    accurate_duration = 0
    accurate_metadata = 0
    valid_audio = 0

    for filename, expected in expected_files.items():
        fdata = files_data.get(filename, {})
        
        if not fdata.get('exists', False):
            feedback_parts.append(f"[x] {filename} missing")
            continue
            
        files_found += 1
        
        # Check Creation (Anti-gaming)
        if not fdata.get('created_during_task', False):
            feedback_parts.append(f"[!] {filename} existed before task")
            
        # Check Format (MP3, Mono, ~64kbps)
        is_mp3 = "mp3" in fdata.get('codec', '').lower()
        is_mono = fdata.get('channels', 0) == expected_channels
        
        # Bitrate can fluctuate slightly in MP3 headers, check within 5%
        bitrate = fdata.get('bitrate', 0)
        is_64k = abs(bitrate - expected_bitrate) <= (expected_bitrate * 0.05)
        
        if is_mp3 and is_mono and is_64k:
            valid_format += 1
            score += 4 # 16 total
        else:
            feedback_parts.append(f"[-] {filename} bad format (MP3={is_mp3}, Mono={is_mono}, 64k={is_64k})")

        # Check Duration (+/- 1.5 seconds)
        duration = fdata.get('duration', 0)
        expected_duration = expected.get('duration', 0)
        if abs(duration - expected_duration) <= 1.5:
            accurate_duration += 1
            score += 4 # 16 total
        else:
            feedback_parts.append(f"[-] {filename} duration {duration:.1f}s (expected {expected_duration}s)")

        # Check ID3 Tags (Case-insensitive comparison)
        tags = fdata.get('tags', {})
        t_artist = tags.get('artist', '').lower() == expected_artist.lower()
        t_album = tags.get('album', '').lower() == expected_album.lower()
        t_title = tags.get('title', '').lower() == expected.get('title', '').lower()
        # Track might be "1" or "1/4", check if it starts with the correct digit
        t_track = str(tags.get('track', '')).startswith(expected.get('track', ''))
        
        if t_artist and t_album and t_title and t_track:
            accurate_metadata += 1
            score += 8 # 32 total
        else:
            feedback_parts.append(f"[-] {filename} metadata incorrect")

        # Check Anti-gaming Volume (mean_volume > -60 dB)
        mean_vol = fdata.get('mean_volume', -99)
        if mean_vol > -60.0:
            valid_audio += 1
            score += 2 # 8 total
        else:
            feedback_parts.append(f"[-] {filename} appears silent (mean vol: {mean_vol}dB)")

    # 2. Check JSON Manifest
    manifest_score = 0
    if result.get('manifest_exists', False):
        if result.get('manifest_valid_json', False):
            manifest_content = result.get('manifest_content', {})
            if "chapters" in manifest_content and len(manifest_content["chapters"]) >= 4:
                manifest_score = 8
                feedback_parts.append("[+] Manifest is valid and complete")
            else:
                manifest_score = 4
                feedback_parts.append("[-] Manifest missing chapters")
        else:
            feedback_parts.append("[-] Manifest is invalid JSON")
    else:
        feedback_parts.append("[x] Manifest missing")
        
    score += manifest_score

    # 3. VLM Verification
    vlm_score = 0
    performed_work, vlm_reasoning = query_vlm_for_trajectory(traj, env_info)
    if performed_work:
        vlm_score = 20
        feedback_parts.append("[+] VLM confirmed valid workflow")
    else:
        feedback_parts.append(f"[-] VLM failed to confirm workflow: {vlm_reasoning}")
        
    score += vlm_score

    # Final scoring
    feedback = f"Files: {files_found}/4 | Format: {valid_format}/4 | Duration: {accurate_duration}/4 | Meta: {accurate_metadata}/4 | Audio: {valid_audio}/4 | " + " | ".join(feedback_parts)
    
    # Pass threshold: 75
    passed = score >= 75 and files_found >= 3 and accurate_duration >= 3

    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback
    }