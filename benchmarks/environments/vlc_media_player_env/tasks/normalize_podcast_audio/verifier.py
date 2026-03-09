#!/usr/bin/env python3
"""
Verifier for Normalize Podcast Audio task

Checks:
1. All three normalized files exist
2. Files are valid MP3 format
3. Peak levels are consistent (within ±0.5 dB)
4. No clipping (peaks below 0 dB)
"""

import sys
import os
import logging
import subprocess
import re
import tempfile
import shutil

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_audio_peak_db(filepath: str) -> float:
    """
    Get peak audio level in dB using ffmpeg volumedetect.
    Returns the max_volume value (negative dB below 0).
    """
    try:
        cmd = [
            'ffmpeg', '-i', filepath,
            '-af', 'volumedetect',
            '-f', 'null', '/dev/null'
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        # Parse max_volume from stderr
        for line in result.stderr.split('\n'):
            if 'max_volume:' in line:
                match = re.search(r'max_volume:\s*([-\d.]+)\s*dB', line)
                if match:
                    return float(match.group(1))
        
        return None
        
    except Exception as e:
        logger.error(f"Error getting audio peak: {e}")
        return None


def verify_audio_format(filepath: str) -> bool:
    """Verify file is valid MP3 format."""
    try:
        cmd = ['ffprobe', '-v', 'error', '-select_streams', 'a:0',
               '-show_entries', 'stream=codec_name', '-of', 'default=noprint_wrappers=1:nokey=1',
               filepath]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        codec = result.stdout.strip().lower()
        return 'mp3' in codec
    except Exception as e:
        logger.error(f"Error verifying audio format: {e}")
        return False


def verify_normalize_podcast_audio(traj, env_info, task_info):
    """
    Verify normalize podcast audio task completion.
    
    Checks:
    1. All three files present
    2. Files are valid MP3 format
    3. Peak levels consistent (within ±0.5 dB)
    4. No clipping (peaks below 0 dB)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "❌ Copy function not available"}
    
    criteria_met = 0.0
    total_criteria = 4.0
    feedback_parts = []
    
    # Expected files
    expected_files = [
        "normalized_segment_intro.mp3",
        "normalized_segment_interview.mp3",
        "normalized_segment_outro.mp3"
    ]
    
    # Create temp directory for copied files
    temp_dir = tempfile.mkdtemp(prefix='vlc_normalize_verify_')
    
    try:
        # Criterion 1: Check all files exist
        files_present = []
        files_missing = []
        
        for filename in expected_files:
            temp_file = os.path.join(temp_dir, filename)
            container_path = f"/tmp/{filename}"
            
            try:
                copy_from_env(container_path, temp_file)
                if os.path.exists(temp_file) and os.path.getsize(temp_file) > 0:
                    files_present.append(filename)
                else:
                    files_missing.append(filename)
            except Exception as e:
                logger.warning(f"Could not copy {filename}: {e}")
                files_missing.append(filename)
        
        if len(files_present) == 3:
            criteria_met += 1.0
            feedback_parts.append(f"✅ All 3 files present")
        elif len(files_present) > 0:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Only {len(files_present)}/3 files present: {', '.join(files_present)}")
        else:
            feedback_parts.append(f"❌ No normalized files found")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {"passed": False, "score": 0.0, "feedback": " | ".join(feedback_parts)}
        
        # Criterion 2: Verify all files are valid MP3
        valid_formats = []
        invalid_formats = []
        
        for filename in files_present:
            temp_file = os.path.join(temp_dir, filename)
            if verify_audio_format(temp_file):
                valid_formats.append(filename)
            else:
                invalid_formats.append(filename)
        
        if len(valid_formats) == len(files_present):
            criteria_met += 1.0
            feedback_parts.append(f"✅ All files are valid MP3 format")
        elif len(valid_formats) > 0:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Some files have invalid format: {', '.join(invalid_formats)}")
        else:
            feedback_parts.append(f"❌ Files are not valid MP3 format")
        
        # Criterion 3: Check peak levels are consistent
        peak_levels = {}
        
        for filename in valid_formats:
            temp_file = os.path.join(temp_dir, filename)
            peak_db = get_audio_peak_db(temp_file)
            if peak_db is not None:
                peak_levels[filename] = peak_db
        
        if len(peak_levels) >= 2:
            peaks = list(peak_levels.values())
            peak_range = max(peaks) - min(peaks)
            
            feedback_parts.append(f"Peak levels: {', '.join([f'{k}: {v:.2f}dB' for k, v in peak_levels.items()])}")
            
            if peak_range <= 0.5:
                criteria_met += 1.0
                feedback_parts.append(f"✅ Peak levels consistent (range: {peak_range:.2f}dB ≤ 0.5dB)")
            elif peak_range <= 1.5:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Peak levels somewhat consistent (range: {peak_range:.2f}dB, target: ≤0.5dB)")
            else:
                feedback_parts.append(f"❌ Peak levels not consistent (range: {peak_range:.2f}dB, target: ≤0.5dB)")
        else:
            feedback_parts.append(f"⚠️ Could not measure peak levels for all files")
        
        # Criterion 4: Check for clipping (peaks should be below 0 dB)
        clipped_files = []
        no_clipping = []
        
        for filename, peak in peak_levels.items():
            if peak > -0.1:  # Allow tiny margin for measurement error
                clipped_files.append(f"{filename} ({peak:.2f}dB)")
            else:
                no_clipping.append(filename)
        
        if len(clipped_files) == 0 and len(peak_levels) >= 2:
            criteria_met += 1.0
            feedback_parts.append(f"✅ No clipping detected")
        elif len(no_clipping) > len(clipped_files):
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Some clipping detected: {', '.join(clipped_files)}")
        elif len(clipped_files) > 0:
            feedback_parts.append(f"❌ Clipping detected: {', '.join(clipped_files)}")
        
        # Cleanup
        shutil.rmtree(temp_dir, ignore_errors=True)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        shutil.rmtree(temp_dir, ignore_errors=True)
        return {"passed": False, "score": 0.0, "feedback": f"❌ Verification error: {str(e)}"}
    
    # Calculate score
    score = (criteria_met / total_criteria) * 100
    passed = score >= 75.0
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
