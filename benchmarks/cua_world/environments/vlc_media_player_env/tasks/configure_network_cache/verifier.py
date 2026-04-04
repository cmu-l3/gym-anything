#!/usr/bin/env python3
"""
Verifier for Configure Network Cache task.

Checks if VLC's network cache settings have been increased
to appropriate values for smooth high-bitrate network playback.
"""

import os
import re
import sys
import json
import logging
import tempfile
from pathlib import Path
from typing import Tuple, Dict, Any, Optional

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config, logger

logging.basicConfig(level=logging.INFO)


def verify_configure_network_cache(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify that VLC's network cache has been configured to appropriate values.
    
    Requirements:
    - network-caching parameter must be increased from default (300ms)
    - Recommended range: 1000-5000ms (1-5 seconds)
    - Optimal range: 1500-3000ms
    - Must not be excessively high (>10000ms = 10s startup delay)
    
    Args:
        traj: Trajectory data (not used in this verification)
        env_info: Environment info dict with copy_from_env function
        task_info: Task information dict
    
    Returns:
        Dict with keys: passed (bool), score (int 0-100), feedback (str)
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
    
    # Create temporary file for config
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.vlcrc', mode='w')
    temp_config_path = temp_config.name
    temp_config.close()
    
    try:
        # Copy VLC config file from container
        try:
            copy_from_env("/tmp/task_output/vlcrc", temp_config_path)
        except Exception as e:
            logger.error(f"Error copying VLC config: {e}", exc_info=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy VLC configuration file: {str(e)}"
            }
        
        # Check if file exists and has content
        if not os.path.exists(temp_config_path) or os.path.getsize(temp_config_path) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ VLC configuration file not found or empty. No changes detected."
            }
        
        # Criterion 1: Config file is accessible and parseable
        config = parse_vlc_config(temp_config_path)
        
        if not config:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Failed to parse VLC configuration file."
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Config accessible")
        
        # Look for network-caching setting (VLC may use different key names)
        network_cache_key = None
        network_cache_value = None
        
        # VLC uses different key names depending on version
        possible_keys = ['network-caching', 'network-cache', 'network_caching']
        
        for key in possible_keys:
            if key in config:
                network_cache_key = key
                network_cache_value = config[key]
                logger.info(f"Found network cache key: {key} = {network_cache_value}")
                break
        
        if network_cache_value is None:
            # Check if file-caching was modified instead (also helps but less specific)
            if 'file-caching' in config:
                file_cache = int(config.get('file-caching', 300))
                if file_cache > 300:
                    return {
                        "passed": True,
                        "score": 60,
                        "feedback": (
                            f"⚠️  Partial success: file-caching increased to {file_cache}ms, "
                            "but network-caching not specifically configured. "
                            "This may help but is not the optimal solution for network playback."
                        )
                    }
            
            return {
                "passed": False,
                "score": 33,
                "feedback": (
                    "❌ Network cache setting not found in configuration. "
                    "Did you navigate to Advanced Preferences (Tools → Preferences → Show settings: All) "
                    "and modify the 'Network caching (ms)' parameter in Input/Codecs → Advanced?"
                )
            }
        
        # Parse cache value
        try:
            cache_ms = int(network_cache_value)
        except ValueError:
            return {
                "passed": False,
                "score": 33,
                "feedback": f"❌ Invalid network cache value: '{network_cache_value}' (expected integer)"
            }
        
        # Evaluation criteria with detailed scoring
        DEFAULT_CACHE = 300
        MIN_ACCEPTABLE = 800
        OPTIMAL_MIN = 1500
        OPTIMAL_MAX = 3000
        GOOD_MAX = 5000
        EXCESSIVE_THRESHOLD = 10000
        
        # Criterion 2 & 3: Check cache value and provide detailed feedback
        if cache_ms <= DEFAULT_CACHE:
            return {
                "passed": False,
                "score": 33,
                "feedback": (
                    f"❌ Network cache unchanged or decreased ({cache_ms}ms). "
                    f"Default is {DEFAULT_CACHE}ms. Must increase to prevent stuttering. "
                    f"Recommended: 1500-3000ms for high-bitrate network files."
                )
            }
        
        elif cache_ms < MIN_ACCEPTABLE:
            criteria_met += 1  # At least changed
            return {
                "passed": False,
                "score": 50,
                "feedback": (
                    f"⚠️  Network cache slightly increased to {cache_ms}ms, "
                    f"but still too low for smooth playback of high-bitrate content. "
                    f"Recommend 1500-3000ms for optimal performance."
                )
            }
        
        elif MIN_ACCEPTABLE <= cache_ms < OPTIMAL_MIN:
            criteria_met += 2
            reward = 70
            return {
                "passed": True,
                "score": reward,
                "feedback": (
                    f"✅ Network cache increased to {cache_ms}ms. "
                    f"This should help reduce stuttering. "
                    f"For optimal performance with 4K content, consider 1500-3000ms. "
                    f"Current setting is acceptable."
                )
            }
        
        elif OPTIMAL_MIN <= cache_ms <= OPTIMAL_MAX:
            criteria_met += 3
            reward = 100
            return {
                "passed": True,
                "score": reward,
                "feedback": (
                    f"✅ ✨ Perfect! Network cache set to {cache_ms}ms. "
                    f"This is optimal for high-bitrate network playback. "
                    f"Stuttering should be eliminated without excessive buffering delay. "
                    f"Great job configuring VLC's advanced settings!"
                )
            }
        
        elif OPTIMAL_MAX < cache_ms <= GOOD_MAX:
            criteria_met += 3
            reward = 90
            return {
                "passed": True,
                "score": reward,
                "feedback": (
                    f"✅ Network cache set to {cache_ms}ms. "
                    f"This will definitely prevent stuttering, though initial buffering "
                    f"may take a bit longer than necessary ({cache_ms/1000:.1f} seconds). "
                    f"Still a good solution. Optimal range is 1500-3000ms."
                )
            }
        
        elif cache_ms > EXCESSIVE_THRESHOLD:
            criteria_met += 2
            reward = 50
            return {
                "passed": True,
                "score": reward,
                "feedback": (
                    f"⚠️  Network cache set to {cache_ms}ms ({cache_ms/1000:.1f} seconds). "
                    f"While this will prevent stuttering, such a large buffer causes long "
                    f"initial loading times when starting playback. "
                    f"Consider reducing to 1500-3000ms for better balance between "
                    f"smoothness and responsiveness."
                )
            }
        
        else:  # GOOD_MAX < cache_ms <= EXCESSIVE_THRESHOLD
            criteria_met += 3
            reward = 80
            return {
                "passed": True,
                "score": reward,
                "feedback": (
                    f"✅ Network cache set to {cache_ms}ms ({cache_ms/1000:.1f} seconds). "
                    f"This will prevent stuttering, though the buffer is larger than typically needed. "
                    f"Initial buffering will take a few seconds. "
                    f"Optimal range is 1500-3000ms, but this configuration will work well."
                )
            }
    
    finally:
        # Cleanup temporary file
        try:
            if os.path.exists(temp_config_path):
                os.unlink(temp_config_path)
                logger.debug(f"Cleaned up temp config file: {temp_config_path}")
        except Exception as e:
            logger.warning(f"Failed to cleanup temp file {temp_config_path}: {e}")


def verify_task_output():
    """
    Main verification entry point for gym-anything framework.
    This function is called by the framework's verification system.
    """
    # Note: This is a wrapper that would be called by the framework
    # The actual verification happens in verify_configure_network_cache
    logger.info("=" * 70)
    logger.info("VERIFICATION: configure_network_cache@1")
    logger.info("=" * 70)
    logger.info("This verifier checks if VLC's network cache buffer has been")
    logger.info("configured to appropriate values for smooth network playback.")
    logger.info("=" * 70)
    
    # In actual usage, the framework calls verify_configure_network_cache
    # with proper arguments
    return {"message": "Use verify_configure_network_cache as verification function"}
