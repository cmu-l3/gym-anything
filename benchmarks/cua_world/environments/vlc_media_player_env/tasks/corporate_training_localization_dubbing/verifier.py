#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_corporate_localization(traj, env_info, task_info):
    """
    Verify the corporate training localization task.
    
    Criteria:
    1. Output file exists and was created during the task (20 pts)
    2. Container Stream check: 1 Video, 1 Audio, 0 Subtitles (15 pts) - Anti-softsub gate
    3. Visual Verification (VLM): Watermark is present (25 pts)
    4. Visual Verification (VLM): French text is hardsubbed (20 pts)
    5. Trajectory Verification (VLM): Audio track was replaced during workflow (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    vlm = env_info.get('vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve programmatic results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if output_exists:
        if created_during:
            score += 20
            feedback_parts.append("Output file created successfully (+20)")
        else:
            feedback_parts.append("Output file exists but was not created during task (0)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("Output file not found. Task failed.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Container Streams Check
    v_streams = int(result.get('video_streams', 0))
    a_streams = int(result.get('audio_streams', 0))
    s_streams = int(result.get('subtitle_streams', 0))
    
    if v_streams >= 1 and a_streams >= 1:
        if s_streams == 0:
            score += 15
            feedback_parts.append("Valid container structure with no soft-subs (+15)")
        else:
            feedback_parts.append(f"FAIL: Found {s_streams} soft-subtitle streams. Captions must be hardsubbed (burned into video).")
    else:
        feedback_parts.append(f"Invalid streams: {v_streams} video, {a_streams} audio")

    # 3 & 4. Visual Verification of Frame 15s (Hardsub and Watermark)
    temp_frame = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    frame_copied = False
    try:
        copy_from_env("/tmp/frame_15s.png", temp_frame.name)
        if os.path.exists(temp_frame.name) and os.path.getsize(temp_frame.name) > 0:
            frame_copied = True
    except Exception:
        pass

    if frame_copied and vlm:
        prompt = """You are verifying an exported video frame for a localized corporate video.
Look closely at the image:
1. Is there a red square/watermark logo visible in the video (likely in the corner)?
2. Is there French text visually burned into the frame (hardsubbed) that reads 'Bienvenue dans la formation de conformité.'?

Respond EXACTLY with a JSON dictionary in this format:
{"watermark_visible": true/false, "hardsub_visible": true/false}"""

        try:
            vlm_response = vlm(prompt=prompt, image=temp_frame.name)
            if vlm_response.get("success") and vlm_response.get("parsed"):
                parsed = vlm_response["parsed"]
                
                if parsed.get("watermark_visible"):
                    score += 25
                    feedback_parts.append("VLM verified watermark is present (+25)")
                else:
                    feedback_parts.append("VLM did not detect the watermark")
                    
                if parsed.get("hardsub_visible"):
                    score += 20
                    feedback_parts.append("VLM verified French hardsubs are present (+20)")
                else:
                    feedback_parts.append("VLM did not detect the French hardsubbed text")
        except Exception as e:
            logger.warning(f"VLM visual frame check failed: {e}")
            feedback_parts.append("VLM visual verification skipped/failed")
    else:
        feedback_parts.append("Could not extract frame or VLM unavailable for visual check")

    if os.path.exists(temp_frame.name):
        os.unlink(temp_frame.name)

    # 5. Trajectory Verification (Audio track replacement via VLC)
    if vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = """You are analyzing a sequence of screenshots from a user configuring VLC Media Player.
The user's goal is to replace the original video's audio track with a translated French dub.
Look through the screenshots for evidence that the user clicked 'Show more options', checked 'Play another media synchronously', and selected a secondary audio file (e.g., french_dub_track.mp3).
Did the user properly configure VLC to replace/add the secondary audio track?

Respond EXACTLY with a JSON dictionary in this format:
{"audio_replaced": true/false}"""

        try:
            vlm_response = vlm(prompt=prompt, images=frames)
            if vlm_response.get("success") and vlm_response.get("parsed"):
                parsed = vlm_response["parsed"]
                if parsed.get("audio_replaced"):
                    score += 20
                    feedback_parts.append("VLM trajectory verified audio replacement workflow (+20)")
                else:
                    feedback_parts.append("VLM trajectory did not clearly show audio replacement workflow")
        except Exception as e:
            logger.warning(f"VLM trajectory check failed: {e}")

    # Final Evaluation
    # Key criteria: File exists, no soft-subs, and at least 70 points
    key_criteria_met = output_exists and created_during and s_streams == 0
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }