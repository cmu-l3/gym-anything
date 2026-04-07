#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import PIL for image verification
try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    logger.warning("PIL not available. Image dimension checks will be limited.")


def verify_retro_speedrun_capture_restoration(traj, env_info, task_info):
    """
    Verify the retro speedrun restoration task.
    
    Rubric (100 points, Pass Threshold: 70):
    1. Clean Video Exists & Codecs (H264/AAC): 15 pts
    2. Perfect Crop (688x448 resolution): 20 pts
    3. Audio Demux (MP3, no video stream): 15 pts
    4. Victory Thumbnail (PNG, exactly 688x448): 15 pts
    5. Manifest JSON (Correct schema and values): 15 pts
    6. VLM Trajectory (Workflow verification): 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    score = 0
    feedback_parts = []
    
    # Extract temporary files
    files_to_copy = {
        'result': '/tmp/task_result.json',
        'clean_run_probe': '/tmp/clean_run_probe.json',
        'run_audio_probe': '/tmp/run_audio_probe.json',
        'manifest': '/tmp/submission_manifest.json',
        'thumbnail': '/tmp/victory_thumbnail.png'
    }
    
    local_paths = {}
    temp_dir = tempfile.mkdtemp()
    
    try:
        for key, remote_path in files_to_copy.items():
            local_path = os.path.join(temp_dir, os.path.basename(remote_path))
            try:
                copy_from_env(remote_path, local_path)
                local_paths[key] = local_path
            except Exception:
                local_paths[key] = None

        # --- 0. Load Task Status ---
        if local_paths['result'] and os.path.exists(local_paths['result']):
            with open(local_paths['result'], 'r') as f:
                result = json.load(f)
        else:
            return {"passed": False, "score": 0, "feedback": "Failed to read task result from container"}
            
        task_start = result.get('task_start', 0)
        
        # --- 1 & 2. Clean Video & Perfect Crop (35 pts total) ---
        clean_run = result.get('clean_run', {})
        if clean_run.get('exists') and clean_run.get('mtime', 0) >= task_start:
            probe_path = local_paths['clean_run_probe']
            if probe_path and os.path.exists(probe_path):
                with open(probe_path, 'r') as f:
                    v_probe = json.load(f)
                    
                streams = v_probe.get('streams', [])
                v_stream = next((s for s in streams if s.get('codec_type') == 'video'), None)
                a_stream = next((s for s in streams if s.get('codec_type') == 'audio'), None)
                
                if v_stream and a_stream:
                    # Check codecs
                    if v_stream.get('codec_name') == 'h264' and a_stream.get('codec_name') == 'aac':
                        score += 15
                        feedback_parts.append("Clean video has correct codecs (H.264/AAC)")
                    else:
                        feedback_parts.append(f"Clean video incorrect codecs: {v_stream.get('codec_name')}/{a_stream.get('codec_name')}")
                        
                    # Check PERFECT crop (688x448)
                    width = v_stream.get('width', 0)
                    height = v_stream.get('height', 0)
                    if width == 688 and height == 448:
                        score += 20
                        feedback_parts.append("Clean video perfectly cropped to 688x448")
                    else:
                        feedback_parts.append(f"Clean video incorrect resolution: {width}x{height} (expected 688x448)")
                else:
                    feedback_parts.append("Clean video is missing audio or video streams")
        else:
            feedback_parts.append("Clean video missing or not created during task")

        # --- 3. Audio Demux (15 pts) ---
        run_audio = result.get('run_audio', {})
        if run_audio.get('exists') and run_audio.get('mtime', 0) >= task_start:
            probe_path = local_paths['run_audio_probe']
            if probe_path and os.path.exists(probe_path):
                with open(probe_path, 'r') as f:
                    a_probe = json.load(f)
                    
                streams = a_probe.get('streams', [])
                has_video = any(s.get('codec_type') == 'video' for s in streams)
                a_stream = next((s for s in streams if s.get('codec_type') == 'audio'), None)
                
                if a_stream and a_stream.get('codec_name') == 'mp3' and not has_video:
                    score += 15
                    feedback_parts.append("Audio standalone extracted correctly (MP3, no video)")
                else:
                    feedback_parts.append("Audio extraction failed codec or stream-isolation checks")
        else:
            feedback_parts.append("Standalone audio missing or not created during task")

        # --- 4. Victory Thumbnail (15 pts) ---
        thumbnail = result.get('thumbnail', {})
        if thumbnail.get('exists') and thumbnail.get('mtime', 0) >= task_start:
            thumb_path = local_paths['thumbnail']
            if thumb_path and os.path.exists(thumb_path) and PIL_AVAILABLE:
                try:
                    with Image.open(thumb_path) as img:
                        if img.format == 'PNG' and img.size == (688, 448):
                            score += 15
                            feedback_parts.append("Victory thumbnail is perfect (PNG, 688x448)")
                        else:
                            feedback_parts.append(f"Thumbnail format/size mismatch: {img.format} {img.size}")
                except Exception as e:
                    feedback_parts.append("Thumbnail is a corrupt image file")
            elif not PIL_AVAILABLE:
                # Give grace if PIL isn't available but file exists and has size
                if thumbnail.get('size', 0) > 1000:
                    score += 15
                    feedback_parts.append("Victory thumbnail exists (content assumed valid, PIL missing)")
        else:
            feedback_parts.append("Victory thumbnail missing or not created during task")

        # --- 5. Manifest JSON (15 pts) ---
        manifest_meta = result.get('manifest', {})
        if manifest_meta.get('exists') and manifest_meta.get('mtime', 0) >= task_start:
            manifest_path = local_paths['manifest']
            if manifest_path and os.path.exists(manifest_path):
                try:
                    with open(manifest_path, 'r') as f:
                        manifest = json.load(f)
                    
                    # Validate schema
                    r_name = manifest.get('runner')
                    o_res = manifest.get('original_resolution')
                    c_res = manifest.get('cropped_resolution')
                    deint = manifest.get('deinterlaced')
                    
                    if r_name == 'ga_agent' and o_res == '720x480' and c_res == '688x448' and deint is True:
                        score += 15
                        feedback_parts.append("Manifest JSON contains correct properties")
                    else:
                        feedback_parts.append("Manifest JSON has incorrect or missing values")
                except json.JSONDecodeError:
                    feedback_parts.append("Manifest is invalid JSON")
        else:
            feedback_parts.append("Manifest missing or not created during task")

        # --- 6. VLM Trajectory Verification (20 pts) ---
        # Prove the agent actually executed software to achieve this
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = (
                "You are auditing an agent performing media restoration. "
                "The agent's goal was to crop a video, convert formats, and extract a snapshot. "
                "Look at these chronological frames from the agent's screen.\n"
                "Do you see clear visual evidence of the agent interacting with VLC Media Player's settings/menus, "
                "OR typing commands into a terminal (like ffmpeg) to manipulate video?\n"
                "Respond in JSON format with exactly this schema:\n"
                "{\"used_media_tools\": true/false, \"observations\": \"briefly describe tool usage visible\"}"
            )
            
            try:
                vlm_result = query_vlm(images=frames, prompt=prompt)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("used_media_tools"):
                        score += 20
                        feedback_parts.append("VLM confirmed usage of media manipulation tools")
                    else:
                        feedback_parts.append("VLM did not detect interaction with media manipulation tools")
                else:
                    feedback_parts.append("VLM query failed or returned no parsable success")
            except Exception as e:
                logger.warning(f"VLM Exception: {e}")
                feedback_parts.append("VLM verification threw an exception")
        else:
            feedback_parts.append("No trajectory frames available for VLM verification")

    finally:
        # Cleanup
        for path in local_paths.values():
            if path and os.path.exists(path):
                try: os.unlink(path)
                except: pass
        try: os.rmdir(temp_dir)
        except: pass

    # Evaluation
    key_criteria_met = score >= 70
    passed = key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }