#!/usr/bin/env python3
"""
Verifier for Chrome Media Autoplay Blocking Task (autoplay_blocking@1)
Task: Configure Chrome to block auto-playing media on a disruptive news website

Verification Strategy:
- Parse Chrome Preferences file (JSON)
- Navigate to profile.content_settings.exceptions.sound (or autoplay)
- Verify target domain appears with setting value 2 (BLOCK)
- Check pattern format matches Chrome's URL pattern conventions
- Validate recent modification timestamp exists

Scoring Criteria (4 total, need 3+ to pass):
1. Domain exception exists in sound/autoplay settings
2. Setting value is 2 (BLOCK) not 1 (ALLOW) or 0 (ASK)
3. Recent modification timestamp present
4. Proper Chrome URL pattern format
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../utils'))
try:
    from chrome_verification_utils import (
        parse_preferences,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def parse_preferences(path):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for autoplay_blocking@1 task.
    
    Verifies that site-specific autoplay blocking has been configured in Chrome.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get target domain from metadata or use default
        target_domain = get_target_domain(copy_from_env, task_info)
        logger.info(f"Verifying autoplay blocking for domain: {target_domain}")
        
        # Get Chrome Preferences file
        prefs_data = get_preferences_file(copy_from_env)
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to access Chrome Preferences file"
            }
        
        # Verify autoplay blocking configuration
        verification_result = verify_autoplay_blocked(prefs_data, target_domain)
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return verification_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_target_domain(copy_from_env, task_info) -> str:
    """
    Extract target domain from task metadata or metadata file.
    
    Args:
        copy_from_env: Function to copy files from container
        task_info: Task configuration dict
        
    Returns:
        Target domain string (e.g., "bbc.com")
    """
    # Try to get from task metadata first
    default_domain = task_info.get('metadata', {}).get('target_domain', 'bbc.com')
    
    # Try to get actual visited domain from export metadata
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        copy_from_env("/tmp/target_domain.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            domain = f.read().strip()
        
        os.unlink(temp_file.name)
        
        if domain and domain != "unknown":
            logger.info(f"Using actual visited domain: {domain}")
            return domain
    except Exception as e:
        logger.debug(f"Could not get actual domain from metadata: {e}")
    
    logger.info(f"Using default domain: {default_domain}")
    return default_domain


def get_preferences_file(copy_from_env) -> Optional[Dict]:
    """
    Copy and parse Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed preferences dict or None on failure
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_paths = [
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        for container_path in prefs_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
                    
                    # Parse JSON
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    
                    os.unlink(temp_file.name)
                    return prefs
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # If we get here, all attempts failed
        if temp_file and os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        
        logger.error("Could not access Preferences file from any known location")
        return None
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse Preferences JSON: {e}")
        if temp_file and os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        return None
    except Exception as e:
        logger.error(f"Error getting Preferences file: {e}")
        if temp_file and os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        return None


def verify_autoplay_blocked(prefs: Dict, target_domain: str) -> Dict[str, Any]:
    """
    Verify that autoplay has been blocked for the target domain.
    
    Checks Chrome Preferences structure:
    - profile.content_settings.exceptions.sound (autoplay is stored here)
    - Looks for domain patterns like "https://bbc.com:443,*" or "[*.]bbc.com,*"
    - Verifies setting value is 2 (BLOCK)
    
    Args:
        prefs: Parsed Chrome Preferences dict
        target_domain: Domain to check (e.g., "bbc.com")
        
    Returns:
        Verification result dict
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Navigate to content settings exceptions
    try:
        content_settings = prefs.get('profile', {}).get('content_settings', {})
        exceptions = content_settings.get('exceptions', {})
        
        # Autoplay settings are typically stored under 'sound'
        sound_exceptions = exceptions.get('sound', {})
        
        logger.info(f"Found {len(sound_exceptions)} sound/autoplay exception(s)")
        
        # Criterion 1: Domain exception exists
        domain_pattern = None
        domain_config = None
        
        # Clean up target domain for matching (remove www., protocols, etc.)
        clean_domain = target_domain.replace('www.', '').split('/')[0].split(':')[0].lower()
        
        for pattern, config in sound_exceptions.items():
            # Chrome stores patterns like:
            # "https://bbc.com:443,*"
            # "[*.]bbc.com,*"
            # "https://www.bbc.com:443,*"
            if clean_domain in pattern.lower():
                domain_pattern = pattern
                domain_config = config
                criteria_met += 1
                feedback_parts.append(f"✓ Domain exception found: {pattern}")
                logger.info(f"Found matching pattern: {pattern}")
                break
        
        if not domain_pattern:
            feedback_parts.append(f"✗ No site-specific setting found for {target_domain}")
            logger.warning(f"No domain exception found for {target_domain}")
            logger.info(f"Available patterns: {list(sound_exceptions.keys())}")
        
        # Criterion 2: Setting value is BLOCK (2)
        if domain_config:
            setting_value = domain_config.get('setting')
            logger.info(f"Setting value: {setting_value}")
            
            if setting_value == 2:
                criteria_met += 1
                feedback_parts.append("✓ Autoplay is BLOCKED (setting=2)")
            elif setting_value == 1:
                feedback_parts.append("✗ Autoplay is ALLOWED (setting=1), should be BLOCKED (2)")
            elif setting_value == 0:
                feedback_parts.append("✗ Autoplay is set to ASK (setting=0), should be BLOCKED (2)")
            else:
                feedback_parts.append(f"✗ Unknown setting value: {setting_value}")
        else:
            feedback_parts.append("✗ Cannot check setting value (no domain exception found)")
        
        # Criterion 3: Recent modification timestamp
        if domain_config:
            last_modified = domain_config.get('last_modified')
            if last_modified:
                criteria_met += 1
                feedback_parts.append(f"✓ Setting has valid timestamp: {last_modified}")
            else:
                feedback_parts.append("✗ No modification timestamp found")
        else:
            feedback_parts.append("✗ Cannot check timestamp (no domain exception found)")
        
        # Criterion 4: Proper pattern format
        if domain_pattern:
            # Check if pattern matches Chrome's expected formats
            # Valid formats: "https://domain:443,*" or "[*.]domain,*"
            valid_format = False
            if re.match(r'https?://[^,]+,\*', domain_pattern):
                valid_format = True
            elif re.match(r'\[\*\.\][^,]+,\*', domain_pattern):
                valid_format = True
            elif '://' in domain_pattern or '[*.]' in domain_pattern:
                valid_format = True
            
            if valid_format:
                criteria_met += 1
                feedback_parts.append("✓ Pattern format is valid")
            else:
                feedback_parts.append(f"⚠ Pattern format unusual: {domain_pattern}")
                criteria_met += 0.5  # Partial credit
        else:
            feedback_parts.append("✗ Cannot validate pattern format (no domain exception found)")
        
    except Exception as e:
        logger.error(f"Error parsing content settings: {e}", exc_info=True)
        feedback_parts.append(f"✗ Error parsing Preferences structure: {str(e)}")
    
    # Calculate score and pass/fail
    score = int((criteria_met / total_criteria) * 100)
    passed = criteria_met >= 3  # Need at least 3 out of 4 criteria
    
    # Build final feedback
    feedback_header = f"Autoplay Blocking Verification for {target_domain}"
    feedback_summary = f"Criteria met: {criteria_met:.1f}/{total_criteria}"
    feedback_body = "\n".join(feedback_parts)
    
    if passed:
        feedback_conclusion = "✅ Task completed successfully - autoplay blocked for site"
    else:
        feedback_conclusion = "❌ Task incomplete - autoplay not properly blocked"
    
    feedback = f"{feedback_header}\n{feedback_summary}\n\n{feedback_body}\n\n{feedback_conclusion}"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met:.1f}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "domain_pattern": domain_pattern,
            "target_domain": target_domain,
            "setting_value": domain_config.get('setting') if domain_config else None
        }
    }
