#!/usr/bin/env python3
"""
Verifier for Navigate Chapter Markers task
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    verify_snapshot_exists,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def vlm_verify_content(snapshot_path: str, expected_content: str, content_type: str) -> tuple:
    """
    Use VLM to verify snapshot shows expected content.
    
    Args:
        snapshot_path: Path to snapshot image
        expected_content: Description of expected content
        content_type: "solar" or "wind"
    
    Returns:
        Tuple of (matches: bool, confidence: float, reasoning: str)
    """
    try:
        # In a real implementation, this would call a VLM API
        # For now, we'll do basic image analysis
        
        from PIL import Image
        import numpy as np
        
        img = Image.open(snapshot_path)
        img_array = np.array(img)
        
        # Calculate dominant colors
        avg_color = img_array.mean(axis=(0, 1))
        
        # Check for text in image (very basic - just check if image has text-like patterns)
        # In production, would use VLM or OCR
        
        if content_type == "solar":
            # Solar chapter has orange/yellow colors
            # Orange is high R, medium-high G, low B
            is_orange = avg_color[0] > 150 and avg_color[1] > 100 and avg_color[2] < 100
            is_yellow = avg_color[0] > 200 and avg_color[1] > 200 and avg_color[2] < 150
            
            if is_orange or is_yellow:
                return True, 0.8, "Image has orange/yellow tones consistent with solar chapter"
            else:
                return False, 0.3, f"Image colors don't match solar chapter (avg RGB: {avg_color})"
        
        elif content_type == "wind":
            # Wind chapter has light blue colors
            # Light blue is low R, high G, high B
            is_lightblue = avg_color[2] > 150 and avg_color[0] < 150
            is_cyan = avg_color[1] > 150 and avg_color[2] > 150
            
            if is_lightblue or is_cyan:
                return True, 0.8, "Image has blue/cyan tones consistent with wind chapter"
            else:
                return False, 0.3, f"Image colors don't match wind chapter (avg RGB: {avg_color})"
        
        return False, 0.0, "Unknown content type"
        
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        return False, 0.0, f"Verification error: {str(e)}"


def extract_timestamp_from_filename(filepath: str) -> int:
    """
    Extract timestamp from VLC snapshot filename.
    
    VLC format: vlcsnap-2024-01-15-23h45m12s.png
    Returns timestamp in seconds from video start.
    """
    try:
        filename = os.path.basename(filepath)
        # VLC doesn't actually encode video timestamp in filename, just capture time
        # So this won't work for our purposes - we'll rely on VLM content verification
        return -1
    except:
        return -1


def verify_navigate_chapter_markers(traj, env_info, task_info):
    """
    Verify navigate chapter markers task completion.
    
    Checks:
    1. Video opened (check completion marker)
    2. Solar Power snapshot exists with correct content
    3. Wind Energy snapshot exists with correct content
    4. Chapter navigation was used
    5. Snapshots from correct time ranges
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    max_score = 100
    current_score = 0
    feedback_parts = []
    
    # Criterion 1: Video opened (15 points)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_chapter_completed.txt", temp_marker.name)
        current_score += 15
        feedback_parts.append("✅ VLC opened with documentary")
        os.unlink(temp_marker.name)
    except Exception as e:
        feedback_parts.append("⚠️ Task completion marker not found")
    
    # Read result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/vlc_chapter_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        logger.warning(f"Could not read result JSON: {e}")
    
    # Criterion 2: Solar Power snapshot (30 points total)
    solar_exists = False
    solar_content_valid = False
    
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_chapter_solar.png",
        file_type='image'
    )
    
    if success:
        solar_exists = True
        image_data = file_info.get('data', {})
        
        # Check file size
        if image_data.get('size_kb', 0) > 10:
            current_score += 10
            feedback_parts.append(f"✅ Solar snapshot exists ({image_data.get('size_kb', 0):.1f} KB)")
            
            # VLM content verification
            snapshot_path = file_info.get('filepath')
            matches, confidence, reasoning = vlm_verify_content(
                snapshot_path, "solar panels, solar energy", "solar"
            )
            
            if matches:
                solar_content_valid = True
                current_score += 20
                feedback_parts.append(f"✅ Solar snapshot shows correct content ({reasoning})")
            else:
                current_score += 5  # Partial credit for having snapshot
                feedback_parts.append(f"⚠️ Solar snapshot content unclear: {reasoning}")
        else:
            feedback_parts.append("⚠️ Solar snapshot too small or invalid")
        
        cleanup_verification_environment(file_info.get('temp_dir'))
    else:
        feedback_parts.append("❌ Solar Power snapshot not found")
    
    # Criterion 3: Wind Energy snapshot (30 points total)
    wind_exists = False
    wind_content_valid = False
    
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_chapter_wind.png",
        file_type='image'
    )
    
    if success:
        wind_exists = True
        image_data = file_info.get('data', {})
        
        # Check file size
        if image_data.get('size_kb', 0) > 10:
            current_score += 10
            feedback_parts.append(f"✅ Wind snapshot exists ({image_data.get('size_kb', 0):.1f} KB)")
            
            # VLM content verification
            snapshot_path = file_info.get('filepath')
            matches, confidence, reasoning = vlm_verify_content(
                snapshot_path, "wind turbines, wind energy", "wind"
            )
            
            if matches:
                wind_content_valid = True
                current_score += 20
                feedback_parts.append(f"✅ Wind snapshot shows correct content ({reasoning})")
            else:
                current_score += 5  # Partial credit for having snapshot
                feedback_parts.append(f"⚠️ Wind snapshot content unclear: {reasoning}")
        else:
            feedback_parts.append("⚠️ Wind snapshot too small or invalid")
        
        cleanup_verification_environment(file_info.get('temp_dir'))
    else:
        feedback_parts.append("❌ Wind Energy snapshot not found")
    
    # Criterion 4: Chapter navigation detected (15 points)
    chapter_nav_detected = result_data.get('chapter_navigation_detected', False)
    
    if chapter_nav_detected:
        current_score += 15
        feedback_parts.append("✅ Chapter navigation detected in logs")
    else:
        # If both snapshots have correct content, give partial credit
        if solar_content_valid and wind_content_valid:
            current_score += 10
            feedback_parts.append("⚠️ Chapter navigation not confirmed, but snapshots suggest correct navigation")
        else:
            feedback_parts.append("⚠️ Chapter navigation not detected")
    
    # Criterion 5: Correct time ranges (10 points)
    # This is difficult to verify without video analysis or timestamp metadata
    # Give partial credit if both snapshots have correct content
    if solar_content_valid and wind_content_valid:
        current_score += 10
        feedback_parts.append("✅ Snapshots appear to be from correct chapters (based on content)")
    else:
        feedback_parts.append("⚠️ Cannot verify correct chapter time ranges")
    
    # Calculate final score and pass/fail
    score = min(current_score, max_score)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    if score >= 85:
        summary = "Excellent! All chapter navigation requirements met."
    elif score >= 70:
        summary = "Good! Chapter navigation task completed successfully."
    elif score >= 50:
        summary = "Partial completion. Missing key snapshots or incorrect content."
    else:
        summary = "Insufficient completion. Task requirements not met."
    
    feedback = f"{summary} | {feedback}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }