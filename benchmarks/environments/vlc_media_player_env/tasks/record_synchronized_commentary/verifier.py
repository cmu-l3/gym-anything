#!/usr/bin/env python3
"""
Verifier for Record Synchronized Commentary task

Verifies that the agent successfully recorded audio commentary
while playing back video in VLC.
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_audio_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_commentary_recording(traj, env_info, task_info):
    """
    Verify that audio commentary was successfully recorded.
    
    Success criteria:
    1. Audio file exists in expected location
    2. Audio has valid properties (codec, sample rate, channels)
    3. Duration is reasonable (at least 120 seconds, max 210 seconds)
    4. File size indicates actual content (min 200KB)
    
    Args:
        traj: Agent trajectory (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration (not used)
        
    Returns:
        Dict with passed, score, feedback keys
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
    details = {}
    
    try:
        # First, check if metadata file exists
        temp_metadata = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        try:
            copy_from_env("/tmp/vlc_recording_metadata.json", temp_metadata.name)
            
            with open(temp_metadata.name, 'r') as f:
                metadata = json.load(f)
            
            details['metadata'] = metadata
            
            if not metadata.get('found', False):
                feedback_parts.append("❌ No recorded audio file found in container")
                feedback_parts.append("   Expected location: /home/ga/Videos/recorded_commentary/")
                feedback_parts.append("   Agent may not have started recording")
                os.unlink(temp_metadata.name)
                
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "\n".join(feedback_parts),
                    "details": details
                }
            
            os.unlink(temp_metadata.name)
            
        except Exception as e:
            logger.warning(f"Could not read metadata file: {e}")
            # Continue anyway, try to find the audio file directly
        
        # Criterion 1: Check if audio file exists
        success, file_info, error = setup_verification_environment(
            copy_from_env,
            "/tmp/vlc_recorded_commentary.mp3",
            file_type='audio'
        )
        
        if not success:
            feedback_parts.append(f"❌ Audio file not found: {error}")
            feedback_parts.append("   Recording may not have been started or saved")
            return {
                "passed": False,
                "score": 0,
                "feedback": "\n".join(feedback_parts),
                "details": details
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Recorded audio file found")
        
        # Get audio data
        audio_data = file_info.get('data', {})
        filepath = file_info.get('filepath', '')
        
        # Check for errors in audio parsing
        if 'error' in audio_data:
            feedback_parts.append(f"❌ Could not parse audio file: {audio_data['error']}")
            cleanup_verification_environment(file_info.get('temp_dir'))
            return {
                "passed": False,
                "score": 25,
                "feedback": "\n".join(feedback_parts),
                "details": details
            }
        
        # Extract audio properties
        duration = audio_data.get('duration', 0)
        codec = audio_data.get('codec', 'unknown')
        sample_rate = audio_data.get('sample_rate', 0)
        channels = audio_data.get('channels', 0)
        bitrate = audio_data.get('bitrate', 0)
        size_bytes = audio_data.get('size_bytes', 0)
        
        details['audio_properties'] = {
            'duration': duration,
            'codec': codec,
            'sample_rate': sample_rate,
            'channels': channels,
            'bitrate': bitrate,
            'size_bytes': size_bytes,
            'size_kb': size_bytes / 1024 if size_bytes > 0 else 0
        }
        
        # Criterion 2: Valid audio properties
        if codec and codec != 'unknown' and sample_rate > 0:
            criteria_met += 1
            feedback_parts.append(f"✅ Valid audio properties:")
            feedback_parts.append(f"   Codec: {codec}")
            feedback_parts.append(f"   Sample rate: {sample_rate} Hz")
            feedback_parts.append(f"   Channels: {channels}")
            if bitrate > 0:
                feedback_parts.append(f"   Bitrate: {bitrate // 1000} kbps")
        else:
            feedback_parts.append("❌ Invalid or missing audio properties")
            feedback_parts.append(f"   Codec: {codec}, Sample rate: {sample_rate}")
        
        # Criterion 3: Duration check (at least 120 seconds, max 210 seconds)
        if duration > 0:
            feedback_parts.append(f"✅ Duration: {duration:.1f} seconds")
            
            if duration >= 120 and duration <= 210:
                criteria_met += 1
                feedback_parts.append(f"✅ Duration meets requirement (120-210s)")
            elif duration < 120:
                feedback_parts.append(f"❌ Recording too short: {duration:.1f}s (minimum: 120s)")
                feedback_parts.append("   Task requires at least 2 minutes of recording")
            else:
                # Duration > 210 is acceptable, just warn
                criteria_met += 1
                feedback_parts.append(f"⚠️  Recording longer than expected: {duration:.1f}s")
                feedback_parts.append("   (This is acceptable, just unusual)")
        else:
            feedback_parts.append("❌ Could not determine audio duration")
        
        # Criterion 4: File size check (minimum 200KB)
        size_kb = size_bytes / 1024 if size_bytes > 0 else 0
        
        if size_kb >= 200:
            criteria_met += 1
            feedback_parts.append(f"✅ File size sufficient: {size_kb:.1f} KB")
        else:
            feedback_parts.append(f"❌ File size too small: {size_kb:.1f} KB (minimum: 200 KB)")
            feedback_parts.append("   Recording may be incomplete or corrupted")
        
        # Quality checks (informational, not scored)
        if sample_rate > 0 and sample_rate < 16000:
            feedback_parts.append(f"⚠️  Low sample rate ({sample_rate} Hz) - quality may be poor")
        
        if duration > 0 and size_bytes > 0:
            # Calculate approximate bitrate if not provided
            if bitrate == 0:
                calc_bitrate = (size_bytes * 8) / duration / 1000  # kbps
                feedback_parts.append(f"   Calculated bitrate: ~{calc_bitrate:.0f} kbps")
                
                if calc_bitrate < 32:
                    feedback_parts.append("⚠️  Very low bitrate - quality may be poor")
        
        # Cleanup
        cleanup_verification_environment(file_info.get('temp_dir'))
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need 3 out of 4 criteria
        
        # Add summary
        if passed:
            feedback_parts.insert(0, "")
            feedback_parts.insert(0, "✅ SUCCESS: Audio commentary recorded successfully!")
        else:
            feedback_parts.insert(0, "")
            feedback_parts.insert(0, f"❌ FAILED: Only {criteria_met}/{total_criteria} criteria met")
        
        feedback = "\n".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": details
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification failed with error: {str(e)}",
            "details": details
        }
