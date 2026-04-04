#!/usr/bin/env python3
"""
Verifier for Chrome Tab Audio Control Task: tab_audio_mute@1
Task: Manage audio playback across multiple tabs by selectively muting tabs with audio content

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query all open tabs in real-time
- Verifies exactly 3 tabs are open (music, video, silent)
- Checks that music and video tabs are muted
- Verifies that silent tab is not muted
- Validates URLs match expected demo pages
- Ensures no audible audio is currently playing (all should be muted)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp, parse_history
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for tab_audio_mute@1 task.
    
    Verifies:
    1. Exactly 3 tabs are open
    2. Music tab is muted
    3. Video tab is muted  
    4. Silent tab is NOT muted
    5. No tabs are currently playing audible audio
    6. URLs match expected patterns (supplementary check)
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed' (bool), 'score' (int 0-100), and 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Get tab audio state data from container
        tabs_data = get_tab_audio_data(copy_from_env)
        if tabs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve tab audio state from Chrome CDP"
            }

        # Perform multi-criteria verification
        verification_result = verify_tab_audio_control(tabs_data)
        
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


def get_tab_audio_data(copy_from_env) -> List[Dict[str, Any]]:
    """
    Retrieve tab audio state information from container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        List of tab dictionaries with url, title, audible, muted fields
    """
    try:
        # Copy the CDP JSON data from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/chrome_tabs_audio_state.json", temp_path)
        
        with open(temp_path, 'r') as f:
            tabs_data = json.load(f)
        
        os.unlink(temp_path)
        
        logger.info(f"Successfully retrieved {len(tabs_data)} tab(s) with audio state from CDP")
        return tabs_data
        
    except Exception as e:
        logger.error(f"Failed to get tab audio data: {e}")
        return None


def normalize_url(url: str) -> str:
    """Normalize URL for comparison"""
    if not url:
        return ""
    url = url.lower().strip()
    # Remove trailing slashes
    url = url.rstrip('/')
    # Remove common protocol variations
    url = url.replace('https://', '').replace('http://', '')
    return url


def identify_tab_type(url: str, title: str) -> str:
    """
    Identify which type of demo page this tab contains.
    
    Returns: 'music', 'video', 'article', or 'other'
    """
    url_lower = normalize_url(url)
    title_lower = title.lower()
    
    # Check for music page
    if 'background_music.html' in url_lower or 'music' in title_lower:
        return 'music'
    
    # Check for video page
    if 'video_content.html' in url_lower or 'video' in title_lower:
        return 'video'
    
    # Check for silent article page
    if 'silent_article.html' in url_lower or 'web development' in title_lower or 'article' in title_lower:
        return 'article'
    
    return 'other'


def verify_tab_audio_control(tabs_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that tab audio control was correctly performed.
    
    Checks:
    1. Exactly 3 tabs open
    2. Music tab identified and muted
    3. Video tab identified and muted
    4. Silent article tab identified and NOT muted
    5. No tabs currently playing audible audio
    6. All expected tab types present
    
    Args:
        tabs_data: List of tab information from CDP with audio state
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    # Extract tab information
    tab_count = len(tabs_data)
    
    logger.info(f"Analyzing {tab_count} tabs for audio control")
    
    # Categorize tabs
    tabs_by_type = {
        'music': [],
        'video': [],
        'article': [],
        'other': []
    }
    
    for tab in tabs_data:
        url = tab.get('url', '')
        title = tab.get('title', '')
        tab_type = identify_tab_type(url, title)
        
        tab_info = {
            'url': url,
            'title': title,
            'audible': tab.get('audible', False),
            'muted': tab.get('muted', False),
            'type': tab_type
        }
        
        tabs_by_type[tab_type].append(tab_info)
        
        logger.info(f"  Tab: {tab_type} | Muted: {tab_info['muted']} | Audible: {tab_info['audible']}")
        logger.info(f"    URL: {url[:80]}")
    
    # Criterion 1: Tab count (exactly 3 tabs)
    tab_count_ok = tab_count == 3
    logger.info(f"✓ Tab count check: {tab_count} tabs (expected 3) - {'PASS' if tab_count_ok else 'FAIL'}")
    
    # Criterion 2: Music tab is muted
    music_tabs = tabs_by_type['music']
    music_muted_ok = len(music_tabs) == 1 and music_tabs[0]['muted']
    if len(music_tabs) == 0:
        logger.info(f"✗ Music tab check: Music tab not found - FAIL")
    elif len(music_tabs) > 1:
        logger.info(f"✗ Music tab check: Multiple music tabs found - FAIL")
    else:
        logger.info(f"✓ Music tab check: Found and muted={music_tabs[0]['muted']} - {'PASS' if music_muted_ok else 'FAIL'}")
    
    # Criterion 3: Video tab is muted
    video_tabs = tabs_by_type['video']
    video_muted_ok = len(video_tabs) == 1 and video_tabs[0]['muted']
    if len(video_tabs) == 0:
        logger.info(f"✗ Video tab check: Video tab not found - FAIL")
    elif len(video_tabs) > 1:
        logger.info(f"✗ Video tab check: Multiple video tabs found - FAIL")
    else:
        logger.info(f"✓ Video tab check: Found and muted={video_tabs[0]['muted']} - {'PASS' if video_muted_ok else 'FAIL'}")
    
    # Criterion 4: Article tab is NOT muted
    article_tabs = tabs_by_type['article']
    article_unmuted_ok = len(article_tabs) == 1 and not article_tabs[0]['muted']
    if len(article_tabs) == 0:
        logger.info(f"✗ Article tab check: Article tab not found - FAIL")
    elif len(article_tabs) > 1:
        logger.info(f"✗ Article tab check: Multiple article tabs found - FAIL")
    else:
        logger.info(f"✓ Article tab check: Found and muted={article_tabs[0]['muted']} - {'PASS' if article_unmuted_ok else 'FAIL'}")
    
    # Criterion 5: No audible audio (all muted tabs should not be audible)
    any_audible = any(tab.get('audible', False) for tab in tabs_data)
    no_audible_ok = not any_audible
    logger.info(f"✓ Audible audio check: Any audible={any_audible} - {'PASS' if no_audible_ok else 'FAIL'}")
    
    # Criterion 6: All expected tab types present
    all_types_present = (
        len(music_tabs) >= 1 and
        len(video_tabs) >= 1 and
        len(article_tabs) >= 1
    )
    logger.info(f"✓ Tab types check: Music={len(music_tabs)}, Video={len(video_tabs)}, Article={len(article_tabs)} - {'PASS' if all_types_present else 'FAIL'}")
    
    # Calculate score based on criteria met
    criteria_results = [
        tab_count_ok,           # Exactly 3 tabs
        music_muted_ok,         # Music tab muted
        video_muted_ok,         # Video tab muted
        article_unmuted_ok,     # Article tab NOT muted
        no_audible_ok,          # No audible audio
        all_types_present       # All tab types present
    ]
    
    criteria_met = sum(criteria_results)
    score = int((criteria_met / 6) * 100)
    passed = score >= 80  # Need at least 5/6 criteria (80%)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Verification Results: {criteria_met}/6 criteria met")
    feedback_parts.append("")
    feedback_parts.append(f"{'✓' if tab_count_ok else '✗'} Tab count: {tab_count} tabs (expected 3)")
    feedback_parts.append(f"{'✓' if music_muted_ok else '✗'} Music tab: {'muted' if len(music_tabs) > 0 and music_tabs[0]['muted'] else 'not muted or not found'}")
    feedback_parts.append(f"{'✓' if video_muted_ok else '✗'} Video tab: {'muted' if len(video_tabs) > 0 and video_tabs[0]['muted'] else 'not muted or not found'}")
    feedback_parts.append(f"{'✓' if article_unmuted_ok else '✗'} Article tab: {'correctly unmuted' if len(article_tabs) > 0 and not article_tabs[0]['muted'] else 'incorrectly muted or not found'}")
    feedback_parts.append(f"{'✓' if no_audible_ok else '✗'} No audible audio: {'correct' if no_audible_ok else 'some tabs still playing audio'}")
    feedback_parts.append(f"{'✓' if all_types_present else '✗'} All tab types present: {'yes' if all_types_present else 'missing tabs'}")
    feedback_parts.append("")
    
    if passed:
        feedback_parts.append("✅ Task completed successfully! Audio management verified.")
    else:
        feedback_parts.append("❌ Task incomplete - check mute states and tab configuration")
        
        # Add helpful debugging info
        if not all_types_present:
            feedback_parts.append("")
            feedback_parts.append("Missing or extra tabs detected:")
            feedback_parts.append(f"  - Music tabs: {len(music_tabs)}")
            feedback_parts.append(f"  - Video tabs: {len(video_tabs)}")
            feedback_parts.append(f"  - Article tabs: {len(article_tabs)}")
            feedback_parts.append(f"  - Other tabs: {len(tabs_by_type['other'])}")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "tab_count": tab_count,
            "criteria_met": criteria_met,
            "music_tabs": len(music_tabs),
            "video_tabs": len(video_tabs),
            "article_tabs": len(article_tabs),
            "other_tabs": len(tabs_by_type['other']),
            "music_muted": music_tabs[0]['muted'] if music_tabs else None,
            "video_muted": video_tabs[0]['muted'] if video_tabs else None,
            "article_muted": article_tabs[0]['muted'] if article_tabs else None,
            "any_audible": any_audible
        }
    }
