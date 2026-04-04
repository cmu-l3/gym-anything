#!/usr/bin/env python3
"""
Verifier for Configure Transcription Workflow task
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


def verify_jump_configuration(config: dict) -> tuple:
    """
    Verify short jump interval is configured for transcription workflow.
    
    Args:
        config: Parsed VLC configuration dictionary
        
    Returns:
        (success: bool, feedback: str, configured_value: int)
    """
    # Check various possible parameter names across VLC versions
    jump_params = [
        'short-jump-size',
        'extrashort-jump-size', 
        'key-jump-short',
        'short_jump_length',
        'hotkeys-jump-short'
    ]
    
    found_configs = []
    
    for param in jump_params:
        if param in config:
            try:
                value_str = config[param].strip()
                # Handle various formats
                value = int(float(value_str))
                found_configs.append((param, value))
                logger.info(f"Found jump config: {param}={value}")
            except (ValueError, AttributeError) as e:
                logger.warning(f"Could not parse {param}={config[param]}: {e}")
                continue
    
    if not found_configs:
        return False, "No custom jump interval configuration found", 10
    
    # Use the first found configuration
    param, value = found_configs[0]
    
    # Check if value is in ideal range for transcription (2-5 seconds)
    if 2 <= value <= 5:
        logger.info(f"✓ Suitable transcription config: {param}={value}s")
        return True, f"Perfect! Jump interval configured to {value}s (ideal for transcription)", value
    elif value < 2:
        return False, f"Jump interval too short: {value}s (need 2-5s for context). Found in: {param}", value
    elif value > 5 and value < 10:
        # Partial credit - it's better than default but not optimal
        return False, f"Jump interval a bit long: {value}s (optimal is 2-5s). Found in: {param}", value
    else:
        # Still at default or worse
        return False, f"Jump interval not properly configured: {value}s (need 2-5s). Found in: {param}", value


def verify_config_file_valid(config_path: str) -> tuple:
    """
    Verify config file exists and is parseable.
    
    Args:
        config_path: Path to vlcrc file
        
    Returns:
        (success: bool, feedback: str, config: dict)
    """
    if not os.path.exists(config_path):
        return False, f"Configuration file not found: {config_path}", {}
    
    # Check file is not empty
    file_size = os.path.getsize(config_path)
    if file_size == 0:
        return False, "Configuration file is empty", {}
    
    # Try to parse the config
    try:
        config = parse_vlc_config(config_path)
        if not config:
            return False, "Configuration file exists but could not be parsed", {}
        
        logger.info(f"Successfully parsed config with {len(config)} entries")
        return True, f"Config file valid ({file_size} bytes, {len(config)} settings)", config
        
    except Exception as e:
        return False, f"Error parsing configuration: {e}", {}


def verify_configure_transcription_workflow(traj, env_info, task_info):
    """
    Verify configure transcription workflow task completion.
    
    Checks:
    1. VLC config file exists and is parseable
    2. Short jump interval is configured to 2-5 seconds
    3. Configuration was actually modified (not default 10)
    
    Args:
        traj: Agent trajectory (not used)
        env_info: Environment info dict with copy_from_env function
        task_info: Task info dict (not used)
        
    Returns:
        Dictionary with keys: passed (bool), score (int 0-100), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify configuration"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    configured_value = None
    
    # Copy VLC config from container
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.vlcrc', mode='w+')
    temp_config_path = temp_config.name
    temp_config.close()
    
    try:
        # Try to copy the config file
        try:
            copy_from_env("/tmp/vlc_transcription_config.vlcrc", temp_config_path)
            logger.info(f"Copied config to {temp_config_path}")
        except Exception as e:
            logger.error(f"Error copying config file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access VLC configuration: {str(e)}"
            }
        
        # Criterion 1: Config file exists and is valid
        config_valid, config_msg, config = verify_config_file_valid(temp_config_path)
        
        if not config_valid:
            return {
                "passed": False,
                "score": 0,
                "feedback": config_msg
            }
        
        criteria_met += 1
        feedback_parts.append(f"✅ {config_msg}")
        
        # Criterion 2 & 3: Jump interval configured correctly
        jump_ok, jump_msg, configured_value = verify_jump_configuration(config)
        
        if jump_ok:
            # Perfect configuration
            criteria_met += 2
            feedback_parts.append(f"✅ {jump_msg}")
        elif configured_value is not None and configured_value != 10:
            # Configuration was modified but not optimal
            criteria_met += 1
            feedback_parts.append(f"⚠️ {jump_msg}")
            
            # Give partial credit if close to target
            if 1 <= configured_value <= 7:
                criteria_met += 0.5
                feedback_parts.append("⚠️ Configuration modified (partial credit)")
        else:
            # No valid configuration or still at default
            feedback_parts.append(f"❌ {jump_msg}")
            feedback_parts.append("❌ Short jump interval not configured for transcription")
        
        # Check completion marker (bonus, doesn't affect main scoring)
        temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/vlc_transcription_completed.txt", temp_marker.name)
            with open(temp_marker.name, 'r') as f:
                content = f.read()
            if content:
                feedback_parts.append("✅ Task completion marker present")
            os.unlink(temp_marker.name)
        except Exception:
            # Not critical
            pass
        
    finally:
        # Cleanup
        if os.path.exists(temp_config_path):
            try:
                os.unlink(temp_config_path)
            except Exception as e:
                logger.warning(f"Could not delete temp config: {e}")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    # Add helpful hint if failed
    if not passed:
        feedback += " | Hint: Open Tools→Preferences→All→Interface→Hotkeys, find 'Short jump length', set to 3"
    
    logger.info(f"Verification result: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }


# Entry point for gym_anything
def verify_task(eval_output_dir: str) -> dict:
    """
    Alternative entry point if called directly with eval_output_dir.
    
    This is used when verification system calls verifier differently.
    """
    # This function adapts the interface if needed
    # For now, we expect the standard interface with traj, env_info, task_info
    logger.warning("verify_task called with eval_output_dir directly - using adapted interface")
    
    # Mock the expected interface
    class MockEnvInfo:
        def get(self, key):
            if key == 'copy_from_env':
                # Return a function that copies from eval_output_dir
                def copy_func(src, dst):
                    import shutil
                    src_path = os.path.join(eval_output_dir, os.path.basename(src))
                    shutil.copy(src_path, dst)
                return copy_func
            return None
    
    return verify_configure_transcription_workflow(None, MockEnvInfo(), None)
