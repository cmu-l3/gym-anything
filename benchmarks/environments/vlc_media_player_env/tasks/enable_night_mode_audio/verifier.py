#!/usr/bin/env python3
"""
Verifier for enable_night_mode_audio@1 task.

Checks that VLC has been configured with:
1. Dynamic range compressor enabled
2. Volume normalizer enabled
3. Settings properly saved in configuration
"""

import sys
import os
import logging
import tempfile
import json

# Add utils to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_night_mode_audio(traj, env_info, task_info):
    """
    Verify that VLC night mode audio (compression + normalization) is enabled.
    
    Checks:
    1. VLC config file is accessible
    2. Dynamic range compressor is enabled
    3. Volume normalizer is enabled
    
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Copy function not available - cannot verify"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        try:
            copy_from_env("/tmp/vlc_night_mode_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result file: {e}", exc_info=True)
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"❌ Result file not found: {str(e)}"
            }
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        logger.info(f"Result data: {result}")
        
        # Criterion 1: Config file found and parsed
        config_found = result.get('config_found', False)
        if config_found:
            criteria_met += 1
            feedback_parts.append("✅ VLC config accessible")
        else:
            feedback_parts.append("❌ VLC config not found")
            os.unlink(temp_result.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ VLC configuration file not found. Did you save preferences?"
            }
        
        # Get filter settings
        audio_filter = result.get('audio_filter', '')
        compressor_enabled = result.get('compressor_enabled', False)
        normalizer_enabled = result.get('normalizer_enabled', False)
        
        logger.info(f"Audio filter: '{audio_filter}'")
        logger.info(f"Compressor: {compressor_enabled}, Normalizer: {normalizer_enabled}")
        
        # Criterion 2: Dynamic range compressor enabled
        if compressor_enabled:
            criteria_met += 1
            feedback_parts.append("✅ Dynamic range compressor enabled")
        else:
            feedback_parts.append("❌ Dynamic range compressor NOT enabled")
        
        # Criterion 3: Volume normalizer enabled
        if normalizer_enabled:
            criteria_met += 1
            feedback_parts.append("✅ Volume normalizer enabled")
        else:
            feedback_parts.append("❌ Volume normalizer NOT enabled")
        
        # Additional verification: parse vlcrc directly for more details
        temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/vlcrc_export.txt", temp_vlcrc.name)
            
            # Parse config using utility function
            config = parse_vlc_config(temp_vlcrc.name)
            
            if config:
                audio_filter_direct = config.get('audio-filter', '')
                if audio_filter_direct:
                    feedback_parts.append(f"📋 Filters: {audio_filter_direct}")
            
            os.unlink(temp_vlcrc.name)
        except Exception as e:
            logger.warning(f"Could not parse vlcrc directly: {e}")
        
        os.unlink(temp_result.name)
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Invalid result file format: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_night_mode_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        logger.info(f"Completion marker found: {marker_content}")
        os.unlink(temp_marker.name)
    except Exception as e:
        logger.warning(f"Completion marker not found: {e}")
        feedback_parts.append("⚠️ Completion marker missing")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70  # Need at least 2/3 criteria (config + one filter)
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    # Add contextual feedback based on success
    if passed:
        if criteria_met == total_criteria:
            feedback = f"🎉 SUCCESS! Night mode audio fully enabled.\n\n{feedback}\n\n" \
                      f"✨ Now you can watch movies late at night without disturbing neighbors!\n" \
                      f"   Quiet dialogue will be audible, and loud explosions won't be deafening."
        else:
            feedback = f"⚠️ PARTIAL SUCCESS ({criteria_met}/{total_criteria} criteria met)\n\n{feedback}\n\n" \
                      f"💡 Both compressor AND normalizer should be enabled for best results."
    else:
        missing = []
        if not compressor_enabled:
            missing.append("Dynamic range compressor")
        if not normalizer_enabled:
            missing.append("Volume normalizer")
        
        feedback = f"❌ Task incomplete ({criteria_met}/{total_criteria} criteria met)\n\n{feedback}\n\n" \
                  f"Missing: {', '.join(missing) if missing else 'Unknown'}\n\n" \
                  f"💡 HINT: Open Tools → Effects and Filters → Audio Effects\n" \
                  f"   Then enable BOTH Compressor and Normalizer.\n" \
                  f"   Finally, save in Tools → Preferences → Audio → Filters → Save"
    
    logger.info(f"Verification result: passed={passed}, score={score}")
    logger.info(f"Feedback: {feedback}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
