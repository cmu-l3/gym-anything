#!/usr/bin/env python3
"""
Verifier for Create Time-lapse task (create_timelapse@1)

Validates that a time-lapse video was created with correct speed-up ratio.
"""

import sys
import os
import logging
import tempfile
import json
import subprocess

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    verify_video_resolution,
    verify_video_codec,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_timelapse(traj, env_info, task_info):
    """
    Verify create time-lapse task completion.
    
    Success criteria:
    1. Output file exists and is valid
    2. Duration is approximately 1/60th of source (±15% tolerance)
    3. Resolution maintained (1920x1080)
    4. Video is playable (has valid codec and properties)
    
    Returns:
        dict with keys: passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Expected values
    EXPECTED_SPEEDUP = 60.0
    SPEEDUP_TOLERANCE = 0.15  # ±15% tolerance
    EXPECTED_WIDTH = 1920
    EXPECTED_HEIGHT = 1080
    
    temp_files = []  # Track temp files for cleanup
    
    try:
        # ============================================================
        # Step 1: Get source video information
        # ============================================================
        temp_source_info = tempfile.NamedTemporaryFile(delete=False, suffix='_source.json', mode='w+')
        temp_files.append(temp_source_info.name)
        
        try:
            copy_from_env("/tmp/vlc_timelapse_source_info.json", temp_source_info.name)
            
            with open(temp_source_info.name, 'r') as f:
                source_info = json.load(f)
            
            if 'error' in source_info:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"❌ Source video info error: {source_info['error']}"
                }
            
            source_duration = float(source_info.get('source_duration', 0))
            expected_output_duration = float(source_info.get('expected_output_duration', source_duration / 60.0))
            
            if source_duration <= 0:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "❌ Invalid source video duration"
                }
            
            feedback_parts.append(f"📊 Source: {source_duration:.1f}s")
            logger.info(f"Source video duration: {source_duration:.1f}s")
            
        except Exception as e:
            logger.error(f"Error reading source info: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Cannot read source video info: {str(e)}"
            }
        
        # ============================================================
        # Step 2: Check if output video exists
        # ============================================================
        temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='_output.mp4', mode='wb')
        temp_files.append(temp_output.name)
        temp_output.close()
        
        try:
            copy_from_env("/tmp/vlc_timelapse_output.mp4", temp_output.name)
        except Exception as e:
            logger.error(f"Error copying output video: {e}")
            feedback_parts.append("❌ Output video not found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts) + f" | Error: {str(e)}"
            }
        
        # Check file size
        if not os.path.exists(temp_output.name) or os.path.getsize(temp_output.name) == 0:
            feedback_parts.append("❌ Output file empty or missing")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        output_size_mb = os.path.getsize(temp_output.name) / (1024 * 1024)
        criteria_met += 1
        feedback_parts.append(f"✅ Output exists ({output_size_mb:.2f} MB)")
        logger.info(f"Output video found: {output_size_mb:.2f} MB")
        
        # ============================================================
        # Step 3: Analyze output video properties
        # ============================================================
        output_info = get_video_info(temp_output.name)
        
        if 'error' in output_info:
            feedback_parts.append(f"❌ Output video invalid: {output_info['error']}")
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        output_duration = output_info.get('duration', 0)
        output_width = output_info.get('width', 0)
        output_height = output_info.get('height', 0)
        output_codec = output_info.get('codec', 'unknown')
        
        if output_duration <= 0:
            feedback_parts.append("❌ Output video has invalid duration")
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        feedback_parts.append(f"📊 Output: {output_duration:.1f}s")
        logger.info(f"Output video duration: {output_duration:.1f}s, codec: {output_codec}, resolution: {output_width}x{output_height}")
        
        # ============================================================
        # Step 4: Verify speed-up ratio
        # ============================================================
        actual_speedup = source_duration / output_duration
        speedup_ratio = actual_speedup / EXPECTED_SPEEDUP
        speedup_error = abs(actual_speedup - EXPECTED_SPEEDUP) / EXPECTED_SPEEDUP
        
        logger.info(f"Speed-up analysis: expected={EXPECTED_SPEEDUP}x, actual={actual_speedup:.1f}x, error={speedup_error:.1%}")
        
        if speedup_error <= SPEEDUP_TOLERANCE:
            criteria_met += 1
            feedback_parts.append(f"✅ Speed-up: {actual_speedup:.1f}x (target: {EXPECTED_SPEEDUP}x)")
        else:
            feedback_parts.append(f"❌ Speed-up: {actual_speedup:.1f}x (target: {EXPECTED_SPEEDUP}x ±{SPEEDUP_TOLERANCE*100:.0f}%)")
            feedback_parts.append(f"   Expected ~{expected_output_duration:.1f}s but got {output_duration:.1f}s")
        
        # ============================================================
        # Step 5: Verify resolution maintained
        # ============================================================
        if output_width == EXPECTED_WIDTH and output_height == EXPECTED_HEIGHT:
            criteria_met += 1
            feedback_parts.append(f"✅ Resolution: {output_width}x{output_height}")
        else:
            feedback_parts.append(f"❌ Resolution: {output_width}x{output_height} (expected: {EXPECTED_WIDTH}x{EXPECTED_HEIGHT})")
        
        # ============================================================
        # Step 6: Verify video is playable and valid
        # ============================================================
        video_valid = (
            output_codec and
            output_codec.lower() in ['h264', 'h265', 'vp8', 'vp9', 'mpeg4', 'xvid', 'hevc'] and
            output_width > 0 and
            output_height > 0 and
            output_duration > 0
        )
        
        if video_valid:
            criteria_met += 1
            feedback_parts.append(f"✅ Valid video (codec: {output_codec})")
        else:
            feedback_parts.append(f"⚠️ Video may have issues (codec: {output_codec})")
        
        # ============================================================
        # Calculate final score
        # ============================================================
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        # Success message
        if passed:
            feedback_parts.append(f"🎉 Time-lapse created successfully!")
        else:
            feedback_parts.append(f"⚠️ Task incomplete (score: {score}%)")
        
        feedback = "\n".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "metadata": {
                "source_duration": source_duration,
                "output_duration": output_duration,
                "actual_speedup": round(actual_speedup, 2),
                "expected_speedup": EXPECTED_SPEEDUP,
                "speedup_error_percent": round(speedup_error * 100, 1),
                "resolution": f"{output_width}x{output_height}",
                "codec": output_codec,
                "output_size_mb": round(output_size_mb, 2)
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup temp files
        for temp_file in temp_files:
            try:
                if os.path.exists(temp_file):
                    os.unlink(temp_file)
            except Exception as e:
                logger.warning(f"Failed to cleanup temp file {temp_file}: {e}")
