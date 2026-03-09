#!/usr/bin/env python3
"""
Verifier for Verify True Duration task.
Checks if user correctly identified the true duration of a video with corrupted/incorrect metadata.
"""

import os
import re
import sys
import tempfile
import logging
from pathlib import Path
from typing import Dict, Any, Tuple

# Add utils to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    setup_verification_environment,
    cleanup_verification_environment,
    logger
)

logging.basicConfig(level=logging.INFO)


def parse_duration_report(report_path: str) -> Dict[str, Any]:
    """
    Parse the user's duration report file.
    
    Args:
        report_path: Path to the duration report text file
        
    Returns:
        Dict with parsed fields: metadata_duration, actual_duration, verification_method
    """
    try:
        with open(report_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        parsed = {}
        
        # Extract METADATA_DURATION (look for numbers, allow decimals)
        metadata_match = re.search(r'METADATA_DURATION:\s*(\d+(?:\.\d+)?)', content, re.IGNORECASE)
        if metadata_match:
            parsed['metadata_duration'] = float(metadata_match.group(1))
            logger.info(f"Parsed metadata_duration: {parsed['metadata_duration']}")
        
        # Extract ACTUAL_DURATION
        actual_match = re.search(r'ACTUAL_DURATION:\s*(\d+(?:\.\d+)?)', content, re.IGNORECASE)
        if actual_match:
            parsed['actual_duration'] = float(actual_match.group(1))
            logger.info(f"Parsed actual_duration: {parsed['actual_duration']}")
        
        # Extract VERIFICATION_METHOD
        method_match = re.search(r'VERIFICATION_METHOD:\s*(.+?)(?:\n|$)', content, re.IGNORECASE)
        if method_match:
            parsed['verification_method'] = method_match.group(1).strip()
            logger.info(f"Parsed verification_method: {parsed['verification_method']}")
        
        return parsed
        
    except Exception as e:
        logger.error(f"Error parsing duration report: {e}")
        return {}


def verify_true_duration(traj, env_info, task_info):
    """
    Verify the verify_true_duration task.
    
    Checks:
    1. Duration report exists and is parseable
    2. Required fields are present
    3. Metadata duration is identified (approximately correct)
    4. Actual duration is accurately determined
    5. Verification method is documented
    
    Returns:
        Dict with: passed (bool), score (int), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    feedback_parts = []
    score = 0.0
    
    # Step 1: Check if duration report exists and copy it
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    temp_report.close()
    
    try:
        copy_from_env("/tmp/vlc_duration_report.txt", temp_report.name)
        logger.info(f"Duration report copied to {temp_report.name}")
    except Exception as e:
        logger.error(f"Failed to copy duration report: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Duration report not found at /home/ga/Documents/duration_report.txt"
        }
    
    # Check if file is empty
    if os.path.getsize(temp_report.name) == 0:
        os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Duration report is empty. Please create the report with required format."
        }
    
    # Step 2: Parse the user's report
    user_report = parse_duration_report(temp_report.name)
    os.unlink(temp_report.name)
    
    if not user_report:
        return {
            "passed": False,
            "score": 10,
            "feedback": "❌ Could not parse duration report. Check format:\nMETADATA_DURATION: [seconds]\nACTUAL_DURATION: [seconds]\nVERIFICATION_METHOD: [description]"
        }
    
    # Step 3: Check required fields
    missing_fields = []
    if 'metadata_duration' not in user_report:
        missing_fields.append('METADATA_DURATION')
    if 'actual_duration' not in user_report:
        missing_fields.append('ACTUAL_DURATION')
    if 'verification_method' not in user_report:
        missing_fields.append('VERIFICATION_METHOD')
    
    if missing_fields:
        return {
            "passed": False,
            "score": 20,
            "feedback": f"❌ Missing required fields: {', '.join(missing_fields)}"
        }
    
    score += 20  # 20% for having all required fields
    feedback_parts.append("✅ Report format correct")
    
    # Step 4: Get ground truth by analyzing the test video
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_test_video.mp4",
        file_type='video'
    )
    
    if not success:
        logger.error(f"Could not copy test video for verification: {error}")
        return {
            "passed": False,
            "score": score,
            "feedback": f"❌ Could not verify: test video not available. {' | '.join(feedback_parts)}"
        }
    
    video_data = file_info.get('data', {})
    temp_dir = file_info.get('temp_dir', '')
    
    # Get the actual playable duration from the test video
    # This is the ground truth
    true_duration = video_data.get('duration', 0)
    
    if true_duration == 0:
        cleanup_verification_environment(temp_dir)
        logger.error("Could not determine true duration from test video")
        return {
            "passed": False,
            "score": score,
            "feedback": f"❌ Could not determine ground truth duration. {' | '.join(feedback_parts)}"
        }
    
    logger.info(f"Ground truth duration: {true_duration:.1f} seconds")
    
    # Expected metadata duration - this should be significantly larger than true duration
    # The setup creates a file truncated from ~600 seconds, so metadata will vary
    # We expect metadata to show somewhere between 300-600 seconds (incomplete file)
    # But actual playable is only ~120 seconds
    
    # For the truncated file, ffprobe might show various values depending on the truncation point
    # Let's be flexible: metadata should be significantly larger than actual (at least 2x)
    
    # Step 5: Verify user's metadata duration identification
    user_metadata = user_report['metadata_duration']
    
    # The metadata duration should be significantly larger than the true duration
    # Since we truncated a 600-second video, the metadata might show various values
    # But it should be noticeably larger than the actual ~120 seconds
    expected_metadata_min = true_duration * 1.5  # At least 1.5x the actual duration
    expected_metadata_max = 700  # Upper bound
    
    if expected_metadata_min <= user_metadata <= expected_metadata_max:
        score += 20  # 20% for metadata identification
        feedback_parts.append(f"✅ Metadata duration identified: {user_metadata:.0f}s")
    else:
        feedback_parts.append(f"⚠️ Metadata duration may be incorrect: {user_metadata:.0f}s (expected: {expected_metadata_min:.0f}-{expected_metadata_max:.0f}s)")
        score += 10  # Partial credit
    
    # Step 6: Verify user's actual duration determination (most important)
    user_actual = user_report['actual_duration']
    
    # Calculate difference from ground truth
    actual_diff = abs(user_actual - true_duration)
    actual_percent_error = (actual_diff / true_duration) * 100 if true_duration > 0 else 100
    
    logger.info(f"User actual duration: {user_actual:.1f}s, True: {true_duration:.1f}s, Diff: {actual_diff:.1f}s ({actual_percent_error:.1f}%)")
    
    # Scoring for actual duration (40% of total score)
    if actual_diff <= 5:  # Within 5 seconds - excellent
        score += 40
        feedback_parts.append(f"✅ Actual duration CORRECT: {user_actual:.0f}s (true: {true_duration:.0f}s, diff: {actual_diff:.1f}s)")
    elif actual_diff <= 10:  # Within 10 seconds - good
        score += 35
        feedback_parts.append(f"✅ Actual duration VERY CLOSE: {user_actual:.0f}s (true: {true_duration:.0f}s, diff: {actual_diff:.1f}s)")
    elif actual_diff <= 20:  # Within 20 seconds - acceptable
        score += 25
        feedback_parts.append(f"⚠️ Actual duration CLOSE: {user_actual:.0f}s (true: {true_duration:.0f}s, diff: {actual_diff:.1f}s)")
    elif actual_diff <= 40:  # Within 40 seconds - needs improvement
        score += 15
        feedback_parts.append(f"⚠️ Actual duration APPROXIMATE: {user_actual:.0f}s (true: {true_duration:.0f}s, diff: {actual_diff:.1f}s)")
    else:  # Too far off
        score += 5
        feedback_parts.append(f"❌ Actual duration INCORRECT: {user_actual:.0f}s (true: {true_duration:.0f}s, diff: {actual_diff:.1f}s)")
    
    # Step 7: Check verification method documentation (20% of score)
    method = user_report.get('verification_method', '')
    method_length = len(method.strip())
    
    if method_length >= 15:  # Reasonable explanation
        score += 20
        feedback_parts.append(f"✅ Verification method documented: '{method[:50]}{'...' if len(method) > 50 else ''}'")
    elif method_length >= 5:  # Minimal explanation
        score += 10
        feedback_parts.append(f"⚠️ Verification method brief: '{method}'")
    else:
        feedback_parts.append("❌ Verification method missing or too brief")
    
    # Clean up
    cleanup_verification_environment(temp_dir)
    
    # Step 8: Determine pass/fail
    # Convert score to 0-100 scale (it's already calculated as percentage)
    final_score = int(score)
    passed = final_score >= 70
    
    # Compile feedback
    if passed:
        feedback = "✅ TASK SUCCESSFUL!\n\n" + "\n".join(feedback_parts)
        feedback += f"\n\nFinal Score: {final_score}/100"
        feedback += "\n\nYou successfully identified that the video's metadata claims a longer duration than the actual playable content!"
    else:
        feedback = "❌ TASK INCOMPLETE\n\n" + "\n".join(feedback_parts)
        feedback += f"\n\nFinal Score: {final_score}/100"
        
        if final_score < 40:
            feedback += "\n\nTip: The actual duration is much shorter than what the metadata claims. Try seeking to the reported end time and playing - what happens? The video likely freezes or ends much earlier than expected."
        elif final_score < 70:
            feedback += "\n\nYou're close! Make sure your actual duration measurement is precise. Try playing through the video and noting exactly when it ends or becomes unplayable."
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": feedback
    }


# Entry point for gym-anything
def verify(export_dir: str) -> Dict[str, Any]:
    """
    Entry point expected by gym-anything framework.
    
    Note: This function signature is for standalone testing.
    The actual verification uses verify_true_duration(traj, env_info, task_info).
    """
    # This is for standalone testing only
    logger.warning("verify() called directly - this should not happen in production")
    return {
        "passed": False,
        "score": 0,
        "feedback": "Direct verify() call not supported - use verify_true_duration()"
    }
