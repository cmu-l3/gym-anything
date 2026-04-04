#!/usr/bin/env python3
"""
Verifier for Extract Lecture Highlights task
"""

import sys
import os
import logging
import tempfile
import json
import shutil

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_audio_info,
    copy_and_parse_media,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_extract_lecture_highlights(traj, env_info, task_info):
    """
    Verify extract lecture highlights task completion.
    
    Checks:
    1. All 4 audio files exist with correct names
    2. Each file has correct duration (30-40 seconds with tolerance)
    3. Each file is valid audio format (MP3)
    4. Files are in correct location
    
    Args:
        traj: Trajectory information
        env_info: Environment info including copy_from_env function
        task_info: Task-specific information
    
    Returns:
        dict: Verification result with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Expected segments
    expected_segments = [
        {
            "filename": "segment_1_concept_a.mp3",
            "min_duration": 28.0,
            "max_duration": 42.0,
            "description": "Segment 1 (Concept A)"
        },
        {
            "filename": "segment_2_concept_b.mp3",
            "min_duration": 28.0,
            "max_duration": 42.0,
            "description": "Segment 2 (Concept B)"
        },
        {
            "filename": "segment_3_concept_c.mp3",
            "min_duration": 28.0,
            "max_duration": 42.0,
            "description": "Segment 3 (Concept C)"
        },
        {
            "filename": "segment_4_concept_d.mp3",
            "min_duration": 28.0,
            "max_duration": 42.0,
            "description": "Segment 4 (Concept D)"
        }
    ]
    
    total_criteria = 4  # One per file
    criteria_met = 0
    feedback_parts = []
    
    # First, check the summary JSON to see what was found
    temp_summary = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vlc_extract_highlights_result.json", temp_summary.name)
        
        with open(temp_summary.name, 'r') as f:
            summary = json.load(f)
        
        files_found = summary.get('files_found', 0)
        feedback_parts.append(f"Files created: {files_found}/4")
        
        os.unlink(temp_summary.name)
    except Exception as e:
        logger.warning(f"Could not read summary JSON: {e}")
        feedback_parts.append("⚠️ Summary not available")
    
    # Verify each segment
    for idx, segment in enumerate(expected_segments):
        filename = segment['filename']
        description = segment['description']
        min_duration = segment['min_duration']
        max_duration = segment['max_duration']
        
        # Try to copy and analyze the segment
        container_path = f"/tmp/vlc_segment_{idx}.mp3"
        
        success, audio_data, error, temp_dir = copy_and_parse_media(
            container_path,
            copy_from_env,
            file_type='audio'
        )
        
        if not success:
            feedback_parts.append(f"❌ {description}: Not found or invalid")
            cleanup_verification_environment(temp_dir)
            continue
        
        # File exists and is valid audio
        if 'error' in audio_data:
            feedback_parts.append(f"❌ {description}: Parse error - {audio_data['error']}")
            cleanup_verification_environment(temp_dir)
            continue
        
        # Check duration
        duration = audio_data.get('duration', 0)
        
        if duration == 0:
            feedback_parts.append(f"❌ {description}: Invalid duration")
            cleanup_verification_environment(temp_dir)
            continue
        
        # Verify duration is in expected range
        if min_duration <= duration <= max_duration:
            criteria_met += 1
            codec = audio_data.get('codec', 'unknown')
            bitrate_kbps = audio_data.get('bitrate', 0) / 1000 if audio_data.get('bitrate') else 0
            feedback_parts.append(
                f"✅ {description}: Valid ({duration:.1f}s, {codec}, {bitrate_kbps:.0f}kbps)"
            )
        else:
            # File exists but duration is wrong
            feedback_parts.append(
                f"⚠️ {description}: Duration mismatch ({duration:.1f}s, expected 30-40s)"
            )
            # Give partial credit if file at least exists and is audio
            criteria_met += 0.5
        
        # Cleanup temp directory
        cleanup_verification_environment(temp_dir)
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_extract_highlights_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        if "completed" in marker_content.lower():
            feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    # Each segment is worth 25% of the score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 80  # Need at least 4 files correct or 3 perfect + 2 partial
    
    # Add summary at the beginning
    summary_line = f"Score: {score}% ({criteria_met}/{total_criteria} segments extracted correctly)"
    feedback = summary_line + " | " + " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }