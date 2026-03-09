#!/usr/bin/env python3
"""
Verifier for verify_recording_framerate@1

Checks if agent successfully analyzed the gameplay recording's frame rate
consistency using VLC's diagnostic tools.
"""

import json
import logging
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple

# Use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_framerate_string(fps_str: str) -> float:
    """Convert frame rate string like '60/1' or '60.0' to float"""
    try:
        if '/' in fps_str:
            num, den = fps_str.split('/')
            return float(num) / float(den)
        return float(fps_str)
    except (ValueError, ZeroDivisionError):
        return 0.0


def find_analysis_files(output_dir: Path) -> List[Path]:
    """Find potential analysis files created by agent"""
    
    candidates = []
    
    # Look for common analysis filenames
    priority_names = [
        'recording_analysis.txt',
        'framerate_analysis.txt',
        'frame_report.txt',
        'codec_info.txt',
        'media_info.txt',
        'analysis.txt',
        'vlc-log.txt',
        'vlc_messages.log'
    ]
    
    for name in priority_names:
        filepath = output_dir / name
        if filepath.exists() and filepath.stat().st_size > 0:
            candidates.append(filepath)
    
    # Also check for any .txt or .log files
    for ext in ['*.txt', '*.log']:
        for filepath in output_dir.glob(ext):
            if filepath.stat().st_size > 0 and filepath not in candidates:
                candidates.append(filepath)
    
    return candidates


def analyze_content_for_framerate_info(filepath: Path) -> Tuple[bool, str, Dict]:
    """
    Parse analysis file to extract frame rate information.
    
    Returns:
        Tuple of (success, feedback_message, findings_dict)
    """
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        logger.info(f"Analyzing content from {filepath.name} ({len(content)} bytes)")
        
        if len(content) < 10:
            return False, "Analysis file is too short (< 10 bytes)", {}
        
        findings = {
            'has_framerate_mention': False,
            'mentions_60fps': False,
            'has_codec_info': False,
            'mentions_frame_drops': False,
            'mentions_cfr_or_vfr': False,
            'has_stream_info': False,
            'has_resolution': False,
            'fps_values_found': []
        }
        
        content_lower = content.lower()
        
        # Pattern 1: Look for explicit FPS mentions
        fps_patterns = [
            r'(\d+\.?\d*)\s*fps',
            r'frame\s*rate[:\s]+(\d+\.?\d*)',
            r'r_frame_rate[:\s]+(\d+/\d+)',
            r'(\d+/\d+)\s*fps',
            r'framerate[:\s]+(\d+\.?\d*)',
            r'(\d+)\s*frames?\s*per\s*second'
        ]
        
        for pattern in fps_patterns:
            matches = re.findall(pattern, content_lower, re.IGNORECASE)
            if matches:
                findings['has_framerate_mention'] = True
                findings['fps_values_found'].extend(matches)
                logger.info(f"✓ Found frame rate data: {matches}")
        
        # Check if any FPS value is around 60
        for match in findings['fps_values_found']:
            try:
                match_str = str(match)
                if '/' in match_str:
                    fps_val = parse_framerate_string(match_str)
                else:
                    fps_val = float(match_str)
                
                # Accept 59-61 FPS (allow slight tolerance for 59.94, etc.)
                if 59.0 <= fps_val <= 61.0:
                    findings['mentions_60fps'] = True
                    logger.info(f"✓ Found expected 60 FPS value: {fps_val}")
                    break
            except (ValueError, TypeError):
                continue
        
        # Pattern 2: Look for codec information
        codec_keywords = [
            'codec', 'h264', 'h.264', 'x264', 'avc1', 'avc', 
            'yuv420p', 'yuv', 'encoding', 'decoder'
        ]
        if any(kw in content_lower for kw in codec_keywords):
            findings['has_codec_info'] = True
            logger.info("✓ Contains codec information")
        
        # Pattern 3: Look for stream information
        stream_keywords = [
            'stream', 'video track', 'stream #', 'stream 0',
            'input #', 'video:', 'duration:'
        ]
        if any(kw in content_lower for kw in stream_keywords):
            findings['has_stream_info'] = True
            logger.info("✓ Contains stream information")
        
        # Pattern 4: Look for resolution
        resolution_patterns = [
            r'1920\s*x\s*1080',
            r'1920x1080',
            r'resolution[:\s]+1920',
            r'width[:\s]+1920',
            r'height[:\s]+1080'
        ]
        for pattern in resolution_patterns:
            if re.search(pattern, content_lower):
                findings['has_resolution'] = True
                logger.info("✓ Contains resolution information")
                break
        
        # Pattern 5: Look for CFR/VFR analysis
        cfr_vfr_keywords = [
            'constant frame rate', 'variable frame rate',
            'cfr', 'vfr', 'constant fps', 'variable fps'
        ]
        if any(kw in content_lower for kw in cfr_vfr_keywords):
            findings['mentions_cfr_or_vfr'] = True
            logger.info("✓ Contains CFR/VFR analysis")
        
        # Pattern 6: Look for frame drop mentions
        frame_drop_keywords = [
            'frame drop', 'dropped frame', 'late picture', 
            'lost frame', 'skip', 'display date', 'missing frame'
        ]
        if any(kw in content_lower for kw in frame_drop_keywords):
            findings['mentions_frame_drops'] = True
            logger.info("✓ Contains frame drop analysis")
        
        # Calculate score based on findings
        score = sum([
            findings['has_framerate_mention'] * 3,  # Most important - 3 points
            findings['mentions_60fps'] * 2,         # Correct value - 2 points
            findings['has_codec_info'] * 1,         # Supporting info - 1 point
            findings['has_stream_info'] * 1,        # Supporting info - 1 point
            findings['has_resolution'] * 1,         # Supporting info - 1 point
            findings['mentions_cfr_or_vfr'] * 2,    # Advanced analysis - 2 points
            findings['mentions_frame_drops'] * 1     # Advanced analysis - 1 point
        ])
        
        # Need at least 4 points: frame rate mention + something else
        min_score = 4
        
        if score >= min_score:
            return True, f"Analysis contains sufficient frame rate diagnostic information (score: {score}/11)", findings
        else:
            return False, f"Analysis lacks sufficient frame rate information (score: {score}/11, need {min_score})", findings
    
    except Exception as e:
        logger.error(f"Error analyzing file content: {e}", exc_info=True)
        return False, f"Error reading analysis file: {str(e)}", {}


def verify_ground_truth_recording(output_dir: Path) -> Tuple[bool, str, Dict]:
    """Verify the recording file itself has expected properties"""
    
    recording_path = output_dir / "gameplay_recording.mp4"
    
    if not recording_path.exists():
        return False, "Recording file not found in output", {}
    
    # Get video info using our utility
    video_info = get_video_info(str(recording_path))
    
    if 'error' in video_info:
        return False, f"Cannot analyze recording: {video_info['error']}", {}
    
    logger.info(f"Recording properties: {video_info}")
    
    # Load ground truth
    ground_truth_path = output_dir / "recording_ground_truth.json"
    if ground_truth_path.exists():
        with open(ground_truth_path, 'r') as f:
            ground_truth = json.load(f)
        
        expected_fps = parse_framerate_string(ground_truth.get('expected_fps', '60/1'))
        actual_fps = video_info.get('fps', 0)
        
        if abs(actual_fps - expected_fps) > 2.0:
            logger.warning(f"Frame rate mismatch: expected {expected_fps}, got {actual_fps}")
            return True, f"Recording verified with unexpected FPS: {actual_fps:.1f}", video_info
    
    return True, f"Recording verified: {video_info.get('fps', 0):.1f} FPS, {video_info.get('duration', 0):.1f}s", video_info


