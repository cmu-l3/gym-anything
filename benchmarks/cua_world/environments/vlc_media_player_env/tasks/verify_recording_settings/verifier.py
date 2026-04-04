#!/usr/bin/env python3
"""
Verifier for Verify Recording Settings task

Checks if the agent correctly verified video specifications and created an accurate report.
"""

import sys
import os
import logging
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected specifications (what the camera should have recorded)
EXPECTED_WIDTH = 3840
EXPECTED_HEIGHT = 2160
EXPECTED_FPS = 60.0
EXPECTED_CODEC = "h264"
EXPECTED_MIN_BITRATE_MBPS = 75  # Slight tolerance below target of 80


def parse_video_specs(specs_file: Path) -> Tuple[Dict[str, Any], str]:
    """Parse actual video specifications from ffprobe JSON."""
    try:
        with open(specs_file, 'r') as f:
            video_data = json.load(f)
        
        stream = video_data.get('streams', [{}])[0]
        actual_width = stream.get('width', 0)
        actual_height = stream.get('height', 0)
        actual_codec = stream.get('codec_name', '').lower()
        
        # Parse frame rate
        fps_str = stream.get('r_frame_rate', '0/1')
        if '/' in fps_str:
            num, den = map(int, fps_str.split('/'))
            actual_fps = num / den if den > 0 else 0
        else:
            actual_fps = float(fps_str)
        
        # Parse bitrate
        actual_bitrate = int(stream.get('bit_rate', 0))
        if actual_bitrate == 0:
            # Fallback to format bitrate
            actual_bitrate = int(video_data.get('format', {}).get('bit_rate', 0))
        actual_bitrate_mbps = actual_bitrate / 1_000_000
        
        specs = {
            'width': actual_width,
            'height': actual_height,
            'fps': actual_fps,
            'codec': actual_codec,
            'bitrate_mbps': actual_bitrate_mbps
        }
        
        logger.info(f"Parsed actual specs: {specs}")
        return specs, ""
    
    except Exception as e:
        logger.error(f"Failed to parse video specs: {e}", exc_info=True)
        return {}, f"Failed to parse video specs: {e}"


def check_specs_match(actual_specs: Dict[str, Any]) -> Dict[str, bool]:
    """Check which specifications match expectations."""
    matches = {
        'resolution': (
            actual_specs.get('width') == EXPECTED_WIDTH and 
            actual_specs.get('height') == EXPECTED_HEIGHT
        ),
        'fps': abs(actual_specs.get('fps', 0) - EXPECTED_FPS) < 1.0,
        'codec': actual_specs.get('codec', '').lower() in ['h264', 'avc1', 'avc'],
        'bitrate': actual_specs.get('bitrate_mbps', 0) >= EXPECTED_MIN_BITRATE_MBPS
    }
    logger.info(f"Spec matching results: {matches}")
    return matches


def verify_recording_settings(traj, env_info, task_info):
    """
    Verify the recording settings verification task.
    
    Args:
        traj: Agent trajectory (not used directly)
        env_info: Environment information including copy_from_env function
        task_info: Task information
        
    Returns:
        Dict with success status, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "❌ Copy function not available"
        }
    
    # Check if report exists
    report_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/recording_verification.txt", report_file.name)
    except Exception as e:
        logger.error(f"Failed to copy verification report: {e}")
        
        # Check if missing marker exists
        try:
            marker_file = tempfile.NamedTemporaryFile(delete=False, suffix='.marker')
            copy_from_env("/tmp/recording_verification_missing.marker", marker_file.name)
            os.unlink(marker_file.name)
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Verification report not found at Documents/recording_verification.txt"
            }
        except:
            pass
        
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Failed to access verification report: {str(e)}"
        }
    
    # Read report content
    try:
        with open(report_file.name, 'r') as f:
            report_content = f.read()
        logger.info(f"Report content ({len(report_content)} chars):\n{report_content}")
    except Exception as e:
        os.unlink(report_file.name)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Failed to read verification report: {e}"
        }
    
    os.unlink(report_file.name)
    
    # Check if report is not empty
    if len(report_content.strip()) < 50:
        return {
            "passed": False,
            "score": 0.1,
            "feedback": "❌ Report is too short or empty (minimum 50 characters expected)"
        }
    
    # Parse actual video specs for cross-checking
    specs_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/actual_video_specs.json", specs_file.name)
    except Exception as e:
        logger.error(f"Failed to copy video specs: {e}")
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Internal error: Could not verify video specifications"
        }
    
    actual_specs, error = parse_video_specs(Path(specs_file.name))
    os.unlink(specs_file.name)
    
    if error:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ {error}"
        }
    
    # Check which specs actually match
    spec_matches = check_specs_match(actual_specs)
    all_specs_match = all(spec_matches.values())
    
    # Analyze report content
    report_lower = report_content.lower()
    
    # Check if each specification is mentioned in report
    mentioned = {
        'resolution': any(term in report_content for term in [
            "3840x2160", "3840 x 2160", "3840", "2160", "resolution"
        ]),
        'fps': any(term in report_lower for term in [
            "fps", "60", "frame", "framerate", "frame rate"
        ]),
        'codec': any(term in report_lower for term in [
            "h.264", "h264", "codec", "avc"
        ]),
        'bitrate': any(term in report_lower for term in [
            "bitrate", "bit rate", "mbps", "80"
        ])
    }
    
    # Check for check marks or status indicators
    has_status_indicators = any(mark in report_content for mark in [
        '✓', '✗', '✔', '✘', 'PASS', 'FAIL', 'pass', 'fail', 'OK', 'ERROR', 
        'Yes', 'No', 'Match', 'Mismatch', '[X]', '[ ]', 'True', 'False'
    ])
    
    # Check for overall verdict
    has_verdict = bool(re.search(
        r'(overall|verdict|result|conclusion|summary|status).*?(pass|fail|ok|error|success|correct|incorrect)',
        report_lower,
        re.MULTILINE | re.DOTALL
    ))
    
    # Determine if verdict is correct based on actual specs
    # Look for PASS/FAIL in relation to verdict keywords
    verdict_pass_pattern = re.search(
        r'(verdict|overall|result|conclusion|summary).*?(pass|ok|success|correct|match)',
        report_lower,
        re.MULTILINE | re.DOTALL
    )
    verdict_fail_pattern = re.search(
        r'(verdict|overall|result|conclusion|summary).*?(fail|error|incorrect|mismatch)',
        report_lower,
        re.MULTILINE | re.DOTALL
    )
    
    verdict_pass_stated = bool(verdict_pass_pattern)
    verdict_fail_stated = bool(verdict_fail_pattern)
    
    # Verdict is correct if it matches the actual spec matching status
    correct_verdict = (
        (all_specs_match and verdict_pass_stated and not verdict_fail_stated) or
        (not all_specs_match and verdict_fail_stated and not verdict_pass_stated)
    )
    
    # Scoring logic
    score = 0.0
    feedback_parts = []
    
    # 1. Report exists and has content (0.1 points - already have this)
    score += 0.1
    feedback_parts.append("✓ Report file created")
    
    # 2. Specifications are mentioned (0.4 points total, 0.1 per spec)
    specs_mentioned_count = sum(mentioned.values())
    spec_mention_score = (specs_mentioned_count / 4) * 0.4
    score += spec_mention_score
    
    if specs_mentioned_count == 4:
        feedback_parts.append("✓ All 4 specifications mentioned")
    elif specs_mentioned_count >= 2:
        missing = [k for k, v in mentioned.items() if not v]
        feedback_parts.append(f"⚠ Partial specs ({specs_mentioned_count}/4): missing {', '.join(missing)}")
    else:
        missing = [k for k, v in mentioned.items() if not v]
        feedback_parts.append(f"✗ Few specs mentioned ({specs_mentioned_count}/4): missing {', '.join(missing)}")
    
    # 3. Has status indicators (0.15 points)
    if has_status_indicators:
        score += 0.15
        feedback_parts.append("✓ Status indicators present")
    else:
        feedback_parts.append("⚠ No clear status indicators (✓/✗/PASS/FAIL)")
    
    # 4. Has overall verdict (0.15 points)
    if has_verdict:
        score += 0.15
        feedback_parts.append("✓ Overall verdict provided")
    else:
        feedback_parts.append("⚠ Missing overall verdict statement")
    
    # 5. Verdict is correct (0.2 points) - most important criterion
    if correct_verdict:
        score += 0.2
        feedback_parts.append("✓ Verdict is CORRECT")
    else:
        if all_specs_match and not verdict_pass_stated:
            feedback_parts.append("✗ Video matches specs but verdict doesn't say PASS")
        elif not all_specs_match and not verdict_fail_stated:
            feedback_parts.append("✗ Video has spec mismatches but verdict doesn't say FAIL")
        elif not has_verdict:
            feedback_parts.append("✗ No clear verdict found in report")
        else:
            feedback_parts.append("✗ Verdict appears incorrect or ambiguous")
    
    # Compile final feedback
    feedback = "\n".join(feedback_parts)
    
    # Add actual video specs for transparency
    feedback += f"\n\n📊 Actual video specifications:"
    feedback += f"\n  • Resolution: {actual_specs['width']}x{actual_specs['height']}"
    feedback += f"\n  • Frame Rate: {actual_specs['fps']:.1f} fps"
    feedback += f"\n  • Codec: {actual_specs['codec'].upper()}"
    feedback += f"\n  • Bitrate: {actual_specs['bitrate_mbps']:.1f} Mbps"
    
    feedback += f"\n\n🎯 Specification matching status:"
    for spec_name, matches_expected in spec_matches.items():
        status = "✓" if matches_expected else "✗"
        feedback += f"\n  {status} {spec_name.replace('_', ' ').capitalize()}"
    
    feedback += f"\n  → All specs match: {'Yes' if all_specs_match else 'No'}"
    
    feedback += f"\n\n📈 Report Quality Score: {score:.2f}/1.00"
    
    # Success threshold: 0.7 (need most components correct)
    passed = score >= 0.7
    
    # Convert to percentage for cleaner display
    score_percent = int(score * 100)
    
    return {
        "passed": passed,
        "score": score_percent,
        "feedback": feedback
    }