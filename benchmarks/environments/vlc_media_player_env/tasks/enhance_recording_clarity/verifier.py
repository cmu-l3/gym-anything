#!/usr/bin/env python3
"""
Verifier for Enhance Recording Clarity task
"""

import sys
import os
import logging
import re
import subprocess

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_audio_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_volume_from_file(filepath):
    """Parse mean_volume from volumedetect output file."""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        # Look for mean_volume in format: "mean_volume: -XX.X dB"
        match = re.search(r'mean_volume:\s*([-\d.]+)\s*dB', content)
        if match:
            return float(match.group(1))
        
        return None
    except Exception as e:
        logger.error(f"Error parsing volume file {filepath}: {e}")
        return None


def analyze_audio_rms(filepath):
    """Analyze RMS level of audio file."""
    try:
        result = subprocess.run([
            'ffmpeg', '-i', filepath,
            '-af', 'astats=metadata=1:reset=1',
            '-f', 'null', '-'
        ], capture_output=True, text=True, timeout=30)
        
        # Parse RMS level from output
        for line in result.stderr.split('\n'):
            if 'RMS level dB' in line:
                match = re.search(r'RMS level dB:\s*([-\d.]+)', line)
                if match:
                    return float(match.group(1))
        
        return None
    except Exception as e:
        logger.error(f"Error analyzing RMS for {filepath}: {e}")
        return None


def verify_enhance_recording_clarity(traj, env_info, task_info):
    """
    Verify audio enhancement task completion.
    
    Checks:
    1. Enhanced file exists
    2. Duration matches original
    3. Volume increased (compression applied)
    4. RMS level improved
    5. File has reasonable properties
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Step 1: Check if enhanced file exists
    logger.info("Step 1: Checking for enhanced recording...")
    
    success, enhanced_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_enhanced_audio.mp3",
        file_type='audio'
    )
    
    if not success:
        return {"passed": False, "score": 0.0, 
                "feedback": f"❌ Enhanced recording not found. {error} | Hint: Use Media → Convert/Save to export audio with effects applied"}
    
    feedback_parts.append("✅ Enhanced recording exists")
    criteria_met += 1
    
    # Step 2: Verify basic audio properties
    logger.info("Step 2: Verifying audio properties...")
    
    enhanced_data = enhanced_info['data']
    
    if 'duration' not in enhanced_data or enhanced_data['duration'] < 10:
        cleanup_verification_environment(enhanced_info.get('temp_dir'))
        return {"passed": False, "score": 20.0, 
                "feedback": f"❌ Enhanced audio too short: {enhanced_data.get('duration', 0):.1f}s (expected ~20s)"}
    
    feedback_parts.append(f"✅ Duration valid: {enhanced_data['duration']:.1f}s")
    
    # Step 3: Load and compare with original
    logger.info("Step 3: Loading original for comparison...")
    
    success_orig, original_info, error_orig = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_original_audio.mp3",
        file_type='audio'
    )
    
    if not success_orig:
        cleanup_verification_environment(enhanced_info.get('temp_dir'))
        return {"passed": False, "score": 20.0, 
                "feedback": f"❌ Cannot load original audio for comparison"}
    
    original_data = original_info['data']
    
    # Check duration similarity
    duration_diff = abs(enhanced_data['duration'] - original_data['duration'])
    if duration_diff <= 2.0:
        criteria_met += 1
        feedback_parts.append(f"✅ Duration matches original (±{duration_diff:.1f}s)")
    else:
        feedback_parts.append(f"⚠️ Duration mismatch: {duration_diff:.1f}s difference")
    
    # Step 4: Analyze volume levels
    logger.info("Step 4: Analyzing volume levels...")
    
    import tempfile
    
    # Copy volume analysis files
    original_volume = None
    enhanced_volume = None
    
    try:
        temp_orig_vol = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/original_volume.txt", temp_orig_vol.name)
        original_volume = parse_volume_from_file(temp_orig_vol.name)
        os.unlink(temp_orig_vol.name)
    except Exception as e:
        logger.warning(f"Could not load original volume: {e}")
    
    try:
        temp_enh_vol = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/enhanced_volume.txt", temp_enh_vol.name)
        enhanced_volume = parse_volume_from_file(temp_enh_vol.name)
        os.unlink(temp_enh_vol.name)
    except Exception as e:
        logger.warning(f"Could not load enhanced volume: {e}")
    
    if original_volume is not None and enhanced_volume is not None:
        volume_increase = enhanced_volume - original_volume
        
        feedback_parts.append(f"📊 Original: {original_volume:.1f} dB, Enhanced: {enhanced_volume:.1f} dB")
        feedback_parts.append(f"📊 Volume increase: {volume_increase:.1f} dB")
        
        if volume_increase >= 3.0:
            criteria_met += 1
            feedback_parts.append("✅ Significant volume boost (≥3dB)")
        elif volume_increase >= 1.0:
            criteria_met += 0.5
            feedback_parts.append("⚠️ Moderate volume boost (1-3dB)")
        else:
            feedback_parts.append("⚠️ Minimal volume change")
    else:
        feedback_parts.append("⚠️ Could not measure volume levels")
    
    # Step 5: Check RMS levels (signal quality)
    logger.info("Step 5: Checking RMS levels...")
    
    enhanced_file = enhanced_info['data']['filepath']
    original_file = original_info['data']['filepath']
    
    enhanced_rms = analyze_audio_rms(enhanced_file)
    original_rms = analyze_audio_rms(original_file)
    
    if enhanced_rms is not None and original_rms is not None:
        rms_improvement = enhanced_rms - original_rms
        
        if rms_improvement > 0:
            criteria_met += 1
            feedback_parts.append(f"✅ RMS improved by {rms_improvement:.1f} dB")
        else:
            feedback_parts.append(f"⚠️ RMS not significantly improved")
    elif enhanced_rms is not None:
        feedback_parts.append(f"📊 Enhanced RMS: {enhanced_rms:.1f} dB")
        criteria_met += 0.5
    else:
        feedback_parts.append("⚠️ Could not analyze RMS levels")
    
    # Cleanup
    cleanup_verification_environment(enhanced_info.get('temp_dir'))
    cleanup_verification_environment(original_info.get('temp_dir'))
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 60
    
    feedback = " | ".join(feedback_parts)
    feedback += f"\n\nScore: {score}% ({'PASS' if passed else 'FAIL'})"
    
    if passed:
        feedback += " | 🎉 Audio enhancement successfully applied!"
    else:
        feedback += " | Hint: Apply Compressor (ratio 4:1) and Equalizer (boost 600Hz-3kHz, reduce <200Hz) in Effects panel, then export with effects enabled"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }