#!/usr/bin/env python3
"""
Verifier for digital_signage_video_wall_slicer task.
Uses OpenCV to compute MSE on output video frames to ensure accurate geometrical cropping.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing OpenCV for image comparison
try:
    import cv2
    import numpy as np
    CV2_AVAILABLE = True
except ImportError:
    logger.warning("OpenCV not available - geometric verification will be limited.")
    CV2_AVAILABLE = False

def calculate_mse(imageA, imageB):
    """Compute the Mean Squared Error between two images."""
    if imageA.shape != imageB.shape:
        return float('inf')
    err = np.sum((imageA.astype("float") - imageB.astype("float")) ** 2)
    err /= float(imageA.shape[0] * imageA.shape[1])
    return err

def verify_digital_signage_video_wall_slicer(traj, env_info, task_info):
    """
    Verify the sliced videos, audio demuxing, XML playlist, and JSON manifest.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    expected_files = ["screen_1_left.mp4", "screen_2_center.mp4", "screen_3_right.mp4"]
    gt_mapping = {
        "screen_1_left.mp4": ("screen_1.png", "gt_1_left.png"),
        "screen_2_center.mp4": ("screen_2.png", "gt_2_center.png"),
        "screen_3_right.mp4": ("screen_3.png", "gt_3_right.png")
    }

    temp_dir = tempfile.mkdtemp(prefix='vlc_signage_verify_')
    results_json_path = os.path.join(temp_dir, 'signage_results.json')
    
    # Copy main results JSON
    try:
        copy_from_env("/tmp/signage_results.json", results_json_path)
        with open(results_json_path, 'r') as f:
            results = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}

    task_start = results.get('task_start', 0)
    files_data = results.get('files', {})
    
    # 1. File Generation (15 points)
    files_exist = sum([1 for f in expected_files if files_data.get(f, {}).get('exists', False)])
    if files_exist == 3:
        score += 15
        feedback_parts.append("All 3 MP4 files generated")
    else:
        feedback_parts.append(f"Only {files_exist}/3 MP4 files generated")
        
    # Check if created during task (anti-gaming)
    newly_created = 0
    for f in expected_files:
        if files_data.get(f, {}).get('mtime', 0) >= task_start:
            newly_created += 1
            
    if files_exist > 0 and newly_created < files_exist:
        feedback_parts.append("WARNING: Some files existed before task started (possible cheating)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Format & Resolution (15 points)
    res_correct = 0
    for f in expected_files:
        fdata = files_data.get(f, {})
        if fdata.get('width') == 1080 and fdata.get('height') == 1920:
            res_correct += 1
            
    if res_correct == 3:
        score += 15
        feedback_parts.append("All resolutions correct (1080x1920)")
    else:
        feedback_parts.append(f"{res_correct}/3 resolutions correct")

    # 3. Audio Stripping (15 points)
    audio_stripped = 0
    for f in expected_files:
        fdata = files_data.get(f, {})
        # File must exist to check audio
        if fdata.get('exists') and fdata.get('audio_streams') == 0:
            audio_stripped += 1
            
    if audio_stripped == 3:
        score += 15
        feedback_parts.append("Audio stripped from all 3 files")
    else:
        feedback_parts.append(f"Audio stripped from {audio_stripped}/3 files")

    # 4. Geometric Accuracy via OpenCV MSE (30 points)
    geo_score = 0
    if CV2_AVAILABLE:
        for f in expected_files:
            agent_frame_name, gt_frame_name = gt_mapping[f]
            agent_frame_path = os.path.join(temp_dir, agent_frame_name)
            gt_frame_path = os.path.join(temp_dir, gt_frame_name)
            
            try:
                copy_from_env(f"/tmp/agent_frames/{agent_frame_name}", agent_frame_path)
                copy_from_env(f"/tmp/ground_truth/{gt_frame_name}", gt_frame_path)
                
                if os.path.exists(agent_frame_path) and os.path.exists(gt_frame_path):
                    imgA = cv2.imread(agent_frame_path)
                    imgB = cv2.imread(gt_frame_path)
                    
                    if imgA is not None and imgB is not None:
                        mse = calculate_mse(imgA, imgB)
                        # Threshold 2000 accounts for transcoding loss, but fails bad geometry
                        if mse < 2000:
                            geo_score += 10
                        else:
                            feedback_parts.append(f"{f} Geometric check failed (MSE: {mse:.1f})")
            except Exception as e:
                logger.error(f"Error checking MSE for {f}: {e}")
                
        score += geo_score
        feedback_parts.append(f"Geometric accuracy score: {geo_score}/30")
    else:
        # Give fallback points if CV is missing but resolutions were correct
        fallback = res_correct * 10
        score += fallback
        feedback_parts.append(f"Geometric check bypassed (OpenCV missing), granted {fallback}/30 based on resolution")

    # 5. XSPF Playlist Validity (15 points)
    if results.get('xspf_exists'):
        xspf_path = os.path.join(temp_dir, 'wall_test_playlist.xspf')
        try:
            copy_from_env("/tmp/wall_test_playlist.xspf", xspf_path)
            with open(xspf_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            content_lower = content.lower()
            valid_xspf = 0
            
            if '<?xml' in content_lower and '<playlist' in content_lower:
                valid_xspf += 5
                
            has_all_files = all(f in content for f in expected_files)
            if has_all_files:
                valid_xspf += 5
                
            if 'loop' in content_lower or 'repeat' in content_lower:
                valid_xspf += 5
                
            score += valid_xspf
            feedback_parts.append(f"XSPF Playlist Score: {valid_xspf}/15")
        except Exception as e:
            feedback_parts.append(f"Failed to parse XSPF: {e}")
    else:
        feedback_parts.append("XSPF Playlist missing")

    # 6. JSON Manifest Accuracy (10 points)
    if results.get('manifest_exists'):
        manifest_path = os.path.join(temp_dir, 'signage_manifest.json')
        try:
            copy_from_env("/tmp/signage_manifest.json", manifest_path)
            with open(manifest_path, 'r') as f:
                manifest = json.load(f)
                
            manifest_score = 0
            if manifest.get('exhibit') == 'Panoramic Earth':
                manifest_score += 3
            if manifest.get('master_resolution') == '3240x1920':
                manifest_score += 3
            if isinstance(manifest.get('panels'), list) and len(manifest.get('panels')) == 3:
                manifest_score += 4
                
            score += manifest_score
            feedback_parts.append(f"Manifest Score: {manifest_score}/10")
        except Exception as e:
            feedback_parts.append(f"Failed to parse Manifest: {e}")
    else:
        feedback_parts.append("JSON Manifest missing")

    # Final logic
    key_criteria_met = files_exist == 3 and (geo_score >= 20 or (not CV2_AVAILABLE and res_correct == 3))
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }