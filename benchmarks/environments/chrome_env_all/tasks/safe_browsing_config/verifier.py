#!/usr/bin/env python3
"""
Verifier for Chrome Safe Browsing Configuration Task (safe_browsing_config@1)
Task: Configure Chrome's Safe Browsing to Enhanced protection level

Verification Strategy:
- Copy Chrome Preferences file from container to host
- Parse JSON and extract safebrowsing configuration
- Validate that both safebrowsing.enabled and safebrowsing.enhanced are true
- Provide multi-criteria scoring with detailed feedback

Scoring Criteria:
1. Safe Browsing enabled (safebrowsing.enabled = true) - 40 points
2. Enhanced protection active (safebrowsing.enhanced = true) - 50 points  
3. Scout reporting configured (safebrowsing.scout_reporting_enabled = true) - 10 points

Pass threshold: 75% (requires both enabled and enhanced to be true)
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

# Add utils to path
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
    
    def cleanup_verification_temp():
        """Fallback cleanup function"""
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for safe_browsing_config@1.
    
    Verifies that Chrome's Safe Browsing has been configured to Enhanced protection.
    
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
            "feedback": "Copy function not available in environment - cannot verify task"
        }

    try:
        # Extract Safe Browsing configuration from Preferences
        sb_config, error_msg = extract_safe_browsing_config(copy_from_env)
        
        if sb_config is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract Safe Browsing configuration: {error_msg}"
            }
        
        # Validate Safe Browsing configuration
        result = validate_safe_browsing_enhanced(sb_config)
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_safe_browsing_config(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract Safe Browsing configuration from Chrome Preferences file.
    
    Tries multiple approaches:
    1. Use chrome_verification_utils if available
    2. Copy from /tmp/chrome_preferences_safebrowsing.json (export script location)
    3. Copy directly from Chrome profile directories
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (safebrowsing_config: dict or None, error_message: str)
    """
    temp_file = None
    
    try:
        # Approach 1: Try using verification utilities
        if UTILS_AVAILABLE:
            try:
                success, files, error = setup_chrome_verification(
                    copy_from_env,
                    ["Preferences"],
                    user="ga",
                    profile="Default"
                )
                
                if success:
                    prefs_data = parse_preferences(files["Preferences"])
                    if prefs_data:
                        sb_config = prefs_data.get('safebrowsing', {})
                        
                        # Handle alternative location (some Chrome versions store under 'profile')
                        if not sb_config:
                            profile = prefs_data.get('profile', {})
                            sb_config = profile.get('safebrowsing', {})
                        
                        logger.info(f"Extracted Safe Browsing config via utilities: {sb_config}")
                        return sb_config, ""
                else:
                    logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
            except Exception as e:
                logger.warning(f"Error using verification utilities: {e}")
        
        # Approach 2: Manual extraction from multiple possible locations
        container_paths = [
            "/tmp/chrome_preferences_safebrowsing.json",  # Export script location
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",  # Primary profile
            "/home/ga/.config/google-chrome/Default/Preferences"  # Alternative profile
        ]
        
        for container_path in container_paths:
            try:
                temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
                temp_file.close()
                
                logger.info(f"Attempting to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully and has content
                if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
                    logger.debug(f"File not found or empty: {container_path}")
                    os.unlink(temp_file.name)
                    continue
                
                # Parse JSON
                with open(temp_file.name, 'r', encoding='utf-8') as f:
                    prefs_data = json.load(f)
                
                # Navigate nested structure to extract Safe Browsing config
                sb_config = prefs_data.get('safebrowsing', {})
                
                # Handle alternative structure (profile.safebrowsing)
                if not sb_config:
                    profile = prefs_data.get('profile', {})
                    sb_config = profile.get('safebrowsing', {})
                
                logger.info(f"Successfully extracted Safe Browsing config from: {container_path}")
                logger.info(f"Config: {sb_config}")
                
                # Clean up temp file
                os.unlink(temp_file.name)
                
                return sb_config, ""
                
            except json.JSONDecodeError as e:
                logger.warning(f"JSON parse error for {container_path}: {e}")
                if temp_file and os.path.exists(temp_file.name):
                    os.unlink(temp_file.name)
                continue
            except Exception as e:
                logger.debug(f"Failed to copy/parse from {container_path}: {e}")
                if temp_file and os.path.exists(temp_file.name):
                    os.unlink(temp_file.name)
                continue
        
        # If we get here, all attempts failed
        return None, "Could not copy or parse Preferences file from any known location"
        
    except Exception as e:
        logger.error(f"Error extracting Safe Browsing config: {e}", exc_info=True)
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
        return None, f"Unexpected error: {str(e)}"


def validate_safe_browsing_enhanced(sb_config: Dict) -> Dict[str, Any]:
    """
    Validate that Enhanced Safe Browsing protection is properly configured.
    
    Checks multiple criteria:
    1. safebrowsing.enabled = true (Safe Browsing is active)
    2. safebrowsing.enhanced = true (Enhanced protection mode)
    3. safebrowsing.scout_reporting_enabled = true (data sharing for Enhanced)
    
    Args:
        sb_config: Dictionary containing Safe Browsing configuration
        
    Returns:
        Dict with passed, score, feedback, and details
    """
    # Extract settings with explicit None handling
    sb_enabled = sb_config.get('enabled')
    sb_enhanced = sb_config.get('enhanced')
    scout_reporting = sb_config.get('scout_reporting_enabled')
    
    logger.info(f"Validating Safe Browsing configuration:")
    logger.info(f"  - enabled: {sb_enabled} (type: {type(sb_enabled).__name__})")
    logger.info(f"  - enhanced: {sb_enhanced} (type: {type(sb_enhanced).__name__})")
    logger.info(f"  - scout_reporting_enabled: {scout_reporting} (type: {type(scout_reporting).__name__})")
    
    # Build criteria results
    criteria = {
        "safe_browsing_enabled": False,
        "enhanced_protection": False,
        "scout_reporting": False
    }
    
    feedback_parts = []
    score = 0
    
    # Criterion 1: Safe Browsing must be enabled (40 points)
    if sb_enabled is True:
        criteria["safe_browsing_enabled"] = True
        score += 40
        feedback_parts.append("✓ Safe Browsing is enabled")
    elif sb_enabled is False:
        feedback_parts.append("✗ Safe Browsing is explicitly disabled")
    elif sb_enabled is None:
        feedback_parts.append("⚠ Safe Browsing status not set in preferences (may use default)")
    else:
        feedback_parts.append(f"⚠ Safe Browsing has unexpected value: {sb_enabled}")
    
    # Criterion 2: Enhanced protection must be active (50 points)
    if sb_enhanced is True:
        criteria["enhanced_protection"] = True
        score += 50
        feedback_parts.append("✓ Enhanced protection mode is ACTIVE")
    elif sb_enhanced is False:
        feedback_parts.append("✗ Enhanced protection is disabled (Standard protection mode)")
    elif sb_enhanced is None:
        feedback_parts.append("⚠ Enhanced protection not set (defaults to Standard protection)")
    else:
        feedback_parts.append(f"⚠ Enhanced protection has unexpected value: {sb_enhanced}")
    
    # Criterion 3: Scout reporting (bonus, 10 points)
    if scout_reporting is True:
        criteria["scout_reporting"] = True
        score += 10
        feedback_parts.append("✓ Enhanced protection data sharing (scout reporting) is configured")
    elif scout_reporting is False:
        feedback_parts.append("ℹ Scout reporting disabled (Enhanced protection may still work)")
    elif scout_reporting is None:
        # This is often not set and is OK
        pass
    
    # Determine pass/fail
    # Must have both Safe Browsing enabled AND Enhanced protection active
    passed = (sb_enabled is True) and (sb_enhanced is True) and (score >= 75)
    
    # Build detailed feedback
    feedback = "\n".join(feedback_parts)
    feedback += "\n\nConfiguration details:"
    feedback += f"\n  • safebrowsing.enabled: {sb_enabled}"
    feedback += f"\n  • safebrowsing.enhanced: {sb_enhanced}"
    feedback += f"\n  • scout_reporting_enabled: {scout_reporting}"
    feedback += f"\n\nScore: {score}/100"
    
    if passed:
        feedback += "\n\n✅ Task completed successfully! Enhanced Safe Browsing protection is active."
    else:
        feedback += "\n\n❌ Task incomplete. Enhanced protection is not properly configured."
        feedback += "\n\nExpected: safebrowsing.enabled=true AND safebrowsing.enhanced=true"
        
        if sb_enabled is not True:
            feedback += "\n  → Navigate to chrome://settings/security"
            feedback += "\n  → Locate 'Safe Browsing' section"
            feedback += "\n  → Enable Safe Browsing (should be on by default)"
        
        if sb_enhanced is not True:
            feedback += "\n  → In the 'Safe Browsing' section, select 'Enhanced protection'"
            feedback += "\n  → This provides the strongest security with proactive warnings"
    
    logger.info(f"Validation result: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria": criteria,
            "safe_browsing_enabled": sb_enabled,
            "enhanced_protection": sb_enhanced,
            "scout_reporting": scout_reporting,
            "config_found": bool(sb_config)
        }
    }
