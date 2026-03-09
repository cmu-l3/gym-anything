#!/usr/bin/env python3
"""
Verifier for Examine Video Metadata task
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_codec_name(codec_str):
    """
    Normalize codec name for comparison.
    Handles variations like: H264, h264, H.264, AVC, MPEG-4 AVC, etc.
    """
    if not codec_str:
        return ""
    
    codec_lower = codec_str.lower().strip()
    
    # H264 variations
    if any(x in codec_lower for x in ['h264', 'h.264', 'avc', 'x264']):
        return 'h264'
    
    # H265 variations
    if any(x in codec_lower for x in ['h265', 'h.265', 'hevc', 'x265']):
        return 'h265'
    
    # VP8/VP9
    if 'vp8' in codec_lower:
        return 'vp8'
    if 'vp9' in codec_lower:
        return 'vp9'
    
    # MPEG variations
    if 'mpeg' in codec_lower or 'mp4v' in codec_lower:
        return 'mpeg4'
    
    return codec_lower


def extract_codec_from_text(text):
    """
    Extract video codec from report text.
    Looks for patterns like:
    - "Video Codec: H264"
    - "Codec: H.264"
    - "Video format: MPEG-4 AVC"
    """
    patterns = [
        r'(?:video\s+)?codec\s*[:=]\s*([a-zA-Z0-9.-]+)',
        r'video\s+format\s*[:=]\s*([a-zA-Z0-9.\s-]+)',
        r'codec\s+name\s*[:=]\s*([a-zA-Z0-9.-]+)',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return match.group(1).strip()
    
    return None


def extract_resolution_from_text(text):
    """
    Extract resolution from report text.
    Looks for patterns like:
    - "Resolution: 1920x1080"
    - "1920 × 1080"
    - "Width: 1920, Height: 1080"
    - "Video size: 1920x1080"
    """
    # Pattern 1: WIDTHxHEIGHT or WIDTH×HEIGHT
    pattern1 = r'(\d{3,4})\s*[x×]\s*(\d{3,4})'
    match = re.search(pattern1, text, re.IGNORECASE)
    if match:
        return int(match.group(1)), int(match.group(2))
    
    # Pattern 2: Width: W, Height: H
    pattern2 = r'width\s*[:=]\s*(\d{3,4}).*?height\s*[:=]\s*(\d{3,4})'
    match = re.search(pattern2, text, re.IGNORECASE | re.DOTALL)
    if match:
        return int(match.group(1)), int(match.group(2))
    
    return None, None


def extract_fps_from_text(text):
    """
    Extract frame rate from report text.
    Looks for patterns like:
    - "Frame Rate: 30 fps"
    - "30.00 fps"
    - "FPS: 30"
    """
    patterns = [
        r'(?:frame\s+rate|fps)\s*[:=]\s*([\d.]+)',
        r'([\d.]+)\s*fps',
        r'([\d.]+)\s*frames?\s*per\s*second',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return float(match.group(1))
    
    return None


def extract_bitrate_from_text(text):
    """
    Extract bitrate from report text.
    Looks for patterns like:
    - "Bitrate: 5000 kb/s"
    - "5000 kbps"
    - "Bit rate: 5 Mb/s"
    """
    patterns = [
        r'(?:bit\s*rate|bitrate)\s*[:=]\s*([\d.]+)\s*([km]?b)',
        r'([\d.]+)\s*([km]?b)(?:ps|/s)',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            value = float(match.group(1))
            unit = match.group(2).lower()
            
            # Convert to kb/s
            if 'mb' in unit or unit == 'm':
                value *= 1000
            elif 'b' in unit and 'k' not in unit:
                value /= 1000
            
            return value
    
    return None


def extract_creation_date_from_text(text):
    """
    Extract creation date from report text.
    Looks for ISO date patterns: YYYY-MM-DD
    """
    pattern = r'(\d{4})-(\d{2})-(\d{2})'
    match = re.search(pattern, text)
    if match:
        return f"{match.group(1)}-{match.group(2)}-{match.group(3)}"
    
    return None


def verify_examine_metadata(traj, env_info, task_info):
    """
    Verify examine video metadata task completion.
    
    Checks:
    1. Report file exists and is non-empty
    2. Codec identified correctly
    3. Resolution documented correctly (±10px tolerance)
    4. Frame rate documented correctly (±2fps tolerance)
    5. At least 4/5 fields correctly extracted
    
    Scoring:
    - Each criterion worth 1 point
    - Total: 5 points
    - Pass threshold: 4/5 (80%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    feedback_parts = []
    criteria_met = 0
    total_criteria = 5
    
    # Copy metadata report from container
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_metadata_report.txt", temp_report.name)
    except Exception as e:
        logger.error(f"Error copying metadata report: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Metadata report not found: {str(e)}"}
    
    # Read report content
    try:
        with open(temp_report.name, 'r') as f:
            report_text = f.read()
    except Exception as e:
        os.unlink(temp_report.name)
        return {"passed": False, "score": 0, "feedback": f"Error reading report: {str(e)}"}
    
    # Criterion 1: Report exists and is non-empty
    if len(report_text.strip()) < 50:
        os.unlink(temp_report.name)
        return {"passed": False, "score": 0, "feedback": "Report is empty or too short (min 50 chars required)"}
    
    feedback_parts.append(f"✅ Report exists ({len(report_text)} chars)")
    
    # Copy ground truth from container
    temp_ground_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/metadata_ground_truth.json", temp_ground_truth.name)
        
        with open(temp_ground_truth.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        logger.error(f"Error loading ground truth: {e}", exc_info=True)
        os.unlink(temp_report.name)
        return {"passed": False, "score": 0, "feedback": f"Ground truth not available: {str(e)}"}
    
    # Extract expected values from ground truth
    expected_codec = normalize_codec_name(ground_truth.get('codec', 'h264'))
    expected_width = ground_truth.get('width', 1920)
    expected_height = ground_truth.get('height', 1080)
    expected_fps = float(ground_truth.get('fps', 30))
    expected_bitrate = float(ground_truth.get('bitrate_kbps', 5000))
    
    logger.info(f"Expected values - Codec: {expected_codec}, Resolution: {expected_width}x{expected_height}, "
                f"FPS: {expected_fps}, Bitrate: {expected_bitrate} kb/s")
    
    # Criterion 2: Codec identified correctly
    extracted_codec_raw = extract_codec_from_text(report_text)
    if extracted_codec_raw:
        extracted_codec = normalize_codec_name(extracted_codec_raw)
        
        if extracted_codec == expected_codec:
            criteria_met += 1
            feedback_parts.append(f"✅ Codec correct: {extracted_codec_raw}")
        else:
            feedback_parts.append(f"❌ Codec mismatch: extracted '{extracted_codec_raw}' (normalized: {extracted_codec}), expected '{expected_codec}'")
    else:
        feedback_parts.append("❌ Codec not found in report")
    
    # Criterion 3: Resolution documented correctly
    extracted_width, extracted_height = extract_resolution_from_text(report_text)
    if extracted_width and extracted_height:
        width_diff = abs(extracted_width - expected_width)
        height_diff = abs(extracted_height - expected_height)
        
        if width_diff <= 10 and height_diff <= 10:
            criteria_met += 1
            feedback_parts.append(f"✅ Resolution correct: {extracted_width}x{extracted_height}")
        else:
            feedback_parts.append(f"❌ Resolution mismatch: {extracted_width}x{extracted_height} "
                                f"(expected {expected_width}x{expected_height}, tolerance ±10px)")
    else:
        feedback_parts.append("❌ Resolution not found in report")
    
    # Criterion 4: Frame rate documented correctly
    extracted_fps = extract_fps_from_text(report_text)
    if extracted_fps:
        fps_diff = abs(extracted_fps - expected_fps)
        
        if fps_diff <= 2.0:
            criteria_met += 1
            feedback_parts.append(f"✅ FPS correct: {extracted_fps} fps")
        else:
            feedback_parts.append(f"❌ FPS mismatch: {extracted_fps} fps "
                                f"(expected {expected_fps}, tolerance ±2fps)")
    else:
        feedback_parts.append("❌ Frame rate not found in report")
    
    # Criterion 5: Bitrate documented (with ±20% tolerance)
    extracted_bitrate = extract_bitrate_from_text(report_text)
    if extracted_bitrate:
        bitrate_diff_pct = abs(extracted_bitrate - expected_bitrate) / expected_bitrate * 100
        
        if bitrate_diff_pct <= 20:
            criteria_met += 1
            feedback_parts.append(f"✅ Bitrate correct: {extracted_bitrate:.0f} kb/s")
        else:
            feedback_parts.append(f"⚠️ Bitrate extracted ({extracted_bitrate:.0f} kb/s) differs from expected "
                                f"({expected_bitrate:.0f} kb/s) by {bitrate_diff_pct:.1f}% (tolerance 20%)")
    else:
        feedback_parts.append("⚠️ Bitrate not found in report (optional field)")
    
    # Bonus: Check for creation date (optional, doesn't affect pass/fail)
    extracted_date = extract_creation_date_from_text(report_text)
    if extracted_date:
        feedback_parts.append(f"ℹ️ Creation date found: {extracted_date}")
    
    # Cleanup temp files
    os.unlink(temp_report.name)
    os.unlink(temp_ground_truth.name)
    
    # Calculate score
    # We have 5 criteria:
    # 1. Codec (1 point)
    # 2. Resolution (1 point)
    # 3. FPS (1 point)
    # 4. Bitrate (1 point)
    # Plus the implicit criterion that report exists (already checked above)
    
    # Adjust scoring: 4 main fields (codec, resolution, fps, bitrate) each worth 20%
    # Plus report existence worth 20%
    score = int((criteria_met / 4) * 80) + 20  # 20% for report existence, 80% for fields
    
    passed = score >= 80  # Pass threshold: 80% (need 4/5 fields correct)
    
    feedback = " | ".join(feedback_parts)
    
    # Check completion marker (doesn't affect score, just informational)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_metadata_completed.txt", temp_marker.name)
        logger.info("Completion marker found")
        os.unlink(temp_marker.name)
    except Exception:
        logger.warning("Completion marker not found")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria_met": criteria_met,
        "total_criteria": 4  # 4 extractable fields
    }