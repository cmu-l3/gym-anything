#!/usr/bin/env python3
"""
Verifier for Chrome Network Request Blocking Task (network_request_blocking@1)
Task: Configure Network Request Blocking in DevTools to block analytics, JPEGs, and CDN domain

Verification Strategy:
- Parse Chrome Preferences file
- Extract DevTools preferences for network request blocking
- Verify blocking is enabled
- Check that all three required patterns are present: *analytics*, *.jpg, *cdn.example.com*
- Validate patterns are properly formatted and enabled
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
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
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for network_request_blocking@1.
    
    Verifies that Network Request Blocking was configured in DevTools with three patterns:
    1. *analytics* - blocks analytics scripts
    2. *.jpg - blocks JPEG images
    3. *cdn.example.com* - blocks specific CDN domain
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), feedback (str), and details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Extract blocking configuration from Preferences
        blocking_config, error_msg = extract_blocking_config(copy_from_env)
        
        if blocking_config is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract blocking configuration: {error_msg}"
            }
        
        # Verify blocking configuration
        result = verify_blocking_patterns(blocking_config)
        
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


def extract_blocking_config(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract network request blocking configuration from Chrome Preferences.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (blocking_config: dict or None, error_message: str)
    """
    temp_file = None
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
            success, files, error = setup_chrome_verification(
                copy_from_env,
                ["Preferences"],
                user="ga",
                profile="Default"
            )
            
            if success:
                prefs = parse_preferences(files["Preferences"])
                if prefs:
                    blocking_config = extract_blocking_from_prefs(prefs)
                    cleanup_verification_temp()
                    return blocking_config, ""
                else:
                    logger.warning("Utility-based parsing returned empty preferences")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences.json",
            "/tmp/network_blocking_verification/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs:
            return None, "Could not load Preferences file from any known location"
        
        # Extract blocking configuration
        blocking_config = extract_blocking_from_prefs(prefs)
        
        return blocking_config, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting blocking config: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def extract_blocking_from_prefs(prefs: Dict) -> Dict:
    """
    Extract network request blocking configuration from parsed preferences.
    
    Args:
        prefs: Parsed Chrome Preferences dictionary
        
    Returns:
        Dictionary with 'enabled' and 'patterns' keys
    """
    # Navigate nested structure to extract DevTools preferences
    devtools = prefs.get('devtools', {})
    devtools_prefs = devtools.get('preferences', {})
    
    # Extract blocking enabled state
    blocking_enabled_str = devtools_prefs.get('network.requestBlockingEnabled', 'false')
    blocking_enabled = blocking_enabled_str.lower() == 'true'
    
    # Extract blocking patterns (stored as JSON string)
    patterns_str = devtools_prefs.get('network.requestBlockingPatterns', '[]')
    
    # Parse patterns JSON
    try:
        patterns = json.loads(patterns_str)
    except json.JSONDecodeError:
        logger.warning(f"Failed to parse blocking patterns: {patterns_str}")
        patterns = []
    
    logger.info(f"Extracted blocking config: enabled={blocking_enabled}, patterns={patterns}")
    
    return {
        'enabled': blocking_enabled,
        'patterns': patterns
    }


def verify_blocking_patterns(blocking_config: Dict) -> Dict[str, Any]:
    """
    Verify that blocking configuration meets task requirements.
    
    Required patterns:
    1. *analytics* - blocks analytics scripts
    2. *.jpg - blocks JPEG images
    3. *cdn.example.com* - blocks specific CDN domain
    
    Criteria (8 total, need 6+ for pass):
    1. DevTools was opened (inferred from preferences existing)
    2. Network tab accessed (inferred)
    3. Request blocking enabled
    4. Analytics pattern present
    5. Image pattern present
    6. Domain pattern present
    7. All patterns are enabled (not disabled)
    8. No extra/incorrect patterns (or reasonable extras allowed)
    
    Args:
        blocking_config: Dictionary with 'enabled' and 'patterns' keys
        
    Returns:
        Verification result with passed, score, and feedback
    """
    enabled = blocking_config.get('enabled', False)
    patterns = blocking_config.get('patterns', [])
    
    # Required patterns (normalized for comparison)
    required_patterns = {
        'analytics': '*analytics*',
        'jpg': '*.jpg',
        'cdn': '*cdn.example.com*'
    }
    
    # Track which patterns were found
    found_patterns = {
        'analytics': False,
        'jpg': False,
        'cdn': False
    }
    
    # Track all pattern details
    pattern_details = []
    
    # Analyze patterns
    for pattern in patterns:
        if isinstance(pattern, dict):
            url = pattern.get('url', '')
            pattern_enabled = pattern.get('enabled', True)
        elif isinstance(pattern, str):
            url = pattern
            pattern_enabled = True
        else:
            continue
        
        url_normalized = url.lower().strip()
        pattern_details.append({
            'url': url,
            'enabled': pattern_enabled
        })
        
        # Check if this matches a required pattern
        if pattern_enabled:
            if '*analytics*' in url_normalized:
                found_patterns['analytics'] = True
            if '*.jpg' in url_normalized:
                found_patterns['jpg'] = True
            if '*cdn.example.com*' in url_normalized:
                found_patterns['cdn'] = True
    
    # Criterion checks
    criteria = {
        'devtools_opened': len(patterns) > 0 or enabled,  # Inferred from any config
        'network_tab_accessed': len(patterns) > 0 or enabled,  # Inferred
        'blocking_enabled': enabled,
        'analytics_pattern': found_patterns['analytics'],
        'image_pattern': found_patterns['jpg'],
        'cdn_pattern': found_patterns['cdn'],
        'patterns_enabled': all(
            p.get('enabled', True) 
            for p in pattern_details 
            if any(req in p['url'].lower() for req in ['analytics', '.jpg', 'cdn.example.com'])
        ) if pattern_details else False,
        'reasonable_patterns': len(patterns) <= 10  # Not too many patterns
    }
    
    criteria_met = sum(criteria.values())
    total_criteria = len(criteria)
    
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 6/8 criteria
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Network Request Blocking Verification: {criteria_met}/{total_criteria} criteria met")
    feedback_parts.append("")
    
    # Individual criterion feedback
    if not criteria['devtools_opened']:
        feedback_parts.append("✗ DevTools does not appear to have been opened")
    else:
        feedback_parts.append("✓ DevTools was accessed")
    
    if not criteria['network_tab_accessed']:
        feedback_parts.append("✗ Network tab configuration not detected")
    else:
        feedback_parts.append("✓ Network tab accessed")
    
    if not criteria['blocking_enabled']:
        feedback_parts.append("✗ Network request blocking is NOT enabled")
        feedback_parts.append("  → You must check the 'Enable network request blocking' checkbox")
    else:
        feedback_parts.append("✓ Network request blocking is enabled")
    
    if not criteria['analytics_pattern']:
        feedback_parts.append("✗ Analytics blocking pattern (*analytics*) NOT found")
    else:
        feedback_parts.append("✓ Analytics pattern (*analytics*) present")
    
    if not criteria['image_pattern']:
        feedback_parts.append("✗ JPEG image blocking pattern (*.jpg) NOT found")
    else:
        feedback_parts.append("✓ Image pattern (*.jpg) present")
    
    if not criteria['cdn_pattern']:
        feedback_parts.append("✗ CDN domain pattern (*cdn.example.com*) NOT found")
    else:
        feedback_parts.append("✓ CDN pattern (*cdn.example.com*) present")
    
    if not criteria['patterns_enabled']:
        feedback_parts.append("⚠ Some required patterns are disabled")
    else:
        feedback_parts.append("✓ All patterns are enabled")
    
    if not criteria['reasonable_patterns']:
        feedback_parts.append(f"⚠ Too many patterns configured ({len(patterns)} patterns)")
    else:
        feedback_parts.append(f"✓ Reasonable number of patterns ({len(patterns)} patterns)")
    
    feedback_parts.append("")
    feedback_parts.append(f"Score: {score}% | {'PASSED ✓' if passed else 'FAILED ✗'}")
    
    if passed:
        feedback_parts.append("Excellent! Network request blocking configured correctly.")
    elif criteria_met >= 5:
        feedback_parts.append("Close! Check the missing patterns/settings above.")
    else:
        feedback_parts.append("Task incomplete. Please configure all three blocking patterns.")
    
    feedback = "\n".join(feedback_parts)
    
    # Log details
    logger.info(f"Verification complete:")
    logger.info(f"  Blocking enabled: {enabled}")
    logger.info(f"  Total patterns: {len(patterns)}")
    logger.info(f"  Analytics pattern: {found_patterns['analytics']}")
    logger.info(f"  JPG pattern: {found_patterns['jpg']}")
    logger.info(f"  CDN pattern: {found_patterns['cdn']}")
    logger.info(f"  Score: {score}%")
    logger.info(f"  Passed: {passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "blocking_enabled": enabled,
            "total_patterns": len(patterns),
            "patterns_found": found_patterns,
            "criteria": criteria,
            "pattern_details": pattern_details
        }
    }
