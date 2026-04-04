#!/usr/bin/env python3
"""
Verifier for Troubleshoot Video Output task.
Checks if VLC is configured to use OpenGL video output module.
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_troubleshoot_video_output(traj, env_info, task_info):
    """
    Verify that VLC video output module is set to OpenGL.
    
    Checks:
    1. VLC configuration file exists and is parseable
    2. Video output (vout) is set to an OpenGL variant
    3. Setting was changed from the initial automatic value
    
    Args:
        traj: Trajectory information (unused)
        env_info: Environment info containing copy_from_env function
        task_info: Task information (unused)
        
    Returns:
        dict: {passed: bool, score: int, feedback: str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available - cannot verify configuration"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy VLC configuration file
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        # Try to copy the config file
        try:
            copy_from_env("/tmp/vlc_output_config.txt", temp_config.name)
        except Exception as e:
            logger.error(f"Error copying VLC config: {e}", exc_info=True)
            
            # Check if config was missing
            temp_missing = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            try:
                copy_from_env("/tmp/vlc_output_config_missing.txt", temp_missing.name)
                os.unlink(temp_missing.name)
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "❌ VLC configuration file not found. Did you save the settings? (Hint: Click 'Save' button in Preferences)"
                }
            except:
                pass
            
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not access VLC configuration: {str(e)}"
            }
        
        # Check if file was actually copied
        if not os.path.exists(temp_config.name) or os.path.getsize(temp_config.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ VLC configuration file is empty or was not saved"
            }
        
        # Parse VLC configuration
        config = parse_vlc_config(temp_config.name)
        
        if not config:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Could not parse VLC configuration file. File may be corrupted."
            }
        
        # Criterion 1: Config file exists and is parseable
        criteria_met += 1
        feedback_parts.append("✅ VLC configuration accessible")
        
        # Get video output setting
        vout_setting = config.get('vout', '').lower().strip()
        
        logger.info(f"Video output setting found: '{vout_setting}'")
        
        # Criterion 2: Check if vout is set to OpenGL variant
        # Accept multiple valid OpenGL-related values
        valid_opengl_values = [
            'gl',           # Generic OpenGL
            'opengl',       # OpenGL
            'glx',          # OpenGL for X11
            'gles2',        # OpenGL ES 2.0
            'gles',         # OpenGL ES
        ]
        
        if vout_setting in valid_opengl_values:
            criteria_met += 2  # Double weight for main criterion
            feedback_parts.append(
                f"✅ Video output correctly set to '{vout_setting}' (OpenGL)"
            )
            feedback_parts.append(
                "🎯 This should eliminate screen tearing and provide smooth playback"
            )
        elif vout_setting and vout_setting != 'auto' and vout_setting != 'automatic':
            # Some other non-automatic value was set
            criteria_met += 1
            feedback_parts.append(
                f"⚠️ Video output changed to '{vout_setting}', but not OpenGL. "
                f"Expected: 'gl', 'opengl', 'glx', or 'gles2'"
            )
        else:
            # Still on automatic or not set
            feedback_map = {
                'auto': "Video output is still set to 'auto' (automatic). You need to explicitly select OpenGL.",
                'automatic': "Video output is still set to automatic. You need to explicitly select OpenGL.",
                '': "Video output setting not found or empty. You need to set it to OpenGL.",
            }
            
            specific_feedback = feedback_map.get(
                vout_setting,
                f"Video output is '{vout_setting}', not OpenGL. Select OpenGL video output."
            )
            
            feedback_parts.append(f"❌ {specific_feedback}")
            
            # Add helpful hint
            feedback_parts.append(
                "💡 Hint: Tools → Preferences → Show All → Video → Output modules → Video output module"
            )
        
        # Criterion 3: Verify config file was actually modified (has reasonable content)
        with open(temp_config.name, 'r') as f:
            config_content = f.read()
        
        if len(config_content) > 50:  # Config has substantial content
            if 'vout=' in config_content or 'video' in config_content.lower():
                feedback_parts.append("✅ Configuration file properly saved")
            else:
                feedback_parts.append("⚠️ Configuration may be incomplete")
        
        # Clean up temp file
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        try:
            os.unlink(temp_config.name)
        except:
            pass
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    # Check for completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_output_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    # Add performance summary
    if passed:
        summary = (
            f"✅ SUCCESS! VLC configured with OpenGL video output. "
            f"Screen tearing should now be resolved. Score: {score}%"
        )
    elif criteria_met >= 1:
        summary = (
            f"⚠️ PARTIAL: Configuration accessible but OpenGL not set. "
            f"Score: {score}%"
        )
    else:
        summary = f"❌ FAILED: Could not verify configuration changes. Score: {score}%"
    
    feedback = f"{summary} | {feedback}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
