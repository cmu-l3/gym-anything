#!/usr/bin/env python3
"""
Verifier for Compress for Email task

This verifier implements comprehensive validation of video compression
including size constraints, quality checks, and compression efficiency.
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    get_audio_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def load_original_video_info(copy_from_env):
    """
    Load original video properties for comparison.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict with original video properties or None if not available
    """
    temp_info = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_original_info.json", temp_info.name)
        
        with open(temp_info.name, 'r') as f:
            original_data = json.load(f)
        
        # Extract relevant properties
        info = {
            'size_mb': 75.0,  # Default fallback
            'duration': 135.0,
            'width': 1920,
            'height': 1080
        }
        
        # Try to extract from ffprobe JSON
        if 'format' in original_data:
            format_info = original_data['format']
            if 'size' in format_info:
                info['size_mb'] = int(format_info['size']) / (1024 * 1024)
            if 'duration' in format_info:
                info['duration'] = float(format_info['duration'])
        
        if 'streams' in original_data:
            for stream in original_data['streams']:
                if stream.get('codec_type') == 'video':
                    if 'width' in stream:
                        info['width'] = int(stream['width'])
                    if 'height' in stream:
                        info['height'] = int(stream['height'])
                    break
        
        os.unlink(temp_info.name)
        logger.info(f"Loaded original video info: {info}")
        return info
        
    except Exception as e:
        logger.warning(f"Could not load original video info: {e}")
        os.unlink(temp_info.name)
        # Return default values
        return {
            'size_mb': 75.0,
            'duration': 135.0,
            'width': 1920,
            'height': 1080
        }


def verify_compress_for_email(traj, env_info, task_info):
    """
    Verify compress for email task completion.
    
    Comprehensive verification including:
    1. File size under 25MB (HARD REQUIREMENT)
    2. File valid and playable
    3. Duration preserved
    4. Audio-video sync
    5. Efficient codec used
    6. Quality maintained
    7. Optimal size range
    
    Args:
        traj: Agent trajectory (not used here)
        env_info: Environment info containing copy_from_env function
        task_info: Task info (not used here)
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Load original video properties
    original_info = load_original_video_info(copy_from_env)
    
    # === STAGE 1: Load and validate compressed video ===
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_compressed_email.mp4",
        file_type='video'
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Compressed video not found: {error}"
        }
    
    try:
        local_path = file_info['filepath']
        video_info = file_info['data']
        
        # === CRITERION 1: File Size Check (HARD REQUIREMENT) ===
        file_size_bytes = os.path.getsize(local_path)
        file_size_mb = file_size_bytes / (1024 * 1024)
        
        SIZE_LIMIT_MB = 25.0
        SIZE_LIMIT_BYTES = 26214400  # 25 * 1024 * 1024
        
        feedback_parts.append(f"📊 File size: {file_size_mb:.2f}MB")
        
        if file_size_bytes > SIZE_LIMIT_BYTES:
            feedback_parts.insert(0, f"❌ FAILED: File size {file_size_mb:.2f}MB exceeds 25MB limit")
            cleanup_verification_environment(file_info['temp_dir'])
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        score += 40
        feedback_parts.insert(0, f"✅ Size requirement met: {file_size_mb:.2f}MB < 25MB")
        
        # Bonus for optimal size range (18-24MB)
        if 18.0 <= file_size_mb <= 24.0:
            score += 5
            feedback_parts.append("✅ Optimal size range (18-24MB)")
        elif file_size_mb < 18.0:
            score += 3
            feedback_parts.append(f"⭐ Excellent compression: {file_size_mb:.2f}MB")
        
        # === CRITERION 2: File Validity Check ===
        if 'error' in video_info:
            feedback_parts.append(f"❌ Invalid video file: {video_info['error']}")
            cleanup_verification_environment(file_info['temp_dir'])
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        score += 15
        feedback_parts.append("✅ File is valid and playable")
        
        # === CRITERION 3: Duration Check ===
        original_duration = original_info['duration']
        output_duration = video_info.get('duration', 0)
        
        if output_duration == 0:
            feedback_parts.append("⚠️ Could not determine video duration")
        else:
            duration_diff = abs(output_duration - original_duration)
            duration_diff_percent = (duration_diff / original_duration) * 100
            
            if duration_diff_percent <= 5.0:
                score += 10
                feedback_parts.append(f"✅ Duration preserved: {output_duration:.1f}s (original: {original_duration:.1f}s)")
            elif duration_diff_percent <= 10.0:
                score += 5
                feedback_parts.append(f"⚠️ Duration slightly off: {output_duration:.1f}s vs {original_duration:.1f}s ({duration_diff_percent:.1f}% difference)")
            else:
                feedback_parts.append(f"⚠️ Duration mismatch: {output_duration:.1f}s vs {original_duration:.1f}s ({duration_diff_percent:.1f}% difference)")
        
        # === CRITERION 4: Codec Efficiency Check ===
        video_codec = video_info.get('codec', '').lower()
        efficient_codecs = ['h264', 'h265', 'hevc', 'vp9', 'av1', 'x264', 'x265']
        
        if any(codec in video_codec for codec in efficient_codecs):
            score += 10
            feedback_parts.append(f"✅ Efficient codec used: {video_codec}")
        else:
            feedback_parts.append(f"⚠️ Suboptimal codec: {video_codec}")
        
        # === CRITERION 5: Audio Presence and Sync Check ===
        audio_info = get_audio_info(local_path)
        
        if 'error' not in audio_info and audio_info.get('codec'):
            score += 5
            feedback_parts.append(f"✅ Audio track present: {audio_info.get('codec')}")
            
            # Audio-video sync check (duration comparison)
            audio_duration = audio_info.get('duration', 0)
            if audio_duration > 0 and output_duration > 0:
                av_sync_diff = abs(audio_duration - output_duration)
                
                if av_sync_diff < 0.5:  # < 500ms
                    score += 10
                    feedback_parts.append(f"✅ A/V sync perfect: {av_sync_diff*1000:.0f}ms difference")
                elif av_sync_diff < 2.0:
                    score += 7
                    feedback_parts.append(f"✅ A/V sync good: {av_sync_diff*1000:.0f}ms difference")
                elif av_sync_diff < 5.0:
                    score += 3
                    feedback_parts.append(f"⚠️ A/V sync acceptable: {av_sync_diff:.2f}s difference")
                else:
                    feedback_parts.append(f"⚠️ A/V sync issues: {av_sync_diff:.2f}s difference")
            else:
                score += 5  # Partial credit if can't measure sync
        else:
            feedback_parts.append("⚠️ Audio track missing or invalid")
        
        # === CRITERION 6: Compression Efficiency ===
        original_size_mb = original_info['size_mb']
        compression_ratio = original_size_mb / file_size_mb if file_size_mb > 0 else 0
        
        if compression_ratio >= 3.0:
            score += 5
            feedback_parts.append(f"✅ Good compression ratio: {compression_ratio:.1f}:1")
        elif compression_ratio >= 2.0:
            score += 3
            feedback_parts.append(f"✅ Acceptable compression: {compression_ratio:.1f}:1")
        else:
            feedback_parts.append(f"⚠️ Low compression ratio: {compression_ratio:.1f}:1")
        
        # === CRITERION 7: Resolution Check ===
        original_width = original_info['width']
        original_height = original_info['height']
        output_width = video_info.get('width', 0)
        output_height = video_info.get('height', 0)
        
        original_res = f"{original_width}x{original_height}"
        output_res = f"{output_width}x{output_height}"
        
        resolution_reduced = (output_width < original_width or output_height < original_height)
        
        if resolution_reduced:
            score += 5
            feedback_parts.append(f"✅ Resolution optimized: {original_res} → {output_res}")
        else:
            feedback_parts.append(f"ℹ️ Resolution maintained: {output_res}")
        
        # === CRITERION 8: Format Check ===
        format_name = video_info.get('format', '').lower()
        if 'mp4' in format_name:
            score += 2
            feedback_parts.append("✅ Optimal format: MP4")
        else:
            feedback_parts.append(f"ℹ️ Format: {format_name}")
        
        # === CRITERION 9: Check for trivial solutions ===
        # Ensure video wasn't just truncated/trimmed
        if output_duration > 0 and original_duration > 0:
            if output_duration < (original_duration * 0.5):
                score -= 20
                feedback_parts.append("⚠️ PENALTY: Video appears to be truncated rather than compressed")
        
        # Ensure some actual compression occurred
        if video_info.get('bitrate', 0) > 5000000:  # > 5 Mbps seems too high for target size
            feedback_parts.append("⚠️ WARNING: Bitrate seems high for target file size")
        
        # === Final Assessment ===
        # Cap score at 100
        score = min(score, max_score)
        
        passed = score >= 75
        
        if passed:
            feedback_parts.insert(0, f"🎉 TASK SUCCESS: Score {score}/{max_score}")
        else:
            feedback_parts.insert(0, f"❌ TASK FAILED: Score {score}/{max_score} (need 75+)")
        
        cleanup_verification_environment(file_info['temp_dir'])
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        feedback_parts.append(f"❌ Verification error: {str(e)}")
        
        if 'temp_dir' in file_info:
            cleanup_verification_environment(file_info['temp_dir'])
        
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
