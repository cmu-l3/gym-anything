#!/usr/bin/env python3
"""
Verifier for Configure Low-Bandwidth Streaming task

This verifier checks that the VLC network cache has been increased
to at least 5000ms to allow smooth streaming on slow connections.
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vlc_config_for_network_caching(config_content):
    """
    Parse VLC config content for network-caching parameter.
    
    Args:
        config_content: String content of vlcrc file
        
    Returns:
        int or None: network-caching value in ms, or None if not found
    """
    for line in config_content.split('\n'):
        line = line.strip()
        
        # Skip comments and empty lines
        if not line or line.startswith('#') or line.startswith('['):
            continue
        
        # Look for network-caching parameter
        if line.startswith('network-caching='):
            try:
                value_str = line.split('=', 1)[1].strip()
                return int(value_str)
            except (ValueError, IndexError) as e:
                logger.error(f"Failed to parse network-caching value: {e}")
                return None
    
    return None


def verify_low_bandwidth_config(traj, env_info, task_info):
    """
    Verify VLC is configured for low-bandwidth streaming.
    
    Checks:
    1. VLC config file exists and is accessible
    2. network-caching parameter is present
    3. network-caching value is >= 5000ms (target threshold)
    
    Args:
        traj: Trajectory information (not used in this verifier)
        env_info: Environment info containing copy_from_env function
        task_info: Task information (not used in this verifier)
        
    Returns:
        dict: Verification result with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available - cannot verify task"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Target threshold
    TARGET_CACHE_MS = 5000
    DEFAULT_CACHE_MS = 1000
    TOLERANCE_MS = 100  # Allow some variation (4900-5000+ is acceptable)
    
    # Copy config file from container
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
    
    try:
        # Try to copy the config file
        try:
            copy_from_env("/tmp/vlc_network_config.txt", temp_config.name)
        except Exception as e:
            logger.error(f"Failed to copy config file: {e}", exc_info=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ VLC config file not found or not accessible. Settings may not have been saved. Error: {str(e)}"
            }
        
        # Criterion 1: Config file accessible
        criteria_met += 1
        feedback_parts.append("✅ Config file accessible")
        
        # Read and parse config content
        with open(temp_config.name, 'r') as f:
            config_content = f.read()
        
        logger.info(f"Config content length: {len(config_content)} bytes")
        
        # Parse for network-caching parameter
        network_cache = parse_vlc_config_for_network_caching(config_content)
        
        if network_cache is None:
            feedback_parts.append(
                "❌ network-caching parameter not found in config. "
                "Did you save the settings after changing them?"
            )
            os.unlink(temp_config.name)
            os.unlink(temp_json.name)
            
            score = int((criteria_met / total_criteria) * 100)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 2: Parameter exists
        criteria_met += 1
        feedback_parts.append(f"✅ network-caching parameter found: {network_cache}ms")
        
        # Criterion 3: Value meets threshold
        if network_cache >= (TARGET_CACHE_MS - TOLERANCE_MS):
            criteria_met += 1
            
            if network_cache >= TARGET_CACHE_MS:
                feedback_parts.append(
                    f"✅ Network cache configured correctly "
                    f"({network_cache}ms ≥ {TARGET_CACHE_MS}ms target)"
                )
            else:
                # Slightly below target but within tolerance
                feedback_parts.append(
                    f"✅ Network cache very close to target "
                    f"({network_cache}ms ≈ {TARGET_CACHE_MS}ms)"
                )
        else:
            # Check if at least changed from default
            if network_cache > DEFAULT_CACHE_MS:
                # Partial credit - increased but not enough
                criteria_met += 0.5
                feedback_parts.append(
                    f"⚠️ Network cache increased to {network_cache}ms, "
                    f"but below target of {TARGET_CACHE_MS}ms. "
                    f"Need {TARGET_CACHE_MS - network_cache}ms more."
                )
            elif network_cache == DEFAULT_CACHE_MS:
                # No change from default
                feedback_parts.append(
                    f"❌ Network cache still at default {DEFAULT_CACHE_MS}ms. "
                    f"Need to increase to {TARGET_CACHE_MS}ms."
                )
            else:
                # Somehow decreased below default
                feedback_parts.append(
                    f"❌ Network cache is {network_cache}ms (below default {DEFAULT_CACHE_MS}ms)"
                )
        
        # Try to also read the JSON result for additional info
        try:
            copy_from_env("/tmp/vlc_network_config_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result_json = json.load(f)
                logger.info(f"JSON result: {result_json}")
        except Exception as e:
            logger.warning(f"Could not read JSON result: {e}")
        
        # Clean up temp files
        os.unlink(temp_config.name)
        os.unlink(temp_json.name)
        
    except Exception as e:
        # Clean up on error
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Error during verification: {str(e)}"
        }
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    # Add context about what this achieves
    if passed:
        feedback += " | 🎉 VLC now configured for smooth streaming on slow connections!"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }