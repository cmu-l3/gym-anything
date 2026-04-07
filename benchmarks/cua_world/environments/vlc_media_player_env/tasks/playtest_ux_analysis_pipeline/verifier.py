#!/usr/bin/env python3
"""
Verifier for the playtest UX analysis pipeline task.

Criteria and Scoring (100 pts total):
1. Extracted Audio (20 pts): MP3, Mono, ~120s duration.
2. Highlight Video Trim (15 pts): MP4, H.264, ~20s duration.
3. Highlight Audio Track (20 pts): AAC, Mono (CRITICAL: proves Track 2 was selected).
4. Snapshots Existence (15 pts): 3 distinct PNG files.
5. JSON Manifest (15 pts): Valid JSON, correct properties.
6. VLM Trajectory (15 pts): Visual evidence of workflow execution using tools.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_playtest_ux_analysis_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch export info
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ux_export_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extracted Audio Check (20 pts)
    voice_file = result.get('voice_file', {})
    voice_audio = result.get('voice_audio', {})
    if voice_file.get('exists') and voice_file.get('created_during_task'):
        score += 5
        try:
            duration = float(voice_audio.get('format', {}).get('duration', 0))
            if abs(duration - 120) <= 5:
                score += 5
        except (ValueError, TypeError):
            pass

        streams = voice_audio.get('streams', [])
        if streams:
            stream = streams[0]
            if stream.get('codec_name') == 'mp3':
                score += 5
            if stream.get('channels') == 1:
                score += 5
        feedback_parts.append("Voice audio processed successfully")
    else:
        feedback_parts.append("Voice audio missing or unchanged")

    # 3. Highlight Video Check (15 pts)
    highlight_file = result.get('highlight_file', {})
    highlight_video = result.get('highlight_video', {})
    highlight_audio = result.get('highlight_audio', {})
    highlight_audio_mono = False

    if highlight_file.get('exists') and highlight_file.get('created_during_task'):
        score += 5
        try:
            # Duration check (20s highlight)
            duration = float(highlight_video.get('format', {}).get('duration', 0))
            if duration == 0:
                duration = float(highlight_audio.get('format', {}).get('duration', 0))
                
            if abs(duration - 20) <= 3:
                score += 5
        except (ValueError, TypeError):
            pass

        # Check video codec
        streams_v = highlight_video.get('streams', [])
        if streams_v:
            if streams_v[0].get('codec_name') == 'h264':
                score += 5
                
        # 4. Highlight Audio Track Check (20 pts) - CRITICAL
        streams_a = highlight_audio.get('streams', [])
        if streams_a:
            stream_a = streams_a[0]
            if stream_a.get('codec_name') == 'aac':
                score += 5
            if stream_a.get('channels') == 1:
                score += 15
                highlight_audio_mono = True
                
        feedback_parts.append("Highlight video/audio processed successfully")
    else:
        feedback_parts.append("Highlight video missing or unchanged")

    # 5. Snapshots Check (15 pts)
    snaps_found = 0
    for snap in ['snap1', 'snap2', 'snap3']:
        info = result.get(snap, {})
        if info.get('exists') and info.get('created_during_task') and info.get('size', 0) > 10000:
            snaps_found += 1
    score += (snaps_found * 5)
    feedback_parts.append(f"{snaps_found}/3 valid snapshots found")

    # 6. JSON Manifest Check (15 pts)
    manifest_info = result.get('manifest_file', {})
    if manifest_info.get('exists') and manifest_info.get('created_during_task'):
        temp_manifest = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/ux_manifest.json", temp_manifest.name)
            with open(temp_manifest.name, 'r') as f:
                manifest_data = json.load(f)
            
            expected_keys = ['session_id', 'extracted_audio', 'highlight_clip', 'snapshots']
            if all(k in manifest_data for k in expected_keys):
                score += 15
                feedback_parts.append("Manifest exists with correct keys")
            else:
                score += 5
                feedback_parts.append("Manifest missing required keys")
        except Exception:
            score += 2
            feedback_parts.append("Manifest exists but is invalid JSON")
        finally:
            if os.path.exists(temp_manifest.name):
                os.unlink(temp_manifest.name)
    else:
        feedback_parts.append("Manifest missing or unchanged")

    # 7. VLM Trajectory Verification (15 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = """You are analyzing the trajectory of an agent completing a media extraction task.
The agent was asked to:
1. Extract a specific audio track from an MKV file.
2. Trim a 20-second video clip.
3. Capture exactly 3 timestamped screenshots.

Looking at these sampled frames, do you see evidence of the agent using media tools (like VLC, a video editor, or a terminal running ffmpeg) to accomplish these steps?
Return a JSON object:
{
    "evidence_of_media_tools": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}"""
                vlm_res = query_vlm(images=frames, prompt=prompt)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("evidence_of_media_tools", False):
                        vlm_score = 15
                        feedback_parts.append("VLM verified media tool usage")
                    else:
                        feedback_parts.append("VLM found no evidence of tool usage")
                else:
                    feedback_parts.append("VLM query failed")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification skipped (error)")
    else:
        feedback_parts.append("VLM not available")
    
    score += vlm_score

    # Evaluate final success
    # MUST have the highlight audio correctly separated (Mono) to ensure they actually picked Track 2
    key_criteria_met = highlight_audio_mono
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }