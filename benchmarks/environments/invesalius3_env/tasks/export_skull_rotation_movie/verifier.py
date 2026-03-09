#!/usr/bin/env python3
"""
Verifier for export_skull_rotation_movie task.

Scoring (100 points total):
1. Output generated (Files exist and created during task) - 25 pts
2. Quantity sufficient (>= 12 frames OR video > 100KB) - 25 pts
3. Content Verification (VLM):
   - Images show a skull - 25 pts
   - Images show rotation (view angle changes) - 25 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging
import cv2
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_skull_rotation_movie(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System functions unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/rotation_result.json", tmp_json.name)
        with open(tmp_json.name) as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    mode = result.get("mode", "none")
    
    # 2. Check Existence (25 pts)
    if mode == "frames":
        score += 25
        feedback_parts.append("Frame sequence detected")
    elif mode == "video":
        score += 25
        feedback_parts.append("Video file detected")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid output found (frames or video)"}

    # 3. Check Quantity (25 pts)
    files_to_check = []
    
    if mode == "frames":
        count = result.get("frames_count", 0)
        files = result.get("frame_files", [])
        if count >= 12:
            score += 25
            feedback_parts.append(f"Frame count good ({count})")
            # Pick 3 frames (start, mid, end) for VLM
            if len(files) >= 3:
                indices = [0, len(files)//2, -1]
                files_to_check = [files[i] for i in indices]
        else:
            feedback_parts.append(f"Frame count low ({count}/12)")
            
    elif mode == "video":
        size = result.get("video_size_bytes", 0)
        video_file_container = result.get("frame_files", [])[0]
        if size > 100 * 1024: # 100KB
            score += 25
            feedback_parts.append(f"Video size good ({size//1024}KB)")
            files_to_check = [video_file_container]
        else:
            feedback_parts.append(f"Video size too small ({size} bytes)")

    # 4. Content Verification (50 pts total)
    if files_to_check:
        images_for_vlm = []
        
        try:
            if mode == "frames":
                # Copy frames to host
                for remote_path in files_to_check:
                    local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
                    local_tmp.close()
                    copy_from_env(remote_path, local_tmp.name)
                    # Read image
                    img = cv2.imread(local_tmp.name)
                    if img is not None:
                        images_for_vlm.append(img)
                    os.unlink(local_tmp.name)
            
            elif mode == "video":
                # Copy video to host
                remote_vid = files_to_check[0]
                local_vid = tempfile.NamedTemporaryFile(delete=False, suffix=".avi")
                local_vid.close()
                copy_from_env(remote_vid, local_vid.name)
                
                # Extract frames using cv2
                cap = cv2.VideoCapture(local_vid.name)
                total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
                if total_frames > 5:
                    # Get start, mid, end
                    for idx in [0, total_frames // 2, total_frames - 2]:
                        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
                        ret, frame = cap.read()
                        if ret:
                            images_for_vlm.append(frame)
                cap.release()
                os.unlink(local_vid.name)

        except Exception as e:
            feedback_parts.append(f"Error processing visual evidence: {e}")

        if len(images_for_vlm) >= 2:
            # VLM Query
            prompt = """
            Look at these sequential frames from a 3D medical imaging task.
            1. Is a human skull (bone structure) visible?
            2. Does the viewing angle of the skull change between frames (indicating rotation)?
            
            Return JSON:
            {
                "skull_visible": true/false,
                "rotation_visible": true/false,
                "confidence": "high/med/low"
            }
            """
            
            vlm_resp = query_vlm(prompt=prompt, images=images_for_vlm)
            
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                
                if parsed.get("skull_visible"):
                    score += 25
                    feedback_parts.append("Skull visible in output")
                else:
                    feedback_parts.append("Skull NOT detected in output")
                    
                if parsed.get("rotation_visible"):
                    score += 25
                    feedback_parts.append("Rotation confirmed")
                else:
                    feedback_parts.append("Rotation NOT detected")
            else:
                feedback_parts.append("VLM verification failed")
        else:
            feedback_parts.append("Could not extract frames for VLM check")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }