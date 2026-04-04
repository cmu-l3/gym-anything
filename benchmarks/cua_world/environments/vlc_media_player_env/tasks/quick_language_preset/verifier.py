#!/usr/bin/env python3
"""
Verifier for Quick Language Preset task

This verifier checks if the user has successfully created and documented
three language preset configurations for a multilingual household scenario.
"""

import sys
import os
import logging
import tempfile
import re
from typing import Dict, Tuple

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_preset_line(line: str, preset_id: str) -> Tuple[bool, int, int]:
    """
    Parse a preset line to extract audio and subtitle track numbers.
    
    Args:
        line: Line from presets file
        preset_id: Expected preset identifier (A, B, or C)
        
    Returns:
        Tuple of (found, audio_track, subtitle_track)
    """
    # Normalize line
    line = line.lower().strip()
    
    # Check if this line is for the expected preset
    if f'preset {preset_id.lower()}' not in line and f'preset{preset_id.lower()}' not in line:
        return False, -1, -1
    
    # Extract audio track number
    audio_match = re.search(r'audio[_\s]*track[:\s=]+(\d+)', line)
    audio_track = int(audio_match.group(1)) if audio_match else -1
    
    # Extract subtitle track number (can be -1, 0, or positive)
    subtitle_match = re.search(r'subtitle[_\s]*track[:\s=]+(-?\d+)', line)
    subtitle_track = int(subtitle_match.group(1)) if subtitle_match else -99
    
    return True, audio_track, subtitle_track


def check_preset_configuration(content: str, preset_id: str, 
                               expected_audio: int, 
                               expected_subtitle: int,
                               preset_name: str) -> Tuple[bool, str]:
    """
    Check if a specific preset configuration is present and correct.
    
    Args:
        content: Full content of presets file
        preset_id: Preset identifier (A, B, C)
        expected_audio: Expected audio track number
        expected_subtitle: Expected subtitle track number
        preset_name: Human-readable preset name for feedback
        
    Returns:
        Tuple of (is_correct, feedback_message)
    """
    lines = content.split('\n')
    
    for line in lines:
        found, audio_track, subtitle_track = parse_preset_line(line, preset_id)
        
        if found:
            # Check audio track
            audio_correct = (audio_track == expected_audio)
            
            # Check subtitle track (accept -1, 0, or "disabled" for no subtitles)
            subtitle_correct = False
            if expected_subtitle == -1:  # No subtitles expected
                # Accept -1, 0, or mentions of "disabled", "none", "off"
                if subtitle_track in [-1, 0]:
                    subtitle_correct = True
                elif 'disabled' in line or 'none' in line or 'off' in line:
                    subtitle_correct = True
            else:
                subtitle_correct = (subtitle_track == expected_subtitle)
            
            if audio_correct and subtitle_correct:
                return True, f"✅ Preset {preset_id} ({preset_name}) correct: audio={audio_track}, subtitle={subtitle_track}"
            else:
                error_parts = []
                if not audio_correct:
                    error_parts.append(f"audio={audio_track} (expected {expected_audio})")
                if not subtitle_correct:
                    error_parts.append(f"subtitle={subtitle_track} (expected {expected_subtitle})")
                return False, f"⚠️ Preset {preset_id} ({preset_name}) incorrect: {', '.join(error_parts)}"
    
    return False, f"❌ Preset {preset_id} ({preset_name}) not found"


def verify_quick_language_preset(traj, env_info, task_info):
    """
    Verify quick language preset task completion.
    
    Checks:
    1. Presets file exists and is readable
    2. Preset A (Grandparents): Spanish audio (track 2), no subtitles
    3. Preset B (Children): English audio (track 1), Spanish subtitles (track 2)
    4. Preset C (Parents): English audio (track 1), no subtitles
    
    Returns:
        Dict with keys: passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 4  # File exists + 3 presets
    feedback_parts = []
    
    # Copy presets file from container
    temp_presets = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_language_presets.txt", temp_presets.name)
    except Exception as e:
        logger.error(f"Error copying presets file: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Presets file not found at /home/ga/Videos/language_presets.txt"
        }
    
    # Read and parse presets file
    try:
        with open(temp_presets.name, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Check if file is empty or just placeholder
        if len(content.strip()) < 20 or "No presets documented" in content:
            os.unlink(temp_presets.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Presets file is empty or incomplete"
            }
        
        criteria_met += 1
        file_size = len(content)
        feedback_parts.append(f"✅ Presets file exists ({file_size} bytes)")
        
        # Check Preset A: Spanish audio (track 2), no subtitles
        preset_a_correct, preset_a_feedback = check_preset_configuration(
            content, 'A', 2, -1, 'Grandparents'
        )
        feedback_parts.append(preset_a_feedback)
        if preset_a_correct:
            criteria_met += 1
        
        # Check Preset B: English audio (track 1), Spanish subtitles (track 2)
        preset_b_correct, preset_b_feedback = check_preset_configuration(
            content, 'B', 1, 2, 'Children'
        )
        feedback_parts.append(preset_b_feedback)
        if preset_b_correct:
            criteria_met += 1
        
        # Check Preset C: English audio (track 1), no subtitles
        preset_c_correct, preset_c_feedback = check_preset_configuration(
            content, 'C', 1, -1, 'Parents'
        )
        feedback_parts.append(preset_c_feedback)
        if preset_c_correct:
            criteria_met += 1
        
        os.unlink(temp_presets.name)
        
    except Exception as e:
        logger.error(f"Error parsing presets file: {e}", exc_info=True)
        if os.path.exists(temp_presets.name):
            os.unlink(temp_presets.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Error parsing presets file: {str(e)}"
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_preset_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        if "completed" in marker_content.lower():
            feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    # Build feedback message
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"🎉 SUCCESS! {feedback}"
    else:
        feedback = f"📋 Incomplete ({criteria_met}/{total_criteria} criteria met): {feedback}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
