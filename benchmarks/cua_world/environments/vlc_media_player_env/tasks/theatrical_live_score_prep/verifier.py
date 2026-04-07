#!/usr/bin/env python3
"""
Verifier for Theatrical Live-Score Synchronization Prep.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Duration/Retiming (GATE): Both videos must be ~80s. Failing this implies frames were dropped rather than PTS stretched. (30 points)
2. Framerate: Must be strictly 18 fps. (15 points)
3. Streams: Projection = no audio. Conductor = audio present. (15 points)
4. Visual Timecode (VLM): Checks trajectory frames for top-right timecode burn-in. (30 points)
5. JSON Manifest: Valid JSON with expected properties. (10 points)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def copy_and_read_json(copy_from_env, container_path):
    """Helper to copy a JSON file from the container and parse it."""
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(container_path, temp_file.name)
        if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
            with open(temp_file.name, 'r') as f:
                return json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read {container_path}: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    return None

def parse_ffprobe_data(info):
    """Extracts duration, fps, video stream count, and audio stream count."""
    if not info or 'error' in info:
        return None
    
    parsed = {
        'duration': 0.0,
        'fps': 0.0,
        'video_streams': 0,
        'audio_streams': 0
    }
    
    if 'format' in info and 'duration' in info['format']:
        parsed['duration'] = float(info['format']['duration'])
        
    for stream in info.get('streams', []):
        if stream.get('codec_type') == 'video':
            parsed['video_streams'] += 1
            # Parse r_frame_rate (e.g., "18/1")
            fps_str = stream.get('r_frame_rate', '0/1')
            try:
                num, den = map(int, fps_str.split('/'))
                parsed['fps'] = num / den if den > 0 else 0
            except:
                pass
        elif stream.get('codec_type') == 'audio':
            parsed['audio_streams'] += 1
            
    return parsed

def verify_theatrical_live_score_prep(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_dur = metadata.get('expected_duration', 80.0)
    dur_tol = metadata.get('duration_tolerance', 1.5)
    expected_fps = metadata.get('expected_fps', 18)

    feedback_parts = []
    score = 0
    
    # Read outputs
    proj_info = copy_and_read_json(copy_from_env, "/tmp/projection_info.json")
    cond_info = copy_and_read_json(copy_from_env, "/tmp/conductor_info.json")
    manifest = copy_and_read_json(copy_from_env, "/tmp/delivery_manifest.json")
    
    proj_parsed = parse_ffprobe_data(proj_info)
    cond_parsed = parse_ffprobe_data(cond_info)

    if not proj_parsed and not cond_parsed:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Deliverables not found. No media files were exported."
        }

    # ================================================================
    # 1. DURATION / PTS RETIMING GATE (30 points)
    # ================================================================
    durations_ok = 0
    gate_passed = False
    
    if proj_parsed:
        if abs(proj_parsed['duration'] - expected_dur) <= dur_tol:
            durations_ok += 1
            feedback_parts.append(f"Projection duration OK ({proj_parsed['duration']:.1f}s)")
        else:
            feedback_parts.append(f"Projection duration FAIL: {proj_parsed['duration']:.1f}s (expected 80s)")
            
    if cond_parsed:
        if abs(cond_parsed['duration'] - expected_dur) <= dur_tol:
            durations_ok += 1
            feedback_parts.append(f"Conductor duration OK ({cond_parsed['duration']:.1f}s)")
        else:
            feedback_parts.append(f"Conductor duration FAIL: {cond_parsed['duration']:.1f}s (expected 80s)")

    if durations_ok == 2:
        score += 30
        gate_passed = True
        feedback_parts.append("GATE PASSED: Media was properly retimed (PTS stretched).")
    elif durations_ok == 1:
        score += 15
        feedback_parts.append("GATE PARTIAL: Only one file properly retimed.")
    else:
        feedback_parts.append("GATE FAILED: Media duration remains ~60s. Frames were dropped, not stretched.")
        # Automatic failure if the primary mechanical requirement wasn't met
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # ================================================================
    # 2. FRAMERATE CHECK (15 points)
    # ================================================================
    fps_score = 0
    if proj_parsed and abs(proj_parsed['fps'] - expected_fps) < 0.1:
        fps_score += 7.5
    if cond_parsed and abs(cond_parsed['fps'] - expected_fps) < 0.1:
        fps_score += 7.5
        
    score += fps_score
    if fps_score == 15:
        feedback_parts.append("Framerates exact (18 fps)")
    else:
        feedback_parts.append("Framerate mismatch detected")

    # ================================================================
    # 3. STREAM MANAGEMENT (15 points)
    # ================================================================
    stream_score = 0
    if proj_parsed and proj_parsed['audio_streams'] == 0:
        stream_score += 7.5
        feedback_parts.append("Projection is silent (correct)")
    else:
        feedback_parts.append("Projection contains audio (incorrect)")

    if cond_parsed and cond_parsed['audio_streams'] > 0:
        stream_score += 7.5
        feedback_parts.append("Conductor contains audio (correct)")
    else:
        feedback_parts.append("Conductor missing audio (incorrect)")
    
    score += stream_score

    # ================================================================
    # 4. JSON MANIFEST (10 points)
    # ================================================================
    if manifest and not manifest.get('error'):
        # Just verifying it's valid JSON with some minimal content
        str_manifest = json.dumps(manifest).lower()
        if 'duration' in str_manifest and ('framerate' in str_manifest or 'fps' in str_manifest):
            score += 10
            feedback_parts.append("Manifest JSON valid")
        else:
            score += 5
            feedback_parts.append("Manifest JSON missing required fields")
    else:
        feedback_parts.append("Manifest JSON missing or invalid")

    # ================================================================
    # 5. VLM TIMECODE VERIFICATION (30 points)
    # ================================================================
    vlm_score = 0
    if query_vlm:
        # Sample trajectory frames (skip the very beginning)
        frames = sample_trajectory_frames(traj, n=4)[1:] 
        prompt = """
        You are reviewing screenshots of an agent performing video manipulation.
        Look closely at the video playback window or final output state in these frames.
        Did the agent successfully burn a running visual timecode (numbers like MM:SS or HH:MM:SS) into the top-right corner of the video?
        Respond in JSON format:
        {
            "timecode_visible_top_right": true/false,
            "observations": "Brief description of what you see in the top right area"
        }
        """
        try:
            result = query_vlm(prompt=prompt, images=frames)
            if result.get("success"):
                parsed = result.get("parsed", {})
                if parsed.get("timecode_visible_top_right", False):
                    vlm_score = 30
                    feedback_parts.append("VLM: Timecode verified in top-right.")
                else:
                    feedback_parts.append("VLM: Timecode NOT found in top-right.")
            else:
                feedback_parts.append("VLM error: " + result.get('error', 'unknown'))
        except Exception as e:
            feedback_parts.append(f"VLM exception: {e}")
    else:
        feedback_parts.append("VLM not available, skipping visual check.")
        
    score += vlm_score

    # Final Evaluation
    passed = (score >= 75) and gate_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }