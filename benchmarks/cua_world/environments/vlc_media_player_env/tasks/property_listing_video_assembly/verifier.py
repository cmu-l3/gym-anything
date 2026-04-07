#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_property_listing_video_assembly(traj, env_info, task_info):
    """
    Verifies property_listing_video_assembly task.
    Combines deep programmatic file inspection (via JSON payload from export_result.sh)
    and VLM-based trajectory analysis to prevent programmatic shortcutting.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    files = result.get("files", {})

    # 1. Anti-Gaming timestamp checks
    created_during_task = True
    for fname, finfo in files.items():
        if finfo.get("exists") and not finfo.get("created_during_task", False):
            created_during_task = False

    if created_during_task:
        score += 3
        feedback_parts.append("Anti-gaming: Outputs created during task (+3)")
    else:
        feedback_parts.append("Anti-gaming failed: Pre-existing files detected (0)")

    # 2. Master Video
    master = files.get("listing_master.mp4", {})
    if master.get("exists") and master.get("size_bytes", 0) > 1000:
        score += 3
        feedback_parts.append("Master exists (+3)")
        if master.get("width") == 1920 and master.get("height") == 1080:
            score += 3
            feedback_parts.append("Master res 1080p (+3)")
        if 30 <= master.get("duration", 0) <= 34:
            score += 3
            feedback_parts.append("Master duration ~32s (+3)")
        if master.get("has_audio"):
            score += 2
            feedback_parts.append("Master has audio (+2)")
        if master.get("v_codec") == "h264":
            score += 2
            feedback_parts.append("Master H.264 codec (+2)")

    # 3. Mobile Video
    mobile = files.get("listing_mobile.mp4", {})
    if mobile.get("exists"):
        if mobile.get("width") == 1280 and mobile.get("height") == 720:
            score += 4
            feedback_parts.append("Mobile res 720p (+4)")
        if 30 <= mobile.get("duration", 0) <= 34:
            score += 2
            feedback_parts.append("Mobile duration ~32s (+2)")

    # 4. Square Video
    square = files.get("listing_square.mp4", {})
    if square.get("exists"):
        if square.get("width") == 1080 and square.get("height") == 1080:
            score += 5
            feedback_parts.append("Square res 1080x1080 (+5)")
        if 30 <= square.get("duration", 0) <= 34:
            score += 2
            feedback_parts.append("Square duration ~32s (+2)")

    # 5. Email Video
    email = files.get("listing_email.mp4", {})
    if email.get("exists"):
        if email.get("width") == 640 and email.get("height") == 360:
            score += 3
            feedback_parts.append("Email res 360p (+3)")
        if email.get("size_bytes", float('inf')) < 8 * 1024 * 1024:
            score += 3
            feedback_parts.append("Email size < 8MB (+3)")
        if email.get("has_audio"):
            score += 2
            feedback_parts.append("Email has audio (+2)")

    # 6. Thumbnail
    thumb = files.get("listing_thumbnail.jpg", {})
    if thumb.get("exists"):
        if thumb.get("format") == "JPEG" and abs(thumb.get("width", 0)-400) <= 20 and abs(thumb.get("height", 0)-300) <= 20:
            score += 3
            feedback_parts.append("Thumbnail valid JPEG 400x300 (+3)")
        if thumb.get("size_bytes", 0) > 5000:
            score += 2
            feedback_parts.append("Thumbnail > 5KB (+2)")

    # 7. Manifest verification
    agent_manifest = result.get("agent_manifest")
    if agent_manifest and isinstance(agent_manifest, dict):
        score += 3
        feedback_parts.append("Manifest valid JSON (+3)")
        manifest_str = json.dumps(agent_manifest)
        listed_files = sum(1 for f in ["listing_master.mp4", "listing_mobile.mp4", "listing_square.mp4", "listing_email.mp4", "listing_thumbnail.jpg", "manifest.json"] if f in manifest_str)
        
        if listed_files >= 5:
            score += 4
            feedback_parts.append("Manifest lists required files (+4)")
        if "1920" in manifest_str and "720" in manifest_str and "1080" in manifest_str:
            score += 4
            feedback_parts.append("Manifest dimensions accurate (+4)")
        if any(str(finfo.get("size_bytes", 123456789)) in manifest_str for finfo in files.values() if finfo.get("exists")):
            score += 3
            feedback_parts.append("Manifest file sizes plausible (+3)")
    elif agent_manifest == "invalid_json":
        feedback_parts.append("Manifest invalid JSON (0)")

    # 8. VLM Trajectory Process Verification (Bonus to detect actual work vs shortcut scripts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                prompt = {
                    "text": "Analyze these chronological trajectory frames of an agent assembling a video. Did the agent utilize video/audio editing software (like VLC, Kdenlive, or a terminal running ffmpeg) to combine the raw images and audio into videos? Respond with a JSON object containing a boolean key 'workflow_observed'.",
                    "response_format": {"type": "json_object"}
                }
                resp = query_vlm(prompt=prompt, images=frames)
                if resp and resp.get("success") and resp.get("parsed", {}).get("workflow_observed", False):
                    vlm_score += 20
                    feedback_parts.append("VLM confirms workflow (+20)")
                else:
                    feedback_parts.append("VLM did not confirm active editing workflow (0)")
        except Exception as e:
            logger.warning(f"VLM error: {e}")
            feedback_parts.append(f"VLM error ({e})")

    total_score = score + vlm_score
    # Max programmatic score is 56. Passing is set roughly to 45 (approx 60% of max combined).
    passed = total_score >= 45 and (master.get("exists") == True)

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }