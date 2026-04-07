#!/usr/bin/env python3
"""
Verifier for Dailies Contact Sheet Pipeline.
Evaluates the existence, dimensions, distinctness of extracted frames and contact sheets,
and validates the schemas of the generated JSON metadata files.
"""

import json
import os
import tarfile
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import PIL for image validation
try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    logger.warning("PIL not available, skipping precise image dimension checks")

def get_image_info(filepath):
    """Return dict with size and dimensions of an image."""
    info = {"size_bytes": os.path.getsize(filepath), "width": 0, "height": 0, "valid": False}
    if PIL_AVAILABLE:
        try:
            with Image.open(filepath) as img:
                info["width"], info["height"] = img.size
                info["valid"] = True
        except Exception:
            info["valid"] = False
    else:
        # Fallback if PIL missing
        info["valid"] = info["size_bytes"] > 0
    return info

def verify_dailies_contact_sheet_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    clips = metadata.get("clips", ["scene12_take3", "scene12_take4", "scene15_take1", "scene18_take2"])
    
    score = 0
    max_score = 52
    pass_threshold = 29
    feedback_parts = []
    
    work_dir = tempfile.mkdtemp(prefix="vlc_verify_dailies_")
    tar_local = os.path.join(work_dir, "dailies.tar.gz")
    meta_local = os.path.join(work_dir, "meta.json")
    
    # 1. Fetch export files
    try:
        copy_from_env("/tmp/export_meta.json", meta_local)
        with open(meta_local, "r") as f:
            export_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export meta: {e}"}

    if not export_meta.get("tarball_created", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Agent did not create the dailies_output directory."
        }
        
    try:
        copy_from_env("/tmp/dailies_output_export.tar.gz", tar_local)
        with tarfile.open(tar_local, "r:gz") as tar:
            tar.extractall(path=work_dir)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to extract output tarball: {e}"}

    output_base = os.path.join(work_dir, "dailies_output")
    task_start_time = export_meta.get("task_start_time", 0)

    # State tracking
    total_valid_frames = 0
    distinct_frames_bonus_given = 0
    
    # ================================================================
    # INDIVIDUAL FRAMES EVALUATION (12 pts + 4 pts distinctness)
    # ================================================================
    frames_dir = os.path.join(output_base, "frames")
    for clip in clips:
        clip_dir = os.path.join(frames_dir, clip)
        clip_frames_valid = 0
        frame_sizes = []
        
        if os.path.isdir(clip_dir):
            for t in ["00s", "10s", "20s", "30s", "40s", "50s"]:
                frame_path = os.path.join(clip_dir, f"frame_{t}.png")
                if os.path.isfile(frame_path):
                    img_info = get_image_info(frame_path)
                    if img_info["valid"] and img_info["size_bytes"] > 10240: # > 10KB
                        clip_frames_valid += 1
                        frame_sizes.append(img_info["size_bytes"])
        
        # Scoring per clip frames
        if clip_frames_valid == 6:
            score += 3
            total_valid_frames += 6
            feedback_parts.append(f"Frames {clip}: 6/6 valid")
        elif clip_frames_valid > 0:
            pts = clip_frames_valid * 0.5
            score += pts
            total_valid_frames += clip_frames_valid
            feedback_parts.append(f"Frames {clip}: {clip_frames_valid}/6 valid ({pts} pts)")
        else:
            feedback_parts.append(f"Frames {clip}: Missing")
            
        # Distinctness check (prevent agent from just copying 1 frame 6 times)
        if len(set(frame_sizes)) >= 2:
            distinct_frames_bonus_given += 1

    if distinct_frames_bonus_given == 4:
        score += 4
        feedback_parts.append("Frame distinctness: Verified across all clips")
    elif distinct_frames_bonus_given > 0:
        score += distinct_frames_bonus_given
        feedback_parts.append(f"Frame distinctness: Verified for {distinct_frames_bonus_given}/4 clips")

    # ================================================================
    # CONTACT SHEETS EVALUATION (12 pts + 2 pts size check)
    # ================================================================
    sheets_dir = os.path.join(output_base, "sheets")
    sheets_valid = 0
    larger_than_frames_count = 0
    
    for clip in clips:
        sheet_path = os.path.join(sheets_dir, f"{clip}_sheet.png")
        if os.path.isfile(sheet_path):
            img_info = get_image_info(sheet_path)
            # A 3x2 of 480x270 should be ~1440x540. Allow some margin for padding.
            if img_info["valid"] and img_info["size_bytes"] > 51200: # > 50KB
                if img_info["width"] >= 1000 or not PIL_AVAILABLE:
                    score += 3
                    sheets_valid += 1
                    feedback_parts.append(f"Sheet {clip}: Valid grid image")
                    
                    # Check if sheet is larger than a single frame (basic montage check)
                    clip_frame_path = os.path.join(frames_dir, clip, "frame_00s.png")
                    if os.path.isfile(clip_frame_path) and img_info["size_bytes"] > os.path.getsize(clip_frame_path):
                        larger_than_frames_count += 1
                else:
                    score += 1
                    feedback_parts.append(f"Sheet {clip}: Too small for grid ({img_info['width']}px)")
        else:
            feedback_parts.append(f"Sheet {clip}: Missing")
            
    if larger_than_frames_count == 4:
        score += 2
        feedback_parts.append("Contact sheets: Verified larger than individual frames")

    # ================================================================
    # FRAME INDEX JSON EVALUATION (11 pts total)
    # ================================================================
    idx_path = os.path.join(output_base, "frame_index.json")
    if os.path.isfile(idx_path):
        try:
            with open(idx_path, "r") as f:
                idx_data = json.load(f)
            
            score += 2 # Valid JSON
            feedback_parts.append("Frame Index: Valid JSON")
            
            frames_list = idx_data.get("frames", [])
            if len(frames_list) == 24:
                score += 3
                feedback_parts.append("Frame Index: 24 entries present")
            elif len(frames_list) > 0:
                score += 1
                feedback_parts.append(f"Frame Index: {len(frames_list)}/24 entries")
                
            # Check timecodes
            valid_tc = sum(1 for item in frames_list if item.get("timecode_seconds") in [0, 10, 20, 30, 40, 50])
            if valid_tc == 24:
                score += 3
                feedback_parts.append("Frame Index: All timecodes correct")
            elif valid_tc > 0:
                score += 1
                feedback_parts.append(f"Frame Index: {valid_tc} valid timecodes")
                
            # Check file existence mapping
            files_exist = 0
            for item in frames_list:
                fname = item.get("filename", "")
                if fname and os.path.isfile(os.path.join(output_base, fname)):
                    files_exist += 1
                elif fname and os.path.isfile(os.path.join(work_dir, fname)): # forgiving paths
                    files_exist += 1
            
            if files_exist == 24:
                score += 3
                feedback_parts.append("Frame Index: All referenced files exist")
            elif files_exist > 0:
                score += 1
                feedback_parts.append(f"Frame Index: {files_exist} referenced files exist")
                
        except json.JSONDecodeError:
            feedback_parts.append("Frame Index: Invalid JSON format")
    else:
        feedback_parts.append("Frame Index: Missing")

    # ================================================================
    # PRODUCTION SUMMARY JSON EVALUATION (9 pts total)
    # ================================================================
    sum_path = os.path.join(output_base, "production_summary.json")
    if os.path.isfile(sum_path):
        try:
            with open(sum_path, "r") as f:
                sum_data = json.load(f)
            
            score += 2 # Valid JSON
            feedback_parts.append("Prod Summary: Valid JSON")
            
            sum_clips = sum_data.get("clips", [])
            clip_names = [c.get("filename", "") for c in sum_clips]
            
            if len(sum_clips) == 4 and all(c + ".mp4" in clip_names for c in clips):
                score += 2
                feedback_parts.append("Prod Summary: All 4 clips listed")
            elif len(sum_clips) > 0:
                score += 1
                feedback_parts.append(f"Prod Summary: {len(sum_clips)}/4 clips listed")
                
            # Check durations (~60s)
            valid_durations = sum(1 for c in sum_clips if abs(float(c.get("duration_seconds", 0)) - 60) <= 5)
            if valid_durations == 4:
                score += 3
                feedback_parts.append("Prod Summary: All durations accurate")
            elif valid_durations > 0:
                score += 1
                
            if sum_data.get("total_frames_extracted") == 24:
                score += 2
                feedback_parts.append("Prod Summary: Total frames correctly stated as 24")
                
        except json.JSONDecodeError:
            feedback_parts.append("Prod Summary: Invalid JSON format")
    else:
        feedback_parts.append("Prod Summary: Missing")

    # ================================================================
    # ANTI-GAMING (2 pts)
    # ================================================================
    # Verify outputs were modified after task start
    new_files_detected = False
    for root, dirs, files in os.walk(output_base):
        for f in files:
            mtime = os.path.getmtime(os.path.join(root, f))
            if mtime > task_start_time:
                new_files_detected = True
                break
        if new_files_detected:
            break
            
    if new_files_detected:
        score += 2
        feedback_parts.append("Anti-gaming: Timestamps verified")
    else:
        feedback_parts.append("Anti-gaming: Warning - files existed before task start")

    # Calculate final status
    passed = score >= pass_threshold and total_valid_frames >= 12
    
    if passed and score < max_score:
        feedback_parts.append("Result: PASSED (with partial credit)")
    elif passed:
        feedback_parts.append("Result: PASSED PERFECTLY")
    else:
        feedback_parts.append("Result: FAILED (did not meet threshold or missing too many frames)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }