#!/usr/bin/env python3
"""
Verifier for Verify Audio Spectrum task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_audio_spectrum(traj, env_info, task_info):
    """
    Verify audio spectrum visualization task completion.
    
    Checks:
    1. VLC configuration file is accessible
    2. Audio visualizer is enabled
    3. Visualizer type is spectrum/spectrometer
    4. The correct audio file was accessed
    
    Returns:
        Dict with passed (bool), score (float), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Copy spectrum result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Criterion 1: Result file exists
        try:
            copy_from_env("/tmp/vlc_spectrum_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying spectrum result: {e}", exc_info=True)
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"❌ Result file not found. Did VLC run? Error: {str(e)}"
            }
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        config_found = result.get('config_found', False)
        
        if config_found:
            criteria_met += 1
            feedback_parts.append("✅ VLC config accessible")
        else:
            feedback_parts.append("❌ VLC config not found")
            os.unlink(temp_result.name)
            return {
                "passed": False,
                "score": 25,
                "feedback": " | ".join(feedback_parts) + " | Hint: Ensure VLC was opened"
            }
        
        # Criterion 2: Audio visualizer enabled
        visualizer_enabled = result.get('visualizer_enabled', False)
        visualizer_type = result.get('visualizer_type', 'none')
        
        if visualizer_enabled:
            criteria_met += 1
            feedback_parts.append(f"✅ Audio visualizer enabled")
        else:
            feedback_parts.append("❌ Audio visualizer not enabled")
            feedback_parts.append("   Hint: Tools → Effects and Filters → Visualization")
        
        # Criterion 3: Check visualizer type is spectrum/spectrometer
        is_spectrum_mode = (
            'spectrum' in visualizer_type.lower() or
            'spectrometer' in visualizer_type.lower() or
            'visual' in visualizer_type.lower()  # VLC sometimes uses 'visual' generically
        )
        
        if is_spectrum_mode and visualizer_enabled:
            criteria_met += 1
            feedback_parts.append(f"✅ Spectrum mode active (type: {visualizer_type})")
        elif visualizer_enabled:
            feedback_parts.append(f"⚠️ Visualizer enabled but not spectrum mode (got: {visualizer_type})")
            feedback_parts.append("   Required: Spectrum or Spectrometer visualization")
        else:
            feedback_parts.append("❌ Spectrum visualization not active")
        
        # Criterion 4: Check if target audio file was played
        file_played = result.get('file_played', False)
        
        if file_played:
            criteria_met += 1
            feedback_parts.append("✅ Target audio file was played")
        else:
            feedback_parts.append("⚠️ Could not verify audio file was played")
            feedback_parts.append("   Make sure to open: /home/ga/Music/questionable_hifi.flac")
        
        os.unlink(temp_result.name)
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Invalid result format: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    # Optional: Check for additional evidence
    try:
        # Copy VLC config file for detailed inspection
        temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/vlc_spectrum_vlcrc.txt", temp_config.name)
        
        with open(temp_config.name, 'r') as f:
            config_content = f.read()
        
        # Additional validation: check config has relevant settings
        if 'audio-visual' in config_content or 'effect-list' in config_content:
            logger.info("VLC config contains visualization settings")
        
        os.unlink(temp_config.name)
    except Exception as e:
        logger.debug(f"Could not read VLC config for additional validation: {e}")
    
    # Check completion marker
    try:
        temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/vlc_spectrum_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70  # Need 70% to pass (3/4 criteria)
    
    feedback = "\n".join(feedback_parts)
    
    # Add summary
    if passed:
        feedback += "\n\n✨ Success! The spectrum analyzer is properly configured."
        feedback += "\n   In a real scenario, you would now observe the frequency content"
        feedback += "\n   to verify if the audio truly contains high-frequency information."
    else:
        feedback += f"\n\n❌ Task incomplete (score: {score}/100, need: 70+)"
        feedback += "\n   Review the hints above and try again."
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
