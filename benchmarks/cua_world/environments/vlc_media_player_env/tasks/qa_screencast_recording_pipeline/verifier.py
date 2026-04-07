#!/usr/bin/env python3
"""
Verifier for QA Screencast Recording task.
Requires the video file, the template image, and the export JSON.
Uses OpenCV template matching and VLM trajectory analysis.
"""

import json
import os
import tempfile
import logging
import cv2
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_qa_screencast(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_fps = metadata.get('expected_fps', 10)
    fps_tolerance = metadata.get('fps_tolerance', 1.5)
    max_size_bytes = metadata.get('max_size_bytes', 2097152)
    output_file_path = metadata.get('output_file', '/home/ga/Videos/qa_reports/jira_attachment_bug_1044.mp4')
    template_image_path = metadata.get('template_image', '/home/ga/Pictures/bug_reference_ui.png')

    score = 0
    feedback_parts = []
    
    # 1. Fetch JSON Results
    result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/qa_screencast_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load export json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read export JSON"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    file_exists = result.get('file_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_size = result.get('file_size_bytes', 0)
    video_codec = result.get('video_codec', '')
    actual_fps = result.get('fps', 0)

    # Fast fail if no file
    if not file_exists or not file_created:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output video file was not created during the task."
        }

    # 2. Programmatic Checks
    
    # Check Codec (H.264)
    if 'h264' in video_codec.lower() or 'avc' in video_codec.lower():
        score += 20
        feedback_parts.append("Codec correct (H.264)")
    else:
        feedback_parts.append(f"Codec incorrect: {video_codec}")

    # Check FPS
    if abs(actual_fps - expected_fps) <= fps_tolerance:
        score += 20
        feedback_parts.append(f"FPS correct (~{actual_fps} fps)")
    else:
        feedback_parts.append(f"FPS incorrect: {actual_fps} fps (expected {expected_fps})")

    # Check File Size
    if 0 < file_size <= max_size_bytes:
        score += 20
        feedback_parts.append(f"Size constraint met ({file_size/1024/1024:.2f} MB)")
    else:
        feedback_parts.append(f"Size constraint failed ({file_size/1024/1024:.2f} MB is > 2.0 MB)")

    # 3. Visual Verification (OpenCV Template Matching)
    visual_evidence_passed = False
    
    temp_video = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    try:
        copy_from_env(output_file_path, temp_video.name)
        copy_from_env(template_image_path, temp_img.name)
        
        template = cv2.imread(temp_img.name)
        cap = cv2.VideoCapture(temp_video.name)
        
        if template is not None and cap.isOpened():
            template_gray = cv2.cvtColor(template, cv2.COLOR_BGR2GRAY)
            th, tw = template_gray.shape
            
            frame_count = 0
            # Check up to 300 frames (30 seconds at 10fps) to prevent infinite hangs
            while cap.isOpened() and frame_count < 300:
                ret, frame = cap.read()
                if not ret:
                    break
                
                # Check 1 frame per second to speed up processing
                if frame_count % max(1, int(actual_fps)) == 0:
                    try:
                        frame_gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                        # Ensure frame is larger than template to avoid cv2 exception
                        if frame_gray.shape[0] >= th and frame_gray.shape[1] >= tw:
                            res = cv2.matchTemplate(frame_gray, template_gray, cv2.TM_CCOEFF_NORMED)
                            _, max_val, _, _ = cv2.minMaxLoc(res)
                            
                            if max_val >= 0.70:  # Threshold for compressed UI elements
                                visual_evidence_passed = True
                                break
                    except Exception as e:
                        logger.warning(f"Frame matching error: {e}")
                
                frame_count += 1
                
        cap.release()
    except Exception as e:
        logger.error(f"OpenCV processing error: {e}")
    finally:
        if os.path.exists(temp_video.name): os.unlink(temp_video.name)
        if os.path.exists(temp_img.name): os.unlink(temp_img.name)

    if visual_evidence_passed:
        score += 40
        feedback_parts.append("Visual evidence found (bug reference image visible in recording)")
    else:
        feedback_parts.append("Visual evidence missing (reference image not found in recording)")

    # 4. Trajectory Check via VLM
    vlm_points = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Analyze these trajectory screenshots of an agent using VLC Media Player.
Did the agent open the 'Capture Device' menu and configure it to record the 'Desktop'?
Reply in JSON: {"configured_desktop_capture": true/false}"""
            
            try:
                vlm_res = query_vlm(images=frames, prompt=prompt)
                if vlm_res and vlm_res.get('success'):
                    if vlm_res.get('parsed', {}).get('configured_desktop_capture', False):
                        feedback_parts.append("VLM confirms Capture Device workflow")
            except Exception as e:
                logger.warning(f"VLM trajectory check failed: {e}")

    # Determine final success
    passed = (score >= 80) and visual_evidence_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }