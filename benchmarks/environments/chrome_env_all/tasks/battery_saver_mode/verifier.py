#!/usr/bin/env python3
"""
Verifier for Chrome Battery Saver Mode Configuration Task (battery_saver_mode@1)
Task: Disable hardware acceleration to minimize battery consumption

Verification Strategy:
- Copy Chrome Preferences file from container to host
- Parse JSON and extract hardware_acceleration_mode.enabled key
- Verify that hardware acceleration is DISABLED (enabled = false)
- Check optional performance settings (memory saver, energy saver)
- Score based on criteria met (75% minimum to pass)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        setup_chrome_verification,
        parse_preferences,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def parse_preferences(path):
        """Fallback preferences parser"""
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        """Fallback cleanup"""
        pass


def check_hardware_acceleration_disabled(prefs: dict) -> tuple:
    """
    Check if hardware acceleration is disabled in preferences.
    
    Args:
        prefs: Parsed Chrome preferences dictionary
        
    Returns:
        Tuple of (is_disabled: bool, detail_message: str)
    """
    # Primary key for hardware acceleration
    hw_accel_mode = prefs.get('hardware_acceleration_mode', {})
    enabled = hw_accel_mode.get('enabled')
    
    # Check alternative paths in case Chrome version stores it differently
    if enabled is None:
        # Try alternative path
        enabled = prefs.get('hardware_acceleration', {}).get('enabled')
    
    # If key doesn't exist, hardware acceleration is typically ON by default
    if enabled is None:
        return False, "Hardware acceleration setting not found in Preferences (likely still enabled by default)"
    
    # Check if explicitly disabled (False)
    if enabled is False:
        return True, "Hardware acceleration successfully disabled"
    
    # If True or any other value, it's still enabled
    return False, f"Hardware acceleration is still enabled (value: {enabled})"


def check_memory_saver_enabled(prefs: dict) -> tuple:
    """
    Check if memory saver / high efficiency mode is enabled (bonus feature).
    
    Args:
        prefs: Parsed Chrome preferences dictionary
        
    Returns:
        Tuple of (is_enabled: bool, detail_message: str)
    """
    performance_tuning = prefs.get('performance_tuning', {})
    
    if not performance_tuning:
        return False, "Performance tuning settings not found"
    
    high_efficiency = performance_tuning.get('high_efficiency_mode', {})
    
    # Check if enabled
    enabled = high_efficiency.get('enabled', False)
    state = high_efficiency.get('state', 0)
    
    # State 2 typically means fully enabled
    if enabled or state == 2:
        return True, f"Memory Saver enabled (state: {state})"
    
    return False, "Memory Saver not enabled"


def check_battery_saver_enabled(prefs: dict) -> tuple:
    """
    Check if battery saver / energy saver mode is enabled (bonus feature).
    
    Args:
        prefs: Parsed Chrome preferences dictionary
        
    Returns:
        Tuple of (is_enabled: bool, detail_message: str)
    """
    performance_tuning = prefs.get('performance_tuning', {})
    
    if not performance_tuning:
        return False, "Performance tuning settings not found"
    
    battery_saver_state = performance_tuning.get('battery_saver_mode_state', 0)
    
    # State 2 typically means enabled
    if battery_saver_state == 2:
        return True, f"Energy Saver enabled (state: {battery_saver_state})"
    
    return False, f"Energy Saver not enabled (state: {battery_saver_state})"


def get_preferences_from_container(copy_from_env):
    """
    Copy and parse Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (prefs_dict or None, error_message: str)
    """
    # Try multiple possible locations for the Preferences file
    possible_paths = [
        "/tmp/chrome_preferences_battery.json",
        "/tmp/Preferences",
        "/home/ga/.config/google-chrome-cdp/Default/Preferences",
        "/home/ga/.config/google-chrome/Default/Preferences"
    ]
    
    temp_file = None
    
    for container_path in possible_paths:
        try:
            logger.info(f"Attempting to copy Preferences from: {container_path}")
            
            # Create temporary file
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
            temp_path = temp_file.name
            temp_file.close()
            
            # Copy from container
            copy_from_env(container_path, temp_path)
            
            # Check if file has content
            if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
                logger.debug(f"File from {container_path} is empty")
                os.unlink(temp_path)
                continue
            
            # Check if it's the error marker
            with open(temp_path, 'r') as f:
                first_line = f.read().strip()
                if first_line == "not_found":
                    logger.debug(f"Error marker found in {container_path}")
                    os.unlink(temp_path)
                    continue
            
            # Try to parse as JSON
            with open(temp_path, 'r', encoding='utf-8') as f:
                prefs = json.load(f)
            
            logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
            os.unlink(temp_path)
            return prefs, ""
            
        except json.JSONDecodeError as e:
            logger.debug(f"Invalid JSON in {container_path}: {e}")
            if temp_file and os.path.exists(temp_path):
                os.unlink(temp_path)
            continue
        except Exception as e:
            logger.debug(f"Failed to copy from {container_path}: {e}")
            if temp_file and os.path.exists(temp_path):
                os.unlink(temp_path)
            continue
    
    return None, "Could not access Chrome Preferences file from any known location"


def verify_task(traj, env_info, task_info):
    """
    Main verification function for battery_saver_mode@1 task.
    
    Verifies:
    1. Hardware acceleration is disabled (PRIMARY - 75 points)
    2. Memory saver is enabled (BONUS - 15 points)
    3. Energy saver is enabled (BONUS - 10 points)
    
    Scoring:
    - 100%: All criteria met (hardware accel disabled + both bonus features)
    - 75-99%: Hardware accel disabled, some/no bonus features
    - 0-74%: Hardware acceleration still enabled (FAIL)
    
    Pass threshold: 75% (requires hardware acceleration to be disabled)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), feedback (str), and details (dict)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }
    
    try:
        # Get Chrome Preferences from container
        logger.info("Retrieving Chrome Preferences from container...")
        prefs, error_msg = get_preferences_from_container(copy_from_env)
        
        if prefs is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Chrome preferences: {error_msg}"
            }
        
        # Check primary requirement: hardware acceleration disabled
        logger.info("Checking hardware acceleration status...")
        hw_accel_disabled, hw_detail = check_hardware_acceleration_disabled(prefs)
        
        # Check bonus features
        logger.info("Checking bonus battery-saving features...")
        memory_saver_enabled, mem_detail = check_memory_saver_enabled(prefs)
        battery_saver_enabled, bat_detail = check_battery_saver_enabled(prefs)
        
        # Calculate score
        score = 0
        feedback_parts = []
        
        # Primary criterion (75 points)
        if hw_accel_disabled:
            score += 75
            feedback_parts.append(f"✓ Hardware acceleration disabled (PRIMARY GOAL ACHIEVED)")
        else:
            feedback_parts.append(f"✗ Hardware acceleration still enabled (TASK FAILED)")
            feedback_parts.append(f"   Detail: {hw_detail}")
        
        # Bonus criterion 1 (15 points)
        if memory_saver_enabled:
            score += 15
            feedback_parts.append(f"✓ Memory Saver enabled (BONUS)")
        else:
            feedback_parts.append(f"○ Memory Saver not enabled (optional)")
        
        # Bonus criterion 2 (10 points)
        if battery_saver_enabled:
            score += 10
            feedback_parts.append(f"✓ Energy Saver enabled (BONUS)")
        else:
            feedback_parts.append(f"○ Energy Saver not enabled (optional)")
        
        # Determine pass/fail
        passed = score >= 75
        
        # Build feedback message
        feedback_header = "=" * 60
        if passed:
            feedback = f"{feedback_header}\n✅ BATTERY SAVER MODE CONFIGURATION SUCCESSFUL\n{feedback_header}\n"
        else:
            feedback = f"{feedback_header}\n❌ BATTERY SAVER MODE CONFIGURATION FAILED\n{feedback_header}\n"
        
        feedback += "\n".join(feedback_parts)
        feedback += f"\n\n{feedback_header}"
        feedback += f"\nFinal Score: {score}/100"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
        feedback += f"\n{feedback_header}"
        
        if passed and score == 75:
            feedback += "\n\n💡 Tip: You can further optimize battery life by enabling"
            feedback += "\n   Memory Saver and Energy Saver in Settings > Performance"
        
        # Log results
        logger.info(f"Verification complete: passed={passed}, score={score}")
        logger.info(f"  Hardware acceleration disabled: {hw_accel_disabled}")
        logger.info(f"  Memory saver enabled: {memory_saver_enabled}")
        logger.info(f"  Energy saver enabled: {battery_saver_enabled}")
        
        # Clean up
        cleanup_verification_temp()
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "hardware_acceleration_disabled": hw_accel_disabled,
                "memory_saver_enabled": memory_saver_enabled,
                "battery_saver_enabled": battery_saver_enabled,
                "hw_detail": hw_detail,
                "mem_detail": mem_detail,
                "bat_detail": bat_detail
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
