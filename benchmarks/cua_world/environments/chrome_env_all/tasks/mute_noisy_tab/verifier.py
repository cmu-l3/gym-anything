#!/usr/bin/env python3
"""
Verifier for Chrome Tab Audio Muting Task: mute_noisy_tab@1
Task: Locate and mute a tab playing audio among multiple tabs without closing it

Verification Strategy:
1. Compare initial and final tab counts (should be equal - no tabs closed)
2. Verify the audio tab URL still exists in final tabs (tab preserved)
3. Check if the audio tab URL is in Chrome's muted sites list (Preferences)
4. Ensure other tabs were not affected
5. Validate that the correct tab was targeted

Scoring:
- 100%: All 5 criteria met (perfect execution)
- 85%: 4/5 criteria met (minor issue)
- 70%: 3/5 criteria met (acceptable, still passing)
- <70%: <3 criteria met (failed)

Pass threshold: 75% (at least 4 out of 5 criteria)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional
from urllib.parse import urlparse, unquote

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for mute_noisy_tab@1.
    
    Verifies that the audio-playing tab was correctly muted without being closed.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
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

    try:
        # Get initial and final tab data
        initial_tabs = get_tab_data(copy_from_env, "/tmp/initial_tabs.json")
        final_tabs = get_tab_data(copy_from_env, "/tmp/chrome_final_tabs.json")
        audio_url = get_audio_tab_url(copy_from_env)
        preferences = get_preferences(copy_from_env)
        
        if initial_tabs is None or final_tabs is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve tab data from container"
            }
        
        if not audio_url:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not determine which tab was playing audio"
            }
        
        # Perform verification
        result = verify_audio_muting(
            initial_tabs=initial_tabs,
            final_tabs=final_tabs,
            audio_url=audio_url,
            preferences=preferences
        )
        
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


def get_tab_data(copy_from_env, container_path: str) -> Optional[List[Dict]]:
    """
    Retrieve tab data from container.
    
    Args:
        copy_from_env: Function to copy files from container
        container_path: Path to tab JSON file in container
        
    Returns:
        List of tab dictionaries or None on failure
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env(container_path, temp_path)
        
        with open(temp_path, 'r') as f:
            data = json.load(f)
        
        os.unlink(temp_path)
        
        logger.info(f"Retrieved {len(data)} tabs from {container_path}")
        return data
        
    except Exception as e:
        logger.error(f"Failed to get tab data from {container_path}: {e}")
        return None


def get_audio_tab_url(copy_from_env) -> Optional[str]:
    """
    Get the URL of the tab that was playing audio.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Audio tab URL or None
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/audio_tab_url.txt", temp_path)
        
        with open(temp_path, 'r') as f:
            url = f.read().strip()
        
        os.unlink(temp_path)
        
        logger.info(f"Audio tab URL: {url}")
        return url
        
    except Exception as e:
        logger.error(f"Failed to get audio tab URL: {e}")
        return None


def get_preferences(copy_from_env) -> Optional[Dict]:
    """
    Get Chrome preferences containing muted sites.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Preferences dict or None
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/chrome_preferences.json", temp_path)
        
        with open(temp_path, 'r', encoding='utf-8') as f:
            prefs = json.load(f)
        
        os.unlink(temp_path)
        
        logger.info("Successfully retrieved Chrome preferences")
        return prefs
        
    except Exception as e:
        logger.warning(f"Failed to get preferences: {e}")
        return None


def normalize_url(url: str) -> str:
    """Normalize URL for comparison."""
    if not url:
        return ""
    # Remove trailing slashes, normalize scheme
    url = url.rstrip('/')
    url = url.replace('http://', '').replace('https://', '')
    url = url.lower()
    return url


def is_url_muted(url: str, preferences: Optional[Dict]) -> Tuple[bool, str]:
    """
    Check if a URL is in Chrome's muted sites list.
    
    Args:
        url: URL to check
        preferences: Chrome preferences dict
        
    Returns:
        Tuple of (is_muted: bool, reason: str)
    """
    if not preferences:
        return False, "Preferences not available"
    
    try:
        # Chrome stores muted sites in profile.content_settings.exceptions.sound
        profile = preferences.get('profile', {})
        content_settings = profile.get('content_settings', {})
        exceptions = content_settings.get('exceptions', {})
        sound_settings = exceptions.get('sound', {})
        
        # Parse the URL to get domain
        if url.startswith('file://'):
            # For file URLs, Chrome mutes the entire file:// protocol
            url_pattern = 'file:///*'
            if url_pattern in sound_settings:
                setting = sound_settings[url_pattern]
                if setting.get('setting') == 2:  # 2 = BLOCK (muted)
                    return True, f"File protocol muted in settings"
            
            # Also check if there's a specific file path entry
            for pattern, setting in sound_settings.items():
                if 'file:///' in pattern and setting.get('setting') == 2:
                    return True, f"File URLs muted (pattern: {pattern})"
        else:
            # For web URLs
            parsed = urlparse(url)
            domain = parsed.netloc
            
            # Check for exact domain match or wildcard patterns
            for pattern, setting in sound_settings.items():
                if domain in pattern and setting.get('setting') == 2:
                    return True, f"Domain muted: {pattern}"
        
        return False, "URL not in muted list"
        
    except Exception as e:
        logger.error(f"Error checking muted status: {e}")
        return False, f"Error: {e}"


def verify_audio_muting(
    initial_tabs: List[Dict],
    final_tabs: List[Dict],
    audio_url: str,
    preferences: Optional[Dict]
) -> Dict[str, Any]:
    """
    Verify that audio muting was performed correctly.
    
    Checks:
    1. Tab count remained the same (no tabs closed)
    2. Audio tab still exists (tab preserved)
    3. Audio URL is in muted sites (task completed)
    4. Other tabs unaffected
    5. Correct tab was targeted
    
    Args:
        initial_tabs: Initial tab state
        final_tabs: Final tab state
        audio_url: URL of the audio-playing tab
        preferences: Chrome preferences
        
    Returns:
        Verification result dict
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Extract URLs
    initial_urls = [t.get('url', '') for t in initial_tabs]
    final_urls = [t.get('url', '') for t in final_tabs]
    
    logger.info(f"Initial tabs: {len(initial_tabs)}")
    logger.info(f"Final tabs: {len(final_tabs)}")
    logger.info(f"Audio tab URL: {audio_url}")
    
    # Criterion 1: Tab count remained the same
    tab_count_preserved = len(initial_tabs) == len(final_tabs)
    if tab_count_preserved:
        feedback_parts.append(f"✓ Tab count preserved: {len(final_tabs)} tabs (no tabs closed)")
        criteria_met += 1
        logger.info("✓ Criterion 1 PASS: Tab count preserved")
    else:
        feedback_parts.append(f"✗ Tab count changed: {len(initial_tabs)} → {len(final_tabs)} (tabs may have been closed)")
        logger.info(f"✗ Criterion 1 FAIL: Tab count changed from {len(initial_tabs)} to {len(final_tabs)}")
    
    # Criterion 2: Audio tab still exists
    audio_url_normalized = normalize_url(audio_url)
    final_urls_normalized = [normalize_url(u) for u in final_urls]
    
    audio_tab_exists = any(audio_url_normalized in norm_url for norm_url in final_urls_normalized)
    
    if audio_tab_exists:
        feedback_parts.append(f"✓ Audio tab preserved: Tab still open (not closed)")
        criteria_met += 1
        logger.info("✓ Criterion 2 PASS: Audio tab still exists")
    else:
        feedback_parts.append(f"✗ Audio tab missing: Tab may have been closed instead of muted")
        logger.info("✗ Criterion 2 FAIL: Audio tab not found in final tabs")
        # Log for debugging
        logger.info(f"Looking for: {audio_url_normalized}")
        logger.info(f"In final URLs: {final_urls_normalized}")
    
    # Criterion 3: Audio URL is in muted sites
    is_muted, mute_reason = is_url_muted(audio_url, preferences)
    
    if is_muted:
        feedback_parts.append(f"✓ Audio muted: {mute_reason}")
        criteria_met += 1
        logger.info(f"✓ Criterion 3 PASS: Audio is muted - {mute_reason}")
    else:
        feedback_parts.append(f"✗ Audio not muted: {mute_reason}")
        logger.info(f"✗ Criterion 3 FAIL: Audio not muted - {mute_reason}")
    
    # Criterion 4: Other tabs unaffected (count similar)
    # If tab count is preserved, this is mostly satisfied
    # We can also check that non-audio tabs still exist
    non_audio_initial = [u for u in initial_urls if normalize_url(u) != audio_url_normalized]
    non_audio_final = [u for u in final_urls if normalize_url(u) != audio_url_normalized]
    
    # Check that most non-audio tabs are still present
    non_audio_preserved_count = sum(
        1 for init_url in non_audio_initial
        if any(normalize_url(init_url) in normalize_url(final_url) for final_url in non_audio_final)
    )
    
    other_tabs_ok = non_audio_preserved_count >= len(non_audio_initial) * 0.8  # At least 80% preserved
    
    if other_tabs_ok:
        feedback_parts.append(f"✓ Other tabs unaffected: {non_audio_preserved_count}/{len(non_audio_initial)} non-audio tabs preserved")
        criteria_met += 1
        logger.info("✓ Criterion 4 PASS: Other tabs unaffected")
    else:
        feedback_parts.append(f"⚠ Some tabs affected: Only {non_audio_preserved_count}/{len(non_audio_initial)} non-audio tabs preserved")
        logger.info(f"✗ Criterion 4 FAIL: Only {non_audio_preserved_count}/{len(non_audio_initial)} preserved")
    
    # Criterion 5: Correct execution (combination check)
    # This is essentially: audio tab exists AND is muted AND other tabs fine
    correct_execution = audio_tab_exists and is_muted and tab_count_preserved
    
    if correct_execution:
        feedback_parts.append(f"✓ Correct execution: Target tab muted without closing, other tabs intact")
        criteria_met += 1
        logger.info("✓ Criterion 5 PASS: Correct execution")
    else:
        feedback_parts.append(f"✗ Execution issues: Task not completed correctly")
        logger.info("✗ Criterion 5 FAIL: Execution issues")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 4/5 criteria
    
    # Build feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if passed:
        feedback += "\n\nTask completed successfully! The audio tab was muted without closing it."
    else:
        feedback += "\n\nTask incomplete. Please ensure you:"
        feedback += "\n  1. Right-clicked on the tab with the speaker icon"
        feedback += "\n  2. Selected 'Mute site' or 'Mute tab' from the menu"
        feedback += "\n  3. Did not close the tab"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "initial_tab_count": len(initial_tabs),
            "final_tab_count": len(final_tabs),
            "audio_tab_exists": audio_tab_exists,
            "audio_url_muted": is_muted,
            "other_tabs_ok": other_tabs_ok
        }
    }
