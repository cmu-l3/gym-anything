#!/usr/bin/env python3
"""
Verifier for Configure ASL Practice task
"""

import sys
import os
import logging
import tempfile
import json
import re
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    parse_vlc_config,
    parse_m3u_playlist,
    parse_xspf_playlist,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_asl_practice_config(traj, env_info, task_info):
    """
    Verify VLC is configured for ASL practice workflow.
    
    Scoring breakdown (100 points total):
    1. Playback Speed Configuration (40 points): 60-70% range
    2. Frame-Step Hotkeys (20 points): Custom hotkeys configured  
    3. Bookmarks Created (30 points): 5 bookmarks at target timestamps
    4. A-B Loop Configured (10 points): Loop markers set
    
    Pass threshold: 70/100 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "ERROR: Copy function not available"
        }
    
    score = 0
    max_score = 100
    feedback_parts = []
    temp_files = []
    
    try:
        # ============================================================
        # 1. Check playback speed configuration (40 points)
        # ============================================================
        config_file = tempfile.NamedTemporaryFile(delete=False, suffix='_vlcrc.txt')
        temp_files.append(config_file.name)
        
        try:
            copy_from_env("/tmp/vlc_asl_config.txt", config_file.name)
            config = parse_vlc_config(config_file.name)
            
            # Look for speed-related settings in vlcrc
            speed_keys = ['rate', 'playback-speed', 'input-rate']
            speed_configured = False
            speed_value = None
            
            for key in speed_keys:
                if key in config:
                    try:
                        speed_value = float(config[key])
                        # Check if in target range: 0.60 to 0.70 (60% to 70%)
                        if 0.60 <= speed_value <= 0.70:
                            score += 40
                            feedback_parts.append(f"✅ Playback speed configured: {speed_value:.2f}x (target: 0.65x) [40pts]")
                            speed_configured = True
                            break
                        elif 0.50 <= speed_value <= 0.80:
                            # Close but not exact
                            score += 25
                            feedback_parts.append(f"⚠️  Playback speed close: {speed_value:.2f}x (target: 0.60-0.70x) [25pts]")
                            speed_configured = True
                            break
                    except ValueError:
                        continue
            
            if not speed_configured:
                feedback_parts.append("❌ Playback speed not configured to 60-70% range [0pts]")
        
        except FileNotFoundError:
            feedback_parts.append("❌ VLC config file not found [0pts]")
            config = {}
        except Exception as e:
            logger.error(f"Error checking playback speed: {e}", exc_info=True)
            feedback_parts.append(f"❌ Error checking playback speed: {e} [0pts]")
            config = {}
        
        # ============================================================
        # 2. Check frame-step hotkey configuration (20 points)
        # ============================================================
        try:
            # Look for frame-step related hotkey bindings
            frame_step_keys = [
                'key-frame-next',
                'key-frame-prev',
                'global-key-frame-next',
                'global-key-frame-prev'
            ]
            
            hotkey_configured = False
            configured_keys = []
            
            for key in frame_step_keys:
                if key in config:
                    key_value = config[key]
                    # Check if it's not the default (which would be empty or default value)
                    # Common defaults: "" or "Unset" or default keys like "e" or "."
                    if key_value and key_value.lower() not in ['unset', '', 'none']:
                        configured_keys.append(f"{key}={key_value}")
                        hotkey_configured = True
            
            if hotkey_configured and len(configured_keys) >= 1:
                score += 20
                feedback_parts.append(f"✅ Frame-step hotkeys configured: {', '.join(configured_keys)} [20pts]")
            elif len(configured_keys) > 0:
                # Partial credit if only one key configured
                score += 10
                feedback_parts.append(f"⚠️  Some frame-step hotkeys configured: {', '.join(configured_keys)} [10pts]")
            else:
                feedback_parts.append("❌ Frame-step hotkeys not configured [0pts]")
        
        except Exception as e:
            logger.error(f"Error checking hotkeys: {e}", exc_info=True)
            feedback_parts.append(f"❌ Error checking hotkeys: {e} [0pts]")
        
        # ============================================================
        # 3. Check for bookmarks (30 points)
        # ============================================================
        try:
            # Target timestamps in seconds (with tolerance)
            target_timestamps = [
                (135, "2:15", 3),   # 2min 15sec ± 3s
                (347, "5:47", 3),   # 5min 47sec ± 3s
                (563, "9:23", 3),   # 9min 23sec ± 3s
                (908, "15:08", 3),  # 15min 8sec ± 3s
                (1294, "21:34", 3)  # 21min 34sec ± 3s
            ]
            
            bookmarks_found = False
            found_count = 0
            bookmark_method = None
            
            # Try to find and parse bookmark files
            # Check for various possible bookmark file names
            bookmark_patterns = [
                "/tmp/vlc_asl_bookmarks_*.xspf",
                "/tmp/vlc_asl_bookmarks_*.m3u",
                "/tmp/vlc_asl_recent_*.xspf",
                "/tmp/vlc_asl_recent_*.m3u"
            ]
            
            import glob
            bookmark_files = []
            for pattern in bookmark_patterns:
                bookmark_files.extend(glob.glob(pattern))
            
            if bookmark_files:
                logger.info(f"Found bookmark files: {bookmark_files}")
                
                for bookmark_file in bookmark_files:
                    try:
                        if bookmark_file.endswith('.xspf'):
                            items = parse_xspf_playlist(bookmark_file)
                            if items and len(items) >= 3:
                                found_count = len(items)
                                bookmarks_found = True
                                bookmark_method = "XSPF playlist"
                                logger.info(f"Found {found_count} items in XSPF playlist")
                                break
                        
                        elif bookmark_file.endswith('.m3u'):
                            items = parse_m3u_playlist(bookmark_file)
                            if items and len(items) >= 3:
                                found_count = len(items)
                                bookmarks_found = True
                                bookmark_method = "M3U playlist"
                                logger.info(f"Found {found_count} items in M3U playlist")
                                break
                    
                    except Exception as e:
                        logger.warning(f"Error parsing {bookmark_file}: {e}")
                        continue
            
            # Alternative: Check for bookmark-related config entries
            if not bookmarks_found:
                bookmark_config_keys = [
                    key for key in config.keys() 
                    if 'bookmark' in key.lower() or 'custom-bookmark' in key.lower()
                ]
                
                if len(bookmark_config_keys) >= 3:
                    found_count = len(bookmark_config_keys)
                    bookmarks_found = True
                    bookmark_method = "config entries"
                    logger.info(f"Found {found_count} bookmark config entries")
            
            # Score based on number of bookmarks found
            if bookmarks_found and found_count >= 5:
                score += 30
                feedback_parts.append(f"✅ Found {found_count} bookmarks via {bookmark_method} [30pts]")
            elif found_count >= 3:
                # Partial credit for 3-4 bookmarks
                partial_score = int(30 * (found_count / 5))
                score += partial_score
                feedback_parts.append(f"⚠️  Found {found_count}/5 bookmarks via {bookmark_method} [{partial_score}pts]")
            elif found_count > 0:
                # Minimal credit for any bookmarks
                score += 10
                feedback_parts.append(f"⚠️  Found only {found_count} bookmark(s) [{10}pts]")
            else:
                feedback_parts.append("❌ No bookmarks found (expected 5 at: 2:15, 5:47, 9:23, 15:08, 21:34) [0pts]")
        
        except Exception as e:
            logger.error(f"Error checking bookmarks: {e}", exc_info=True)
            feedback_parts.append(f"❌ Error checking bookmarks: {e} [0pts]")
        
        # ============================================================
        # 4. Check A-B loop configuration (10 points)
        # ============================================================
        try:
            # Look for A-B loop markers in config
            loop_keys = [
                ('ab-loop-a', 'ab-loop-b'),
                ('loop-a', 'loop-b'),
                ('input-repeat', None)
            ]
            
            loop_configured = False
            loop_points = None
            
            for key_a, key_b in loop_keys:
                if key_a in config:
                    if key_b and key_b in config:
                        try:
                            loop_start = float(config[key_a])
                            loop_end = float(config[key_b])
                            
                            # Expected: ~135s to ~138s (2:15 to 2:18), with tolerance
                            if (130 <= loop_start <= 140) and (135 <= loop_end <= 143):
                                score += 10
                                feedback_parts.append(f"✅ A-B loop configured: {loop_start:.0f}s to {loop_end:.0f}s [10pts]")
                                loop_configured = True
                                break
                            else:
                                # Some loop is set but not at expected range
                                score += 5
                                feedback_parts.append(f"⚠️  A-B loop set but not at expected range: {loop_start:.0f}s to {loop_end:.0f}s [5pts]")
                                loop_configured = True
                                break
                        except (ValueError, TypeError):
                            pass
                    else:
                        # Generic repeat/loop setting
                        if config[key_a] not in ['', '0', 'false']:
                            score += 3
                            feedback_parts.append(f"⚠️  Loop setting found: {key_a}={config[key_a]} [3pts]")
                            loop_configured = True
                            break
            
            if not loop_configured:
                feedback_parts.append("❌ A-B loop not configured (optional) [0pts]")
        
        except Exception as e:
            logger.error(f"Error checking A-B loop: {e}", exc_info=True)
            feedback_parts.append(f"❌ Error checking A-B loop: {e} [0pts]")
        
    finally:
        # Clean up temp files
        for temp_file in temp_files:
            try:
                if os.path.exists(temp_file):
                    os.unlink(temp_file)
            except Exception as e:
                logger.warning(f"Failed to clean up {temp_file}: {e}")
    
    # ============================================================
    # Final result
    # ============================================================
    passed = score >= 70
    
    feedback_summary = [
        f"\n{'='*70}",
        f"ASL Practice Configuration Verification",
        f"{'='*70}",
        f"FINAL SCORE: {score}/{max_score}",
        f"STATUS: {'✅ PASS' if passed else '❌ FAIL'} (threshold: 70/100)",
        f"{'='*70}",
        "\nDetailed Scoring:",
        *[f"  {fb}" for fb in feedback_parts],
        f"\n{'='*70}",
        "\nConfiguration Checklist:",
        "  [ ] Playback speed: 60-70% (40pts)",
        "  [ ] Frame-step hotkeys: E/W or similar (20pts)",
        "  [ ] Bookmarks: 5 timestamps (30pts)",
        "  [ ] A-B loop: 2:15-2:18 (10pts, optional)",
        f"{'='*70}"
    ]
    
    return {
        "passed": passed,
        "score": score,
        "feedback": '\n'.join(feedback_summary)
    }


# Entry point for gym-anything
def verify_task(traj, env_info, task_info):
    """Standard entry point for task verification."""
    return verify_asl_practice_config(traj, env_info, task_info)