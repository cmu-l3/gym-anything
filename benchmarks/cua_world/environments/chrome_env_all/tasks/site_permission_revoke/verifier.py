#!/usr/bin/env python3
"""
Verifier for Chrome Site Permission Management Task (site_permission_revoke@1)
Task: Revoke notification permission for spam-sending news site while preserving other permissions

Verification Strategy:
- Copy Chrome Preferences file from container (before and after states)
- Parse JSON and navigate to profile.content_settings.exceptions.notifications
- Verify target site's permission was revoked (setting changed to 2 or entry removed)
- Validate that ALL other sites' permissions remain unchanged
- Handle Chrome's various URL pattern formats ([*.]example.com, https://example.com:443, etc.)
- Provide detailed multi-criteria feedback
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for site_permission_revoke@1.
    
    Verifies:
    1. Target site permission revoked (setting = 2 or entry removed)
    2. Target moved to block list (or removed from allow list)
    3. Other sites' permissions preserved (zero unintended changes)
    4. Correct permission type modified (notifications, not camera/location)
    5. Preferences file integrity maintained (valid JSON, no corruption)
    
    Scoring:
    - 100%: All 5 criteria met (perfect surgical revocation)
    - 80-99%: 4/5 criteria met (successful with minor issues)
    - 60-79%: 3/5 criteria met (partial success)
    - <60%: <3 criteria met (task failed)
    
    Pass threshold: 80% (requires 4 out of 5 criteria)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    try:
        # Load before and after preference states
        prefs_before = load_preferences_file(copy_from_env, "before")
        prefs_after = load_preferences_file(copy_from_env, "after")
        
        if prefs_after is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not load Chrome Preferences file (after state). Ensure Chrome was closed properly."
            }
        
        # Perform verification
        result = verify_permission_revocation(
            prefs_before=prefs_before,
            prefs_after=prefs_after,
            target_site="news-daily-times.example"
        )
        
        # Cleanup
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


def load_preferences_file(copy_from_env, state: str) -> Optional[Dict]:
    """
    Load Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        state: "before" or "after" to load respective state
        
    Returns:
        Parsed JSON dict or None if failed
    """
    temp_file = None
    
    try:
        # Determine which file to load
        if state == "before":
            container_paths = ["/tmp/preferences_before_task.json"]
        else:  # after
            container_paths = [
                "/tmp/preferences_after_task.json",
                "/home/ga/.config/google-chrome-cdp/Default/Preferences",
                "/home/ga/.config/google-chrome/Default/Preferences"
            ]
        
        # Try each possible location
        for container_path in container_paths:
            try:
                temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
                temp_path = temp_file.name
                temp_file.close()
                
                logger.info(f"Trying to copy {state} preferences from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    
                    os.unlink(temp_path)
                    logger.info(f"✓ Successfully loaded {state} preferences from: {container_path}")
                    return prefs
                else:
                    os.unlink(temp_path)
                    
            except Exception as e:
                logger.debug(f"Failed to load from {container_path}: {e}")
                if temp_file and os.path.exists(temp_path):
                    os.unlink(temp_path)
                continue
        
        # If we're here, all attempts failed
        if state == "before":
            logger.warning("Could not load 'before' state - verification will be less precise")
            return None
        else:
            logger.error("Could not load 'after' state from any location")
            return None
            
    except Exception as e:
        logger.error(f"Error loading preferences: {e}")
        return None


def verify_permission_revocation(prefs_before: Optional[Dict], prefs_after: Dict, 
                                 target_site: str) -> Dict[str, Any]:
    """
    Verify that notification permission was correctly revoked for target site.
    
    Args:
        prefs_before: Preferences before task (may be None)
        prefs_after: Preferences after task
        target_site: Domain to check (e.g., "news-daily-times.example")
        
    Returns:
        Dict with verification results
    """
    criteria_met = []
    criteria_scores = []
    feedback_parts = []
    
    # Extract notification permissions
    notif_before = extract_notifications(prefs_before) if prefs_before else {}
    notif_after = extract_notifications(prefs_after)
    
    if not notif_after:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not find notifications permissions in Preferences file"
        }
    
    logger.info(f"Notifications before task: {len(notif_before)} entries")
    logger.info(f"Notifications after task: {len(notif_after)} entries")
    
    # Criterion 1: Target site permission revoked
    target_revoked, revoke_details = check_target_site_revoked(
        notif_before, notif_after, target_site
    )
    
    if target_revoked:
        criteria_met.append("target_site_blocked")
        criteria_scores.append(20)
        feedback_parts.append(f"✓ Target site permission revoked: {revoke_details}")
    else:
        criteria_scores.append(0)
        feedback_parts.append(f"✗ Target site permission NOT revoked: {revoke_details}")
    
    # Criterion 2: Target moved to block list (or removed from allow list)
    in_block_list, block_details = check_target_in_block_list(notif_after, target_site)
    
    if in_block_list or target_revoked:  # Either blocked or removed is acceptable
        criteria_met.append("moved_to_block_list")
        criteria_scores.append(20)
        feedback_parts.append(f"✓ {block_details}")
    else:
        criteria_scores.append(0)
        feedback_parts.append(f"✗ {block_details}")
    
    # Criterion 3: Other sites preserved
    unintended_changes = count_unintended_changes(notif_before, notif_after, target_site)
    
    if unintended_changes == 0:
        criteria_met.append("other_sites_preserved")
        criteria_scores.append(20)
        feedback_parts.append(f"✓ Other sites' permissions preserved (0 unintended changes)")
    else:
        criteria_scores.append(max(0, 20 - unintended_changes * 5))  # Partial credit
        feedback_parts.append(f"✗ {unintended_changes} unintended permission change(s) detected")
    
    # Criterion 4: Correct permission type (notifications only)
    other_perms_ok = check_other_permission_types_unchanged(prefs_before, prefs_after)
    
    if other_perms_ok:
        criteria_met.append("correct_permission_type")
        criteria_scores.append(20)
        feedback_parts.append(f"✓ Other permission types (camera, location, etc.) unchanged")
    else:
        criteria_scores.append(0)
        feedback_parts.append(f"✗ Other permission types were modified (should only change notifications)")
    
    # Criterion 5: Preferences file valid
    try:
        json.dumps(prefs_after)  # Test if it's valid JSON
        criteria_met.append("preferences_file_valid")
        criteria_scores.append(20)
        feedback_parts.append(f"✓ Preferences file integrity maintained (valid JSON)")
    except:
        criteria_scores.append(0)
        feedback_parts.append(f"✗ Preferences file corrupted or malformed")
    
    # Calculate final score
    score = sum(criteria_scores)
    passed = score >= 80  # Need 4/5 criteria (80%)
    
    # Build comprehensive feedback
    feedback = "=== Site Permission Revocation Verification ===\n\n"
    feedback += f"Target: {target_site}\n"
    feedback += f"Criteria met: {len(criteria_met)}/5\n"
    feedback += f"Score: {score}/100\n\n"
    feedback += "Detailed Results:\n"
    feedback += "\n".join(f"  {fp}" for fp in feedback_parts)
    feedback += f"\n\n{'='*50}\n"
    
    if passed:
        feedback += "✅ TASK PASSED - Permission successfully revoked with minimal side effects"
    else:
        feedback += "❌ TASK FAILED - Permission not properly revoked or significant issues detected"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "target_revoked": target_revoked,
            "unintended_changes": unintended_changes,
            "in_block_list": in_block_list
        }
    }


def extract_notifications(prefs: Optional[Dict]) -> Dict[str, Any]:
    """Extract notifications permissions from preferences."""
    if not prefs:
        return {}
    
    try:
        return prefs.get('profile', {}) \
                    .get('content_settings', {}) \
                    .get('exceptions', {}) \
                    .get('notifications', {})
    except:
        return {}


def is_pattern_match(pattern: str, target: str) -> bool:
    """
    Check if Chrome permission pattern matches target site.
    
    Handles patterns like:
    - https://example.com:443,*
    - [*.]example.com
    - https://[*.]example.com:443,*
    
    Args:
        pattern: Chrome's permission pattern
        target: Target domain (e.g., "news-daily-times.example")
        
    Returns:
        True if pattern matches target
    """
    # Normalize both strings
    pattern_lower = pattern.lower()
    target_lower = target.lower()
    
    # Remove protocol prefixes
    pattern_clean = pattern_lower.replace('https://', '').replace('http://', '')
    pattern_clean = pattern_clean.replace('[*.]', '')  # Remove wildcard syntax
    
    # Remove port and wildcards
    pattern_clean = re.sub(r':\d+,?\*?', '', pattern_clean)  # Remove :443,* or :443
    pattern_clean = pattern_clean.rstrip(',*')
    
    # Check if target domain is in the pattern
    return target_lower in pattern_clean or pattern_clean in target_lower


def check_target_site_revoked(notif_before: Dict, notif_after: Dict, 
                               target_site: str) -> Tuple[bool, str]:
    """
    Check if target site's permission was revoked.
    
    Returns:
        Tuple of (revoked: bool, details: str)
    """
    # Find target in before state
    before_pattern = None
    before_setting = None
    
    for pattern, data in notif_before.items():
        if is_pattern_match(pattern, target_site):
            before_pattern = pattern
            before_setting = data.get('setting')
            break
    
    if not before_pattern:
        return False, f"Target site '{target_site}' was not found in before state (cannot verify)"
    
    if before_setting != 1:  # Should have been ALLOW (1) initially
        return False, f"Target site was not initially allowed (setting={before_setting})"
    
    # Find target in after state
    after_pattern = None
    after_setting = None
    
    for pattern, data in notif_after.items():
        if is_pattern_match(pattern, target_site):
            after_pattern = pattern
            after_setting = data.get('setting')
            break
    
    # Check if revoked
    if not after_pattern:
        # Entry removed completely (acceptable)
        return True, f"Entry removed from permissions (was ALLOW, now gone)"
    
    if after_setting == 2:  # BLOCK
        return True, f"Permission changed from ALLOW to BLOCK"
    
    if after_setting == 0:  # ASK
        return True, f"Permission changed from ALLOW to ASK (also acceptable)"
    
    # Still allowed
    return False, f"Permission still set to ALLOW (setting={after_setting})"


def check_target_in_block_list(notif_after: Dict, target_site: str) -> Tuple[bool, str]:
    """
    Check if target site is in the block list.
    
    Returns:
        Tuple of (in_block_list: bool, details: str)
    """
    for pattern, data in notif_after.items():
        if is_pattern_match(pattern, target_site):
            setting = data.get('setting')
            if setting == 2:
                return True, f"Target site explicitly blocked (setting=2)"
            elif setting == 1:
                return False, f"Target site still in allow list (setting=1)"
            else:
                return False, f"Target site has unexpected setting: {setting}"
    
    # Not found in after state
    return True, f"Target site removed from allow list (entry deleted)"


def count_unintended_changes(notif_before: Dict, notif_after: Dict, 
                             target_site: str) -> int:
    """
    Count how many non-target sites had their permissions changed.
    
    Returns:
        Number of unintended changes
    """
    if not notif_before:
        # Can't count changes without before state
        logger.warning("No before state available, cannot count unintended changes")
        return 0
    
    unintended = 0
    
    # Check all sites that were in before state
    all_patterns = set(list(notif_before.keys()) + list(notif_after.keys()))
    
    for pattern in all_patterns:
        # Skip the target site
        if is_pattern_match(pattern, target_site):
            continue
        
        before_setting = notif_before.get(pattern, {}).get('setting')
        after_setting = notif_after.get(pattern, {}).get('setting')
        
        if before_setting != after_setting:
            unintended += 1
            logger.warning(f"Unintended change detected for {pattern}: {before_setting} → {after_setting}")
    
    return unintended


def check_other_permission_types_unchanged(prefs_before: Optional[Dict], 
                                           prefs_after: Dict) -> bool:
    """
    Check that other permission types (camera, location, etc.) weren't modified.
    
    Returns:
        True if other permissions unchanged
    """
    if not prefs_before:
        # Can't verify without before state, assume OK
        return True
    
    try:
        exceptions_before = prefs_before.get('profile', {}) \
                                       .get('content_settings', {}) \
                                       .get('exceptions', {})
        exceptions_after = prefs_after.get('profile', {}) \
                                      .get('content_settings', {}) \
                                      .get('exceptions', {})
        
        # Check important permission types (excluding notifications)
        permission_types = [
            'geolocation', 
            'media_stream_camera', 
            'media_stream_mic',
            'cookies',
            'images',
            'javascript',
            'popups'
        ]
        
        for perm_type in permission_types:
            before = exceptions_before.get(perm_type, {})
            after = exceptions_after.get(perm_type, {})
            
            if before != after:
                logger.warning(f"Permission type '{perm_type}' was modified (should not have changed)")
                return False
        
        return True
        
    except Exception as e:
        logger.error(f"Error checking other permission types: {e}")
        return False
