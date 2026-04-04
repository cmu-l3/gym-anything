#!/usr/bin/env python3
"""
Verifier for Chrome Data Saver Configuration Task (data_saver_setup@1)
Task: Configure Chrome for bandwidth optimization on slow/metered connections

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract bandwidth-related settings:
  * net.network_prediction_options (preloading)
  * safebrowsing.enhanced (Enhanced Safe Browsing data usage)
  * performance_tuning.high_efficiency_mode.state (Memory Saver)
  * dns_prefetching.enabled
  * search.suggest_enabled
  * alternate_error_pages.enabled
- Award points for each data-saving setting properly configured
- Pass threshold: 75% (need at least 2 major settings optimized)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        setup_chrome_verification,
        cleanup_verification_temp,
        parse_preferences
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


def get_preferences_file(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Retrieve and parse Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (preferences_dict or None, error_message)
    """
    temp_file = None
    
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
            logger.info("Attempting to use chrome_verification_utils...")
            try:
                success, files, error = setup_chrome_verification(
                    copy_from_env,
                    ["Preferences"],
                    user="ga",
                    profile="Default"
                )
                
                if success and "Preferences" in files:
                    prefs_path = files["Preferences"]
                    prefs = parse_preferences(prefs_path)
                    cleanup_verification_temp()
                    logger.info("✓ Successfully retrieved Preferences using utilities")
                    return prefs, ""
                else:
                    logger.warning(f"Utility-based retrieval failed: {error}")
            except Exception as e:
                logger.warning(f"Exception using utilities: {e}")
        
        # Fallback: Manual file retrieval
        logger.info("Using fallback manual file retrieval...")
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations in order of preference
        possible_paths = [
            "/tmp/chrome_preferences_export.json",
            "/tmp/Preferences",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        source_path = None
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 10:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    
                    # Validate it's actually a Preferences file (has expected structure)
                    if isinstance(prefs, dict) and len(prefs) > 0:
                        source_path = container_path
                        logger.info(f"✓ Successfully retrieved Preferences from: {container_path}")
                        break
                    else:
                        logger.warning(f"File from {container_path} doesn't look like valid Preferences")
                        prefs = None
                        
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs is None:
            return None, "Could not access Preferences file from any known location"
        
        return prefs, ""
        
    except json.JSONDecodeError as e:
        return None, f"Preferences file is not valid JSON: {e}"
    except Exception as e:
        logger.error(f"Error retrieving Preferences: {e}", exc_info=True)
        return None, f"Error retrieving Preferences: {str(e)}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def verify_data_saver_settings(prefs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify Chrome data-saving settings in Preferences file.
    
    Checks multiple settings that reduce bandwidth usage:
    - Network prediction/preloading (40 points)
    - Enhanced Safe Browsing (30 points)
    - Performance/memory saver mode (20 points)
    - Additional data-intensive features (10 points)
    
    Args:
        prefs: Parsed Chrome Preferences dictionary
        
    Returns:
        Dict with verification results including passed, score, feedback, and metrics
    """
    if not prefs or not isinstance(prefs, dict):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Invalid or empty Preferences data",
            "metrics": {}
        }
    
    score = 0
    max_score = 100
    feedback_items = []
    metrics = {}
    
    # Check 1: Network Prediction / Preloading (40 points - most critical)
    network_prediction = prefs.get('net', {}).get('network_prediction_options', None)
    metrics['network_prediction_option'] = network_prediction
    
    if network_prediction is not None:
        if network_prediction == 2:  # No preloading
            score += 40
            feedback_items.append("✓ Preloading disabled (network_prediction_options=2) - Excellent! [+40pts]")
            metrics['preloading_optimized'] = True
        elif network_prediction == 0:  # Standard (not Enhanced)
            score += 25
            feedback_items.append("✓ Preloading set to standard mode (not enhanced) - Good [+25pts]")
            metrics['preloading_optimized'] = True
        elif network_prediction == 1:  # Enhanced preloading
            feedback_items.append("✗ Preloading still on enhanced mode (uses most data) [+0pts]")
            metrics['preloading_optimized'] = False
        else:
            feedback_items.append(f"⚠ Unexpected preloading value: {network_prediction} [+0pts]")
            metrics['preloading_optimized'] = False
    else:
        feedback_items.append("⚠ Network prediction setting not found (possibly unchanged) [+0pts]")
        metrics['preloading_optimized'] = False
    
    # Check 2: Enhanced Safe Browsing (30 points - significant background data)
    enhanced_safe_browsing = prefs.get('safebrowsing', {}).get('enhanced', None)
    metrics['enhanced_safe_browsing'] = enhanced_safe_browsing
    
    if enhanced_safe_browsing is False:
        score += 30
        feedback_items.append("✓ Enhanced Safe Browsing disabled - Reduces background data [+30pts]")
        metrics['enhanced_features_limited'] = True
    elif enhanced_safe_browsing is True:
        feedback_items.append("✗ Enhanced Safe Browsing still enabled (uses background data) [+0pts]")
        metrics['enhanced_features_limited'] = False
    else:
        feedback_items.append("⚠ Enhanced Safe Browsing setting not found (may be default) [+0pts]")
        metrics['enhanced_features_limited'] = False
    
    # Check 3: Performance/Memory Saver Mode (20 points - indirect benefit)
    performance_mode = prefs.get('performance_tuning', {}).get(
        'high_efficiency_mode', {}
    ).get('state', None)
    metrics['performance_mode_state'] = performance_mode
    
    if performance_mode in [1, 2]:  # Various enabled states
        score += 20
        feedback_items.append(f"✓ Performance/Memory Saver mode enabled (state={performance_mode}) [+20pts]")
        metrics['performance_mode_enabled'] = True
    else:
        feedback_items.append("⚠ Performance/Memory Saver mode not enabled (optional optimization) [+0pts]")
        metrics['performance_mode_enabled'] = False
    
    # Check 4: Additional Data-Intensive Features (10 points total)
    additional_score = 0
    additional_details = []
    
    # DNS prefetching (3 points)
    dns_prefetch = prefs.get('dns_prefetching', {}).get('enabled', True)
    metrics['dns_prefetching_enabled'] = dns_prefetch
    if not dns_prefetch:
        additional_score += 3
        additional_details.append("DNS prefetching disabled [+3pts]")
    
    # Search suggestions (3 points)
    search_suggest = prefs.get('search', {}).get('suggest_enabled', True)
    metrics['search_suggest_enabled'] = search_suggest
    if not search_suggest:
        additional_score += 3
        additional_details.append("Search suggestions disabled [+3pts]")
    
    # Alternate error pages (4 points)
    alt_error_pages = prefs.get('alternate_error_pages', {}).get('enabled', True)
    metrics['alternate_error_pages_enabled'] = alt_error_pages
    if not alt_error_pages:
        additional_score += 4
        additional_details.append("Alternate error pages disabled [+4pts]")
    
    if additional_score > 0:
        score += additional_score
        feedback_items.append(f"✓ Additional optimizations: {', '.join(additional_details)} [+{additional_score}pts]")
    else:
        feedback_items.append("⚠ No additional minor optimizations applied [+0pts]")
    
    metrics['additional_optimizations_score'] = additional_score
    
    # Determine pass/fail (need 75% = 75 points minimum)
    passed = score >= 75
    
    # Build detailed feedback
    feedback = "Chrome Data Saver Configuration Verification\n"
    feedback += "=" * 50 + "\n\n"
    feedback += "\n".join(feedback_items)
    feedback += f"\n\n{'=' * 50}"
    feedback += f"\nTotal Score: {score}/{max_score}"
    feedback += f"\nPass Threshold: 75/100"
    
    if passed:
        feedback += "\n\n✅ PASSED: Data-saving configuration successfully applied!"
        feedback += "\nChrome is now optimized for slow/metered connections."
    else:
        feedback += "\n\n❌ FAILED: Insufficient data-saving optimizations."
        feedback += "\n\nTo pass, you need to achieve at least 75 points by:"
        feedback += "\n  • Disabling preloading (40pts) - Most important!"
        feedback += "\n  • Disabling Enhanced Safe Browsing (30pts)"
        feedback += "\n  • Enabling Memory Saver mode (20pts) - Optional but helpful"
        feedback += "\n  • Disabling other data-intensive features (10pts)"
        feedback += "\n\nNavigate to chrome://settings and look for:"
        feedback += "\n  • 'Privacy and security' → 'Cookies and other site data' → 'Preload pages'"
        feedback += "\n  • 'Privacy and security' → 'Security' → 'Safe Browsing'"
        feedback += "\n  • 'Performance' → 'Memory Saver'"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "metrics": metrics
    }


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for data_saver_setup@1 task.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }
    
    try:
        # Step 1: Get Preferences file from container
        logger.info("Retrieving Chrome Preferences file from container...")
        prefs, error_msg = get_preferences_file(copy_from_env)
        
        if prefs is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve Preferences file: {error_msg}\n\n"
                           f"This could mean Chrome didn't save settings, or the file couldn't be accessed."
            }
        
        logger.info("✓ Preferences file retrieved successfully")
        
        # Step 2: Verify data-saving settings
        logger.info("Analyzing data-saving settings...")
        result = verify_data_saver_settings(prefs)
        
        logger.info(f"Verification complete: passed={result['passed']}, score={result['score']}")
        
        # Clean up
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}\n\n"
                       f"An unexpected error occurred during verification. "
                       f"Please check that Chrome closed properly and settings were saved."
        }
