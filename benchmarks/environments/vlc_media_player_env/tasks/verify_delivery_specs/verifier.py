#!/usr/bin/env python3
"""
Verifier for Verify Delivery Specs task

Checks if agent correctly analyzed video specifications and created accurate report.
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


def normalize_codec_name(codec):
    """Normalize codec names for comparison (H.264, h264, AVC, etc.)"""
    if not codec:
        return ""
    codec_lower = codec.lower()
    # H.264 variants
    if any(x in codec_lower for x in ['h264', 'h.264', 'avc', 'x264']):
        return "h264"
    # H.265 variants
    if any(x in codec_lower for x in ['h265', 'h.265', 'hevc', 'x265']):
        return "h265"
    return codec_lower


def parse_verdict(text, keyword):
    """
    Parse PASS/FAIL verdict from report text for a given keyword.
    Returns: 'pass', 'fail', or None if not found
    """
    if not text:
        return None
    
    text_lower = text.lower()
    
    # Look for patterns like:
    # "Resolution: [PASS]" or "Resolution: PASS" or "Resolution [PASS]"
    # "Resolution: [FAIL]" or "Resolution: FAIL"
    
    patterns = [
        rf'{keyword.lower()}:?\s*\[?(pass|fail)\]?',
        rf'{keyword.lower()}.*?(pass|fail)',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, text_lower)
        if match:
            return match.group(1).lower()
    
    return None


def extract_overall_verdict(text):
    """Extract overall PASS/FAIL verdict"""
    if not text:
        return None
    
    text_lower = text.lower()
    
    # Look for "OVERALL: PASS" or "OVERALL: FAIL"
    match = re.search(r'overall:?\s*\[?(pass|fail)\]?', text_lower)
    if match:
        return match.group(1).lower()
    
    return None


def extract_recommendation(text):
    """Extract recommendation (ACCEPT or REQUEST REVISION)"""
    if not text:
        return None
    
    text_lower = text.lower()
    
    if re.search(r'accept\s+delivery', text_lower):
        return "accept"
    if re.search(r'request\s+revision', text_lower):
        return "revision"
    
    return None


def verify_delivery_specs(traj, env_info, task_info):
    """
    Verify the delivery specs verification task.
    
    Checks:
    1. Report file exists and is parseable
    2. Each parameter is correctly evaluated (resolution, codec, bitrate, format, duration)
    3. Overall verdict is correct (PASS only if ALL specs met)
    4. Recommendation matches verdict
    
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
    
    feedback_parts = []
    score_components = {
        'report_exists': 0,      # 20 points
        'resolution': 0,          # 15 points
        'codec': 0,               # 15 points
        'bitrate': 0,             # 15 points
        'format': 0,              # 15 points
        'duration': 0,            # 10 points
        'overall_verdict': 0,     # 5 points
        'recommendation': 0,      # 5 points
    }
    
    # Copy and read the agent's verification report
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_verification_report.txt", temp_report.name)
        
        with open(temp_report.name, 'r') as f:
            report_content = f.read()
        
        logger.info(f"Agent's report:\n{report_content}")
        
        if not report_content or len(report_content) < 50:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Verification report not found or too short"
            }
        
        score_components['report_exists'] = 20
        feedback_parts.append("✅ Report exists")
        
    except Exception as e:
        logger.error(f"Error reading report: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading verification report: {str(e)}"
        }
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    # Read ground truth
    temp_ground_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
    temp_expected = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_ground_truth.json", temp_ground_truth.name)
        copy_from_env("/tmp/vlc_expected_verdict.txt", temp_expected.name)
        
        with open(temp_ground_truth.name, 'r') as f:
            ground_truth = json.load(f)
        
        with open(temp_expected.name, 'r') as f:
            expected_verdict = f.read().strip().lower()
        
    except Exception as e:
        logger.error(f"Error reading ground truth: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 20,  # At least report exists
            "feedback": f"Error reading ground truth: {str(e)}"
        }
    finally:
        if os.path.exists(temp_ground_truth.name):
            os.unlink(temp_ground_truth.name)
        if os.path.exists(temp_expected.name):
            os.unlink(temp_expected.name)
    
    # Extract actual properties from ground truth
    stream = ground_truth.get("streams", [{}])[0]
    format_info = ground_truth.get("format", {})
    
    actual_width = stream.get("width", 0)
    actual_height = stream.get("height", 0)
    actual_codec = normalize_codec_name(stream.get("codec_name", ""))
    actual_bitrate_bps = int(stream.get("bit_rate", 0))
    actual_bitrate_mbps = actual_bitrate_bps / 1_000_000
    actual_duration = float(format_info.get("duration", 0))
    actual_format = format_info.get("format_name", "")
    
    logger.info(f"Actual properties: {actual_width}x{actual_height}, {actual_codec}, "
                f"{actual_bitrate_mbps:.2f} Mbps, {actual_format}, {actual_duration:.1f}s")
    
    # Expected specs
    expected_width = 1920
    expected_height = 1080
    expected_codec = "h264"
    expected_bitrate_min = 4.5
    expected_bitrate_max = 5.5
    expected_min_duration = 30
    expected_format_contains = "mp4"
    
    # Determine what SHOULD be the correct evaluation for each parameter
    resolution_should_pass = (actual_width == expected_width and actual_height == expected_height)
    codec_should_pass = (actual_codec == expected_codec)
    bitrate_should_pass = (expected_bitrate_min <= actual_bitrate_mbps <= expected_bitrate_max)
    format_should_pass = (expected_format_contains in actual_format.lower())
    duration_should_pass = (actual_duration >= expected_min_duration)
    
    overall_should_pass = all([
        resolution_should_pass,
        codec_should_pass,
        bitrate_should_pass,
        format_should_pass,
        duration_should_pass
    ])
    
    logger.info(f"Expected evaluations - Res:{resolution_should_pass}, Codec:{codec_should_pass}, "
                f"Bitrate:{bitrate_should_pass}, Format:{format_should_pass}, Duration:{duration_should_pass}")
    logger.info(f"Overall should pass: {overall_should_pass}")
    
    # Parse agent's report
    agent_resolution = parse_verdict(report_content, "resolution")
    agent_codec = parse_verdict(report_content, "codec")
    agent_bitrate = parse_verdict(report_content, "bitrate")
    agent_format = parse_verdict(report_content, "format")
    agent_duration = parse_verdict(report_content, "duration")
    agent_overall = extract_overall_verdict(report_content)
    agent_recommendation = extract_recommendation(report_content)
    
    logger.info(f"Agent's verdicts - Res:{agent_resolution}, Codec:{agent_codec}, "
                f"Bitrate:{agent_bitrate}, Format:{agent_format}, Duration:{agent_duration}")
    logger.info(f"Agent overall: {agent_overall}, Recommendation: {agent_recommendation}")
    
    # Check each parameter
    # Resolution
    if agent_resolution:
        if (resolution_should_pass and agent_resolution == "pass") or \
           (not resolution_should_pass and agent_resolution == "fail"):
            score_components['resolution'] = 15
            feedback_parts.append("✅ Resolution check correct")
        else:
            feedback_parts.append(f"❌ Resolution check wrong (should be {'PASS' if resolution_should_pass else 'FAIL'})")
    else:
        feedback_parts.append("⚠️ Resolution verdict not found in report")
    
    # Codec
    if agent_codec:
        if (codec_should_pass and agent_codec == "pass") or \
           (not codec_should_pass and agent_codec == "fail"):
            score_components['codec'] = 15
            feedback_parts.append("✅ Codec check correct")
        else:
            feedback_parts.append(f"❌ Codec check wrong (should be {'PASS' if codec_should_pass else 'FAIL'})")
    else:
        feedback_parts.append("⚠️ Codec verdict not found in report")
    
    # Bitrate
    if agent_bitrate:
        if (bitrate_should_pass and agent_bitrate == "pass") or \
           (not bitrate_should_pass and agent_bitrate == "fail"):
            score_components['bitrate'] = 15
            feedback_parts.append("✅ Bitrate check correct")
        else:
            feedback_parts.append(f"❌ Bitrate check wrong (should be {'PASS' if bitrate_should_pass else 'FAIL'})")
    else:
        feedback_parts.append("⚠️ Bitrate verdict not found in report")
    
    # Format
    if agent_format:
        if (format_should_pass and agent_format == "pass") or \
           (not format_should_pass and agent_format == "fail"):
            score_components['format'] = 15
            feedback_parts.append("✅ Format check correct")
        else:
            feedback_parts.append(f"❌ Format check wrong (should be {'PASS' if format_should_pass else 'FAIL'})")
    else:
        feedback_parts.append("⚠️ Format verdict not found in report")
    
    # Duration
    if agent_duration:
        if (duration_should_pass and agent_duration == "pass") or \
           (not duration_should_pass and agent_duration == "fail"):
            score_components['duration'] = 10
            feedback_parts.append("✅ Duration check correct")
        else:
            feedback_parts.append(f"❌ Duration check wrong (should be {'PASS' if duration_should_pass else 'FAIL'})")
    else:
        feedback_parts.append("⚠️ Duration verdict not found in report")
    
    # Overall verdict
    if agent_overall:
        if (overall_should_pass and agent_overall == "pass") or \
           (not overall_should_pass and agent_overall == "fail"):
            score_components['overall_verdict'] = 5
            feedback_parts.append("✅ Overall verdict correct")
        else:
            feedback_parts.append(f"❌ Overall verdict wrong (should be {'PASS' if overall_should_pass else 'FAIL'})")
    else:
        feedback_parts.append("⚠️ Overall verdict not found in report")
    
    # Recommendation
    if agent_recommendation:
        if (overall_should_pass and agent_recommendation == "accept") or \
           (not overall_should_pass and agent_recommendation == "revision"):
            score_components['recommendation'] = 5
            feedback_parts.append("✅ Recommendation correct")
        else:
            feedback_parts.append(f"❌ Recommendation wrong")
    else:
        feedback_parts.append("⚠️ Recommendation not found in report")
    
    # Calculate total score
    total_score = sum(score_components.values())
    passed = total_score >= 70
    
    # Add summary
    feedback_parts.insert(0, f"Score: {total_score}/100")
    feedback_parts.append(f"Actual: {actual_width}x{actual_height}, {actual_codec.upper()}, "
                         f"{actual_bitrate_mbps:.1f}Mbps, {actual_duration:.0f}s")
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Final score: {total_score}, Passed: {passed}")
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback
    }