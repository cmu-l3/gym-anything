#!/usr/bin/env python3
"""
Verifier for Setup Ambient Background task

Checks that VLC was configured for ambient background playback:
- Infinite loop enabled
- Volume set to appropriate level (~40%)
- Minimal interface settings applied
- Configuration persisted to vlcrc file
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_setup_ambient_background(traj, env_info, task_info):
    """
    Verify ambient background configuration task completion.
    
    Checks:
    1. Loop/repeat enabled in config (infinite playback)
    2. Volume set to 35-45% range (90-115 on 0-256 scale)
    3. Minimal interface settings applied
    4. Settings persisted in configuration file
    
    Pass threshold: 75% (requires 3/4 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Copy ambient result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        try:
            copy_from_env("/tmp/vlc_ambient_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying ambient result: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Error copying result file: {str(e)}"}
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        # Extract values
        volume = int(result.get('volume', 256))
        volume_percent = float(result.get('volume_percent', 100))
        loop_enabled = result.get('loop_enabled', False)
        minimal_interface = result.get('minimal_interface', False)
        
        config_loop = result.get('config_loop', '')
        config_repeat = result.get('config_repeat', '')
        config_input_repeat = result.get('config_input_repeat', '')
        
        logger.info(f"Ambient config - Volume: {volume} ({volume_percent}%), Loop: {loop_enabled}, Minimal: {minimal_interface}")
        
        # Criterion 1: Loop/Repeat enabled for infinite playback
        # Check multiple possible loop indicators
        loop_indicators = [
            config_loop == '1',
            config_repeat == 'one',
            config_input_repeat and config_input_repeat != '0',
            loop_enabled is True
        ]
        
        if any(loop_indicators):
            criteria_met += 1
            feedback_parts.append("✅ Loop enabled for infinite playback")
            
            # Log which indicator was found
            if config_loop == '1':
                logger.info("Loop detected: loop=1")
            elif config_repeat == 'one':
                logger.info("Loop detected: repeat=one")
            elif config_input_repeat:
                logger.info(f"Loop detected: input-repeat={config_input_repeat}")
        else:
            feedback_parts.append("❌ Loop not enabled (video won't repeat)")
            logger.warning(f"Loop not found. config_loop={config_loop}, config_repeat={config_repeat}, config_input_repeat={config_input_repeat}")
        
        # Criterion 2: Volume at appropriate level for background (35-45%)
        # VLC scale: 0-256 where 256=100%, so 35-45% = 90-115
        target_min = 90  # 35%
        target_max = 115  # 45%
        
        # More lenient range for partial credit: 80-130 (31-51%)
        lenient_min = 80
        lenient_max = 130
        
        if target_min <= volume <= target_max:
            criteria_met += 1
            feedback_parts.append(f"✅ Volume at target ({volume_percent:.0f}%, ideal for background)")
        elif lenient_min <= volume <= lenient_max:
            # Partial credit if close to target
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Volume close to target ({volume_percent:.0f}%, target 35-45%)")
        elif volume < 256:
            # At least it was changed from default
            feedback_parts.append(f"⚠️ Volume changed ({volume_percent:.0f}%) but not optimal (target 35-45%)")
        else:
            feedback_parts.append(f"❌ Volume still at default ({volume_percent:.0f}%, target 35-45%)")
        
        # Criterion 3: Minimal interface settings
        # This is optional but demonstrates UX optimization
        if minimal_interface:
            criteria_met += 1
            feedback_parts.append("✅ Minimal interface configured")
        else:
            # Don't penalize too much - this is a bonus criterion
            feedback_parts.append("⚠️ Minimal interface not configured (optional)")
        
        # Criterion 4: Settings persisted in config file
        # Check that config file was actually modified
        temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/vlc_ambient_config.txt", temp_config.name)
            
            with open(temp_config.name, 'r') as f:
                config_content = f.read()
            
            # Check if config has content and relevant settings
            if len(config_content) > 100:  # Non-empty config
                # Parse config using utility
                config_dict = parse_vlc_config(temp_config.name)
                
                if config_dict:
                    criteria_met += 1
                    feedback_parts.append("✅ Settings persisted in config")
                else:
                    feedback_parts.append("⚠️ Config file exists but may be incomplete")
            else:
                feedback_parts.append("❌ Config file not properly saved")
            
            os.unlink(temp_config.name)
            
        except Exception as e:
            logger.warning(f"Could not verify config persistence: {e}")
            feedback_parts.append("⚠️ Could not verify config persistence")
        
        os.unlink(temp_result.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_ambient_completed.txt", temp_marker.name)
        logger.info("Task completion marker found")
        os.unlink(temp_marker.name)
    except Exception:
        logger.warning("Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Add summary
    summary = f"Score: {score}% ({criteria_met:.1f}/{total_criteria} criteria)"
    feedback = summary + " | " + " | ".join(feedback_parts)
    
    logger.info(f"Verification result: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "volume": volume,
            "volume_percent": volume_percent,
            "loop_enabled": loop_enabled,
            "minimal_interface": minimal_interface,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }