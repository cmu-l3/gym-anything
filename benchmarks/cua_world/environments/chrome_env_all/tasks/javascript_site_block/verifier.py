#!/usr/bin/env python3
"""
Verifier for Chrome Site-Specific JavaScript Control Task (javascript_site_block@1)
Task: Block JavaScript execution on ads.example.com using Chrome's site settings

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and navigate to profile.content_settings.exceptions.javascript
- Search for rules containing the target site (ads.example.com)
- Verify the setting value is 2 (CONTENT_SETTING_BLOCK)
- Validate rule structure and proper configuration
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../utils'))
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


# Chrome content setting values
CONTENT_SETTING_DEFAULT = 0
CONTENT_SETTING_ALLOW = 1
CONTENT_SETTING_BLOCK = 2
CONTENT_SETTING_ASK = 3
CONTENT_SETTING_SESSION_ONLY = 4


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for javascript_site_block@1 task.
    
    Verifies that JavaScript blocking rule exists for ads.example.com in Chrome Preferences.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information (contains target_site)
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }
    
    # Get target site from task_info or use default
    target_site = task_info.get('target_site', 'ads.example.com')
    
    try:
        # Extract JavaScript blocking rules from Preferences
        js_rules, prefs, error_msg = extract_javascript_rules(copy_from_env)
        
        if js_rules is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract JavaScript rules: {error_msg}"
            }
        
        # Verify the blocking rule exists and is correct
        verification_result = verify_javascript_block_rule(js_rules, target_site, prefs)
        
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


def extract_javascript_rules(copy_from_env) -> Tuple[Optional[Dict], Optional[Dict], str]:
    """
    Extract JavaScript exception rules from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (js_rules: dict or None, full_prefs: dict or None, error_message: str)
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
                prefs_path = files["Preferences"]
                prefs = parse_preferences(prefs_path)
                
                # Navigate to JavaScript exceptions
                js_rules = prefs.get('profile', {}) \
                               .get('content_settings', {}) \
                               .get('exceptions', {}) \
                               .get('javascript', {})
                
                logger.info(f"Successfully extracted JavaScript rules using utilities")
                return js_rules, prefs, ""
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    logger.info(f"Successfully copied and parsed from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs is None:
            return None, None, "Could not copy Preferences file from any known location"
        
        # Navigate nested structure to extract JavaScript rules
        js_rules = prefs.get('profile', {}) \
                       .get('content_settings', {}) \
                       .get('exceptions', {}) \
                       .get('javascript', {})
        
        logger.info(f"Extracted JavaScript rules: {len(js_rules)} rule(s) found")
        
        return js_rules, prefs, ""
        
    except json.JSONDecodeError as e:
        return None, None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, None, f"Error extracting JavaScript rules: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_javascript_block_rule(js_rules: Dict, target_site: str, full_prefs: Dict) -> Dict[str, Any]:
    """
    Verify that a JavaScript blocking rule exists for the target site.
    
    Checks:
    1. Rule pattern contains target site
    2. Setting value is 2 (CONTENT_SETTING_BLOCK)
    3. Rule has proper structure (primary_pattern, last_modified)
    4. No conflicting allow rules for same site
    
    Args:
        js_rules: Dictionary of JavaScript exception rules from Preferences
        target_site: Target site to check (e.g., "ads.example.com")
        full_prefs: Full preferences dict for additional context
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    if not js_rules:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No JavaScript content settings found. Please navigate to chrome://settings/content/javascript and add '{target_site}' to the blocked list.",
            "details": {
                "rules_found": 0,
                "block_rule_exists": False
            }
        }
    
    logger.info(f"Checking {len(js_rules)} JavaScript rule(s) for target site: {target_site}")
    
    # Search for rules containing the target site
    matching_rules = []
    block_rule_found = False
    allow_rule_found = False
    matched_pattern = None
    matched_rule = None
    
    for pattern, rule in js_rules.items():
        pattern_lower = pattern.lower()
        target_lower = target_site.lower()
        
        # Check if pattern contains the target site
        if target_lower in pattern_lower:
            matching_rules.append((pattern, rule))
            logger.info(f"Found matching pattern: {pattern}")
            logger.info(f"  Rule details: {json.dumps(rule, indent=2)}")
            
            setting = rule.get('setting')
            
            if setting == CONTENT_SETTING_BLOCK:
                block_rule_found = True
                matched_pattern = pattern
                matched_rule = rule
            elif setting == CONTENT_SETTING_ALLOW:
                allow_rule_found = True
    
    # Calculate score and generate feedback based on findings
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Block rule exists
    if block_rule_found:
        criteria_met += 1
        feedback_parts.append(f"✓ JavaScript block rule found for '{target_site}'")
        feedback_parts.append(f"  Pattern: {matched_pattern}")
    else:
        feedback_parts.append(f"✗ No JavaScript block rule found for '{target_site}'")
        if len(matching_rules) > 0:
            feedback_parts.append(f"  Found {len(matching_rules)} matching rule(s) but none are blocking")
        else:
            feedback_parts.append(f"  No rules found containing '{target_site}'")
    
    # Criterion 2: Correct setting value
    if block_rule_found and matched_rule:
        setting_value = matched_rule.get('setting')
        if setting_value == CONTENT_SETTING_BLOCK:
            criteria_met += 1
            feedback_parts.append(f"✓ Setting value correct: {setting_value} (CONTENT_SETTING_BLOCK)")
        else:
            feedback_parts.append(f"✗ Setting value incorrect: {setting_value} (expected {CONTENT_SETTING_BLOCK})")
    
    # Criterion 3: Rule structure validation
    if block_rule_found and matched_rule:
        has_primary_pattern = 'primary_pattern' in matched_rule
        has_last_modified = 'last_modified' in matched_rule
        
        if has_primary_pattern and has_last_modified:
            criteria_met += 1
            feedback_parts.append(f"✓ Rule structure valid (has primary_pattern and last_modified)")
        else:
            missing = []
            if not has_primary_pattern:
                missing.append('primary_pattern')
            if not has_last_modified:
                missing.append('last_modified')
            feedback_parts.append(f"⚠ Rule structure incomplete (missing: {', '.join(missing)})")
            criteria_met += 0.5  # Partial credit
    
    # Criterion 4: No conflicting allow rules
    if not allow_rule_found:
        criteria_met += 1
        feedback_parts.append(f"✓ No conflicting allow rules for '{target_site}'")
    else:
        feedback_parts.append(f"⚠ Warning: Allow rule also exists for '{target_site}' (may conflict)")
        criteria_met += 0.5  # Partial credit if block rule exists
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Add summary to feedback
    feedback_parts.append("")
    feedback_parts.append(f"{'='*50}")
    feedback_parts.append(f"Criteria met: {criteria_met:.1f}/{total_criteria}")
    feedback_parts.append(f"Final score: {score}%")
    feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
    
    if not passed and not block_rule_found:
        feedback_parts.append("")
        feedback_parts.append("To complete this task:")
        feedback_parts.append("1. Open Chrome settings (chrome://settings)")
        feedback_parts.append("2. Navigate to Privacy and security > Site Settings > JavaScript")
        feedback_parts.append("3. Click 'Add' next to 'Not allowed to use JavaScript'")
        feedback_parts.append(f"4. Enter 'https://{target_site}' and click 'Add'")
    
    feedback = "\n".join(feedback_parts)
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "rules_found": len(js_rules),
            "matching_rules": len(matching_rules),
            "block_rule_exists": block_rule_found,
            "allow_rule_exists": allow_rule_found,
            "matched_pattern": matched_pattern,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
