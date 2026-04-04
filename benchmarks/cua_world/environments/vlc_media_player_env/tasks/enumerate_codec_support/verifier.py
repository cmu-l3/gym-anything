#!/usr/bin/env python3
"""
Verifier for Enumerate Codec Support task
Validates that VLC codec list was successfully extracted and documented
"""

import sys
import os
import re
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_enumerate_codec_support(traj, env_info, task_info):
    """
    Verify codec enumeration task completion.
    
    Checks:
    1. File exists at expected location
    2. File has sufficient content (>500 bytes)
    3. File contains video codec identifiers
    4. File contains audio codec identifiers
    5. File has structured format (multiple lines)
    6. File contains VLC-specific keywords
    
    Returns:
        Dict with score, passed status, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    # Container path for the codec list file
    container_path = "/tmp/vlc_codec_list.txt"
    
    # Create temp file for copying
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        # Criterion 1: File exists
        try:
            copy_from_env(container_path, temp_path)
        except Exception as e:
            logger.error(f"Error copying codec list file: {e}")
            feedback_parts.append(f"❌ File not found: {container_path}")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # File exists
        criteria_met += 1
        feedback_parts.append(f"✅ File exists")
        
        # Read file content
        try:
            with open(temp_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
        except Exception as e:
            logger.error(f"Error reading file: {e}")
            feedback_parts.append(f"❌ Error reading file: {e}")
            os.unlink(temp_path)
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 2: Sufficient content (min 500 bytes)
        file_size = len(content)
        if file_size >= 500:
            criteria_met += 1
            feedback_parts.append(f"✅ Sufficient content ({file_size} bytes)")
        else:
            feedback_parts.append(f"❌ Content too small ({file_size} bytes, need 500+)")
        
        # Normalize content for matching
        content_lower = content.lower()
        
        # Criterion 3: Video codecs present (need 3+)
        video_codecs = [
            'h264', 'x264', 'avc', 'h265', 'hevc', 
            'vp8', 'vp9', 'vpx', 'mpeg2', 'mpeg4', 
            'mp4v', 'theora', 'av1', 'dav1d', 'xvid', 
            'divx', 'h263', 'ffh264', 'avcodec'
        ]
        
        found_video = []
        for codec in video_codecs:
            if codec in content_lower:
                found_video.append(codec)
        
        # Remove duplicates
        found_video = list(set(found_video))
        
        if len(found_video) >= 3:
            criteria_met += 1
            sample_codecs = ', '.join(found_video[:5])
            feedback_parts.append(f"✅ Video codecs found: {sample_codecs}")
        else:
            feedback_parts.append(f"❌ Insufficient video codecs ({len(found_video)} found, need 3+)")
        
        # Criterion 4: Audio codecs present (need 3+)
        audio_codecs = [
            'mp3', 'mpga', 'aac', 'mp4a', 'vorbis', 
            'opus', 'flac', 'a52', 'dts', 'ac3',
            'wma', 'alac', 'ape', 'wavpack', 'speex',
            'mpeg audio', 'audio'
        ]
        
        found_audio = []
        for codec in audio_codecs:
            if codec in content_lower:
                found_audio.append(codec)
        
        # Remove duplicates
        found_audio = list(set(found_audio))
        
        if len(found_audio) >= 3:
            criteria_met += 1
            sample_codecs = ', '.join(found_audio[:5])
            feedback_parts.append(f"✅ Audio codecs found: {sample_codecs}")
        else:
            feedback_parts.append(f"❌ Insufficient audio codecs ({len(found_audio)} found, need 3+)")
        
        # Criterion 5: Structured format (multiple lines, not prose)
        lines = content.strip().split('\n')
        non_empty_lines = [line for line in lines if line.strip()]
        
        if len(non_empty_lines) >= 20:
            criteria_met += 1
            feedback_parts.append(f"✅ Structured format ({len(non_empty_lines)} lines)")
        else:
            feedback_parts.append(f"❌ Insufficient structure ({len(non_empty_lines)} lines, need 20+)")
        
        # Criterion 6: VLC-specific content
        vlc_keywords = [
            'plugin', 'module', 'decoder', 'codec', 
            'vlc', 'demux', 'mux', 'encoder', 
            'video output', 'audio output', 'access',
            'packetizer', 'stream_out'
        ]
        
        found_keywords = []
        for keyword in vlc_keywords:
            if keyword in content_lower:
                found_keywords.append(keyword)
        
        # Remove duplicates
        found_keywords = list(set(found_keywords))
        
        if len(found_keywords) >= 2:
            criteria_met += 1
            sample_keywords = ', '.join(found_keywords[:3])
            feedback_parts.append(f"✅ VLC-specific content: {sample_keywords}")
        else:
            feedback_parts.append(f"❌ Missing VLC-specific content (need keywords like: plugin, module, decoder)")
        
        # Clean up temp file
        os.unlink(temp_path)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = criteria_met >= 4  # Need at least 4/6 criteria (67%)
    
    # Add summary to feedback
    feedback_parts.append(f"📊 Score: {score}% ({criteria_met}/{total_criteria} criteria met)")
    
    if passed:
        feedback_parts.append("✅ PASSED")
    else:
        feedback_parts.append("❌ FAILED")
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria_met": criteria_met,
        "criteria_total": total_criteria,
        "details": {
            "video_codecs_found": len(found_video) if 'found_video' in locals() else 0,
            "audio_codecs_found": len(found_audio) if 'found_audio' in locals() else 0,
            "file_size": file_size if 'file_size' in locals() else 0,
            "line_count": len(non_empty_lines) if 'non_empty_lines' in locals() else 0
        }
    }


# For backward compatibility if called differently
def verify(copy_from_env_fn=None, **kwargs):
    """
    Alternative entry point for gym_anything compatibility.
    """
    env_info = {'copy_from_env': copy_from_env_fn}
    return verify_enumerate_codec_support(None, env_info, {})
