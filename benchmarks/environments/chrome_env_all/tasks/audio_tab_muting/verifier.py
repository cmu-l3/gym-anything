#!/usr/bin/env python3
"""
Verifier for Chrome Audio Tab Muting Task: audio_tab_muting@1
Task: Identify and mute the tab playing audio among multiple open tabs

Verification Strategy:
1. Check if the audio tab (YouTube URL) was closed (acceptable solution)
2. Check if the audio tab URL is in Chrome's muted sites list (preferred solution)
3. Verify workflow preservation (other tabs remain open)
4. Score based on method used and collateral damage
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
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
    Main verification function for audio_tab_muting@1 task.
    
    Verifies that the agent successfully muted or closed the audio-playing tab
    without disrupting the workflow (other tabs).
    
    Scoring:
    - 100%: Audio tab muted (preferred method), all other tabs preserved
    - 85%: Audio tab closed, all other tabs preserved  
    - 70%: Audio stopped but with minor collateral (1 other tab affected)
    - 50%: Audio stopped but inefficient (multiple tabs closed)
    - 0%: Audio still playing OR all tabs closed
    
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
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Get verification data from container
        verification_data = extract_verification_data(copy_from_env)
        
        if not verification_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to extract verification data from container"
            }
        
        # Perform verification
        result = verify_audio_tab_muting(verification_data)
        
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


def extract_verification_data(copy_from_env) -> Optional[Dict[str, Any]]:
    """
    Extract all necessary verification data from container.
    
    Returns:
        Dict containing:
        - initial_tab_count: Number of tabs at start
        - final_tab_urls: List of URLs in final state
        - audio_tab_url: The URL that was playing audio
        - preferences: Chrome Preferences JSON
    """
    data = {
        "initial_tab_count": 8,  # Expected from setup
        "final_tab_urls": [],
        "audio_tab_url": "",
        "preferences": {},
        "final_tab_count": 0
    }
    
    temp_files = []
    
    try:
        # 1. Get audio tab URL marker
        temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_files.append(temp_marker.name)
        temp_marker.close()
        
        try:
            copy_from_env("/tmp/audio_tab_url_marker.txt", temp_marker.name)
            with open(temp_marker.name, 'r') as f:
                data["audio_tab_url"] = f.read().strip()
            logger.info(f"Audio tab URL: {data['audio_tab_url']}")
        except Exception as e:
            logger.warning(f"Could not get audio tab URL marker: {e}")
            # Fallback to known URL
            data["audio_tab_url"] = "https://www.youtube.com/watch?v=jfKfPfyJRdk"
        
        # 2. Get final tab URLs
        temp_urls = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_files.append(temp_urls.name)
        temp_urls.close()
        
        try:
            copy_from_env("/tmp/final_tab_urls.txt", temp_urls.name)
            with open(temp_urls.name, 'r') as f:
                data["final_tab_urls"] = [line.strip() for line in f if line.strip()]
            data["final_tab_count"] = len(data["final_tab_urls"])
            logger.info(f"Final tab count: {data['final_tab_count']}")
            logger.info(f"Final tab URLs: {data['final_tab_urls']}")
        except Exception as e:
            logger.error(f"Could not get final tab URLs: {e}")
            return None
        
        # 3. Get Chrome Preferences
        temp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_files.append(temp_prefs.name)
        temp_prefs.close()
        
        try:
            copy_from_env("/tmp/chrome_preferences.json", temp_prefs.name)
            with open(temp_prefs.name, 'r', encoding='utf-8') as f:
                data["preferences"] = json.load(f)
            logger.info("Successfully loaded Chrome Preferences")
        except Exception as e:
            logger.warning(f"Could not load Chrome Preferences: {e}")
            data["preferences"] = {}
        
        return data
        
    except Exception as e:
        logger.error(f"Error extracting verification data: {e}")
        return None
    finally:
        # Cleanup temp files
        for temp_path in temp_files:
            try:
                if os.path.exists(temp_path):
                    os.unlink(temp_path)
            except:
                pass


def normalize_url(url: str) -> str:
    """Normalize URL for comparison (remove protocol, trailing slash, query params)"""
    if not url:
        return ""
    
    # Remove protocol
    url = re.sub(r'^https?://', '', url)
    
    # For YouTube, keep only the base watch URL with video ID
    if 'youtube.com/watch' in url:
        match = re.search(r'youtube\.com/watch\?v=([^&]+)', url)
        if match:
            return f"youtube.com/watch?v={match.group(1)}"
    
    # Remove trailing slash
    url = url.rstrip('/')
    
    return url.lower()


def is_audio_tab_present(audio_tab_url: str, final_tab_urls: List[str]) -> bool:
    """Check if the audio tab URL is still present in final tabs"""
    audio_normalized = normalize_url(audio_tab_url)
    
    for url in final_tab_urls:
        if normalize_url(url) == audio_normalized:
            return True
    
    return False


def check_muted_in_preferences(preferences: Dict, audio_tab_url: str) -> bool:
    """
    Check if the audio tab URL is in Chrome's muted sites list.
    
    Chrome stores muted sites in:
    - profile.content_settings.exceptions.sound (site-specific)
    - Or in session-specific mute state (not persisted in Preferences)
    """
    if not preferences:
        return False
    
    try:
        # Check content settings for sound
        content_settings = preferences.get('profile', {}).get('content_settings', {})
        exceptions = content_settings.get('exceptions', {})
        sound_exceptions = exceptions.get('sound', {})
        
        # Extract domain from audio URL
        audio_domain = None
        if 'youtube.com' in audio_tab_url:
            audio_domain = 'youtube.com'
        
        if audio_domain:
            # Check if domain has sound blocked/muted
            for pattern, settings in sound_exceptions.items():
                if audio_domain in pattern:
                    setting_value = settings.get('setting', 0)
                    # setting=2 typically means "block" (muted)
                    if setting_value == 2:
                        logger.info(f"Found muted setting for {audio_domain}")
                        return True
        
        # Check for tab-specific muting (less common in Preferences)
        # This is typically stored in session state, not Preferences
        # So we'll be conservative here
        
        return False
        
    except Exception as e:
        logger.warning(f"Error checking muted preferences: {e}")
        return False


def verify_audio_tab_muting(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the audio tab was properly muted or closed.
    
    Verification criteria:
    1. Audio tab no longer present (closed) - 85% if workflow preserved
    2. Audio tab muted in preferences - 100% if workflow preserved
    3. Workflow preservation (other tabs remain) - affects final score
    4. Efficiency (minimal collateral damage)
    """
    audio_tab_url = data["audio_tab_url"]
    final_tab_urls = data["final_tab_urls"]
    final_tab_count = data["final_tab_count"]
    initial_tab_count = data["initial_tab_count"]
    preferences = data["preferences"]
    
    # Check if audio tab is still present
    audio_tab_present = is_audio_tab_present(audio_tab_url, final_tab_urls)
    
    # Check if audio tab is muted in preferences
    audio_tab_muted = check_muted_in_preferences(preferences, audio_tab_url)
    
    # Calculate tab loss (how many tabs were closed)
    tabs_lost = initial_tab_count - final_tab_count
    
    logger.info(f"Verification results:")
    logger.info(f"  Audio tab present: {audio_tab_present}")
    logger.info(f"  Audio tab muted: {audio_tab_muted}")
    logger.info(f"  Initial tabs: {initial_tab_count}")
    logger.info(f"  Final tabs: {final_tab_count}")
    logger.info(f"  Tabs lost: {tabs_lost}")
    
    # Determine outcome and score
    feedback_parts = []
    
    # Case 1: Audio tab muted (preferred solution)
    if audio_tab_muted and audio_tab_present:
        score = 100
        feedback_parts.append("✓ Audio tab successfully muted (preferred method)")
        
        if tabs_lost == 0:
            feedback_parts.append("✓ All other tabs preserved (perfect workflow)")
        elif tabs_lost == 1:
            score = 95
            feedback_parts.append("⚠ One tab was accidentally closed")
        else:
            score = 85
            feedback_parts.append(f"⚠ {tabs_lost} tabs were closed unnecessarily")
        
        passed = True
    
    # Case 2: Audio tab closed (acceptable solution)
    elif not audio_tab_present and not audio_tab_muted:
        # Audio tab was closed
        if tabs_lost == 1:
            score = 85
            feedback_parts.append("✓ Audio tab successfully closed (acceptable method)")
            feedback_parts.append("✓ All other tabs preserved")
            passed = True
        elif tabs_lost == 2:
            score = 70
            feedback_parts.append("✓ Audio tab closed")
            feedback_parts.append("⚠ One additional tab was accidentally closed")
            passed = True
        elif tabs_lost >= 3 and tabs_lost < initial_tab_count:
            score = 50
            feedback_parts.append("⚠ Audio tab closed but workflow disrupted")
            feedback_parts.append(f"⚠ {tabs_lost} tabs were closed (only 1 needed)")
            passed = False
        elif final_tab_count == 0:
            score = 0
            feedback_parts.append("✗ All tabs were closed - workflow completely destroyed")
            passed = False
        else:
            score = 60
            feedback_parts.append("⚠ Audio tab closed with some collateral damage")
            passed = False
    
    # Case 3: Audio tab still present and NOT muted (task failed)
    elif audio_tab_present and not audio_tab_muted:
        score = 0
        feedback_parts.append("✗ Audio tab is still present and not muted")
        feedback_parts.append("✗ Task failed - audio is still playing")
        passed = False
    
    # Case 4: Edge case - all tabs closed
    elif final_tab_count == 0:
        score = 0
        feedback_parts.append("✗ All tabs were closed")
        feedback_parts.append("✗ Workflow completely destroyed")
        passed = False
    
    else:
        # Unexpected state
        score = 0
        feedback_parts.append("⚠ Unexpected state - unable to verify task completion")
        passed = False
    
    # Add summary statistics
    feedback_parts.append("")
    feedback_parts.append("=" * 50)
    feedback_parts.append(f"Initial tabs: {initial_tab_count}")
    feedback_parts.append(f"Final tabs: {final_tab_count}")
    feedback_parts.append(f"Audio tab present: {audio_tab_present}")
    feedback_parts.append(f"Audio tab muted: {audio_tab_muted}")
    feedback_parts.append(f"Score: {score}%")
    feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "audio_tab_present": audio_tab_present,
            "audio_tab_muted": audio_tab_muted,
            "initial_tab_count": initial_tab_count,
            "final_tab_count": final_tab_count,
            "tabs_lost": tabs_lost,
            "final_tab_urls": final_tab_urls
        }
    }