def verify_recording_framerate(traj, env_info, task_info):
    """
    Main verification function for verify_recording_framerate@1
    
    Args:
        traj: Trajectory data (unused for this task)
        env_info: Environment info containing copy_from_env function
        task_info: Task information (unused for this task)
    
    Returns:
        Dict with keys:
            - passed (bool): True if task completed successfully
            - score (int): 0 to 100
            - feedback (str): Human-readable feedback
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Get task output directory from env_info
    task_output_dir = env_info.get('task_output_dir', '/tmp/task_output')
    output_dir = Path(task_output_dir)
    
    logger.info(f"Verifying verify_recording_framerate task in {output_dir}")
    
    if not output_dir.exists():
        return {
            "passed": False,
            "score": 0,
            "feedback": "Task output directory not found"
        }
    
    feedback_parts = []
    checks = {
        'analysis_file_exists': False,
        'contains_framerate_info': False,
        'mentions_correct_fps': False,
        'has_diagnostic_data': False,
        'recording_verified': False
    }
    
    # Check 1: Find analysis files
    analysis_files = find_analysis_files(output_dir)
    
    if not analysis_files:
        feedback_parts.append("❌ No analysis file found")
        feedback_parts.append("Expected: Save VLC's codec information or frame statistics to a text file")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
    
    checks['analysis_file_exists'] = True
    feedback_parts.append(f"✓ Analysis file found: {analysis_files[0].name}")
    logger.info(f"Found {len(analysis_files)} analysis file(s)")
    
    # Check 2: Analyze content of each file until we find good info
    best_score = 0
    best_findings = {}
    best_message = ""
    
    for analysis_file in analysis_files:
        has_info, msg, findings = analyze_content_for_framerate_info(analysis_file)
        
        current_score = sum([
            findings.get('has_framerate_mention', False) * 3,
            findings.get('mentions_60fps', False) * 2,
            findings.get('has_codec_info', False) * 1,
            findings.get('has_stream_info', False) * 1,
            findings.get('has_resolution', False) * 1,
            findings.get('mentions_cfr_or_vfr', False) * 2,
            findings.get('mentions_frame_drops', False) * 1
        ])
        
        if current_score > best_score:
            best_score = current_score
            best_findings = findings
            best_message = msg
        
        if has_info:
            break
    
    checks['contains_framerate_info'] = best_findings.get('has_framerate_mention', False)
    checks['mentions_correct_fps'] = best_findings.get('mentions_60fps', False)
    checks['has_diagnostic_data'] = (
        best_findings.get('has_codec_info', False) or 
        best_findings.get('has_stream_info', False) or
        best_findings.get('has_resolution', False)
    )
    
    if best_score >= 4:
        feedback_parts.append(f"✓ {best_message}")
    else:
        feedback_parts.append(f"⚠️ {best_message}")
        feedback_parts.append("Analysis should contain frame rate data from VLC's diagnostic tools")
    
    # Check 3: Verify recording properties (ground truth check)
    verified, rec_msg, rec_info = verify_ground_truth_recording(output_dir)
    checks['recording_verified'] = verified
    
    if verified:
        feedback_parts.append(f"✓ {rec_msg}")
    
    # Calculate final score
    # Weighted scoring:
    # - Analysis file exists: 15%
    # - Contains frame rate info: 30%
    # - Mentions correct FPS: 25%
    # - Has diagnostic data: 20%
    # - Recording verified: 10%
    
    score = int(sum([
        checks['analysis_file_exists'] * 15,
        checks['contains_framerate_info'] * 30,
        checks['mentions_correct_fps'] * 25,
        checks['has_diagnostic_data'] * 20,
        checks['recording_verified'] * 10
    ]))
    
    passed = score >= 70
    
    if passed:
        feedback_parts.append("✅ Task completed successfully!")
        feedback_parts.append("Agent verified gameplay recording frame rate using VLC's diagnostic tools")
    else:
        feedback_parts.append(f"⚠️ Task partially completed (score: {score}/100)")
        if not checks['contains_framerate_info']:
            feedback_parts.append("Hint: Use Tools → Media Information (Ctrl+I) → Codec Details")
        if not checks['mentions_correct_fps']:
            feedback_parts.append("Hint: Recording should show 60 FPS")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
