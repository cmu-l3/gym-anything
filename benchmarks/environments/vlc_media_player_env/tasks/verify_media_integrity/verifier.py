#!/usr/bin/env python3
"""
Verifier for Verify Media Integrity task
"""

import sys
import os
import logging
import tempfile
import re
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_media_integrity(traj, env_info, task_info):
    """
    Verify the media verification task completion.
    
    Checks:
    1. Verification report exists
    2. Report contains actual resolution from video
    3. Report contains actual codec
    4. Report contains duration
    5. Pass/fail determination is correct based on specs
    
    Returns:
        dict: Verification result with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    score = 0.0
    max_score = 100.0
    feedback = []
    
    report_path_container = "/tmp/vlc_verification_report.txt"
    video_path_container = "/tmp/vlc_verification_video.mp4"
    
    # Get actual video specs for comparison
    temp_dir = tempfile.mkdtemp(prefix='verify_media_integrity_')
    
    try:
        # Copy video file to analyze it
        host_video = Path(temp_dir) / "video.mp4"
        try:
            copy_from_env(video_path_container, str(host_video))
        except Exception as e:
            feedback.append(f"❌ Could not access video file: {e}")
            cleanup_verification_environment(temp_dir)
            return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}
        
        # Get actual video properties
        actual_specs = get_video_info(str(host_video))
        
        if 'error' in actual_specs:
            feedback.append(f"⚠️ Could not analyze video: {actual_specs['error']}")
            # Continue anyway, might still check report
        else:
            actual_width = actual_specs.get('width', 0)
            actual_height = actual_specs.get('height', 0)
            actual_codec = actual_specs.get('codec', '').lower()
            actual_duration = actual_specs.get('duration', 0)
            
            feedback.append(f"📊 Actual video specs: {actual_width}x{actual_height}, {actual_codec}, {actual_duration:.1f}s")
        
        # Check if report exists
        host_report = Path(temp_dir) / "report.txt"
        
        try:
            copy_from_env(report_path_container, str(host_report))
        except Exception as e:
            feedback.append(f"❌ Verification report not found at: {report_path_container}")
            cleanup_verification_environment(temp_dir)
            return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}
        
        if not host_report.exists() or host_report.stat().st_size < 50:
            feedback.append("❌ Verification report is missing or empty")
            cleanup_verification_environment(temp_dir)
            return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}
        
        # Criterion 1: Report exists (15 points)
        score += 15
        feedback.append(f"✅ Verification report created (+15 points)")
        
        # Read report content
        with open(host_report, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
        
        report_lower = report_content.lower()
        
        # Criterion 2: Resolution documented (25 points)
        resolution_patterns = [
            r'(\d{3,4})\s*[x×]\s*(\d{3,4})',  # 1920x1080 or 1920 x 1080
            r'resolution[:\s]+(\d{3,4})\s*[x×]\s*(\d{3,4})',
            r'width[:\s]+(\d{3,4}).*?height[:\s]+(\d{3,4})',
        ]
        
        resolution_found = False
        documented_width = 0
        documented_height = 0
        
        for pattern in resolution_patterns:
            match = re.search(pattern, report_content, re.IGNORECASE | re.DOTALL)
            if match:
                documented_width = int(match.group(1))
                documented_height = int(match.group(2))
                resolution_found = True
                break
        
        if resolution_found:
            score += 25
            feedback.append(f"✅ Resolution documented: {documented_width}x{documented_height} (+25 points)")
            
            # Check if it matches actual (within 10 pixels for tolerance)
            if 'error' not in actual_specs:
                if abs(documented_width - actual_width) <= 10 and abs(documented_height - actual_height) <= 10:
                    feedback.append(f"   ✓ Resolution matches actual video specs")
                else:
                    feedback.append(f"   ⚠️ Resolution mismatch: documented {documented_width}x{documented_height} vs actual {actual_width}x{actual_height}")
        else:
            feedback.append("❌ Resolution not documented (0/25 points)")
        
        # Criterion 3: Codec documented (20 points)
        codec_patterns = [
            r'codec[:\s]+([a-z0-9\.]+)',
            r'video codec[:\s]+([a-z0-9\.]+)',
            r'codec name[:\s]+([a-z0-9\.]+)',
        ]
        
        codec_found = False
        documented_codec = ""
        
        for pattern in codec_patterns:
            match = re.search(pattern, report_lower)
            if match:
                documented_codec = match.group(1).strip()
                codec_found = True
                break
        
        # Also check for common codec mentions
        if not codec_found:
            for codec_name in ['h264', 'h.264', 'avc', 'h265', 'hevc', 'vp9', 'vp8', 'mpeg4', 'mpeg-4']:
                if codec_name in report_lower:
                    documented_codec = codec_name
                    codec_found = True
                    break
        
        if codec_found:
            score += 20
            feedback.append(f"✅ Codec documented: {documented_codec} (+20 points)")
            
            if 'error' not in actual_specs:
                # Normalize codec names for comparison
                codec_normalized = documented_codec.replace('.', '').replace('-', '').replace('_', '')
                actual_normalized = actual_codec.replace('.', '').replace('-', '').replace('_', '')
                
                if codec_normalized in actual_normalized or actual_normalized in codec_normalized or \
                   ('h264' in codec_normalized and 'avc' in actual_normalized) or \
                   ('avc' in codec_normalized and 'h264' in actual_normalized):
                    feedback.append(f"   ✓ Codec matches actual video")
                else:
                    feedback.append(f"   ⚠️ Codec mismatch: documented '{documented_codec}' vs actual '{actual_codec}'")
        else:
            feedback.append("❌ Codec not documented (0/20 points)")
        
        # Criterion 4: Duration documented (20 points)
        duration_patterns = [
            r'duration[:\s]+(\d+):(\d+)',  # MM:SS or HH:MM:SS
            r'duration[:\s]+(\d+)\s*min',  # X minutes
            r'duration[:\s]+(\d+\.?\d*)\s*s',  # X seconds
            r'(\d+)\s*seconds?',
            r'length[:\s]+(\d+\.?\d*)',
        ]
        
        duration_found = False
        documented_duration = 0
        
        for pattern in duration_patterns:
            match = re.search(pattern, report_lower)
            if match:
                # Try to extract duration in seconds
                matched_text = match.group(0)
                if ':' in matched_text:
                    # Time format
                    parts = [p for p in re.findall(r'\d+', matched_text)]
                    if len(parts) == 2:  # MM:SS
                        documented_duration = int(parts[0]) * 60 + int(parts[1])
                    elif len(parts) == 3:  # HH:MM:SS
                        documented_duration = int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
                elif 'min' in matched_text:
                    documented_duration = int(match.group(1)) * 60
                elif 's' in matched_text or 'sec' in matched_text:
                    documented_duration = float(match.group(1))
                else:
                    # Just a number
                    documented_duration = float(match.group(1))
                
                duration_found = True
                break
        
        if duration_found and documented_duration > 0:
            score += 20
            feedback.append(f"✅ Duration documented: {documented_duration:.0f}s ({documented_duration/60:.1f} min) (+20 points)")
            
            if 'error' not in actual_specs and actual_duration > 0:
                # Check if within 10% tolerance or ±5 seconds
                tolerance = max(5, actual_duration * 0.1)
                if abs(documented_duration - actual_duration) <= tolerance:
                    feedback.append(f"   ✓ Duration matches actual video")
                else:
                    feedback.append(f"   ⚠️ Duration mismatch: documented {documented_duration:.0f}s vs actual {actual_duration:.0f}s")
        else:
            feedback.append("❌ Duration not documented (0/20 points)")
        
        # Criterion 5: Correct pass/fail determination (20 points)
        # Expected specs: 1920x1080, 60s, H.264
        # The setup script creates a video with DIFFERENT specs (1280x720, 30s)
        # So the correct determination should be "FAIL"
        
        has_pass = bool(re.search(r'\bpass\b', report_lower))
        has_fail = bool(re.search(r'\bfail\b', report_lower))
        
        # Determine what the CORRECT determination should be
        expected_resolution = (1920, 1080)
        expected_codec_variants = ['h264', 'avc', 'h.264']
        expected_duration = 60  # seconds
        
        specs_match = True
        mismatch_reasons = []
        
        if 'error' not in actual_specs:
            # Check resolution
            if actual_width != expected_resolution[0] or actual_height != expected_resolution[1]:
                specs_match = False
                mismatch_reasons.append(f"resolution ({actual_width}x{actual_height} ≠ 1920x1080)")
            
            # Check codec (H.264/AVC variants acceptable)
            codec_matches = any(variant in actual_codec for variant in expected_codec_variants)
            if not codec_matches:
                specs_match = False
                mismatch_reasons.append(f"codec ({actual_codec} ≠ H.264)")
            
            # Check duration (±5 seconds tolerance)
            if abs(actual_duration - expected_duration) > 5:
                specs_match = False
                mismatch_reasons.append(f"duration ({actual_duration:.0f}s ≠ 60s)")
        
        correct_determination = "PASS" if specs_match else "FAIL"
        
        if correct_determination == "FAIL":
            # Should have marked as FAIL
            if has_fail:
                score += 20
                feedback.append(f"✅ Correct determination: FAIL (specs don't match: {', '.join(mismatch_reasons)}) (+20 points)")
            elif has_pass:
                feedback.append(f"❌ Incorrect determination: marked PASS but should be FAIL (0/20 points)")
                feedback.append(f"   Reason: {', '.join(mismatch_reasons)}")
            else:
                feedback.append(f"⚠️ No clear PASS/FAIL determination found (0/20 points)")
                feedback.append(f"   Expected: FAIL because {', '.join(mismatch_reasons)}")
        else:
            # Should have marked as PASS (unlikely with our intentional mismatch)
            if has_pass and not has_fail:
                score += 20
                feedback.append(f"✅ Correct determination: PASS (all specs match) (+20 points)")
            elif has_fail:
                feedback.append(f"❌ Incorrect determination: marked FAIL but should be PASS (0/20 points)")
            else:
                feedback.append(f"⚠️ No clear PASS/FAIL determination found (0/20 points)")
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_environment(temp_dir)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        # Cleanup
        cleanup_verification_environment(temp_dir)
    
    normalized_score = score / max_score
    
    feedback.append(f"\n📊 **Final Score: {score:.1f}/{max_score} ({normalized_score*100:.1f}%)**")
    
    if normalized_score >= 0.70:
        feedback.append("✅ **TASK PASSED** - Media verification completed successfully")
    else:
        feedback.append("❌ **TASK FAILED** - Verification incomplete or incorrect")
    
    return {
        "passed": normalized_score >= 0.70,
        "score": int(normalized_score * 100),
        "feedback": "\n".join(feedback)
    }