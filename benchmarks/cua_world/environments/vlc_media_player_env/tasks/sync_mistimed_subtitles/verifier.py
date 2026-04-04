#!/usr/bin/env python3
"""
Verifier for sync_mistimed_subtitles task.

Checks that VLC subtitle delay has been correctly configured to fix
subtitles that appear 2.5 seconds too early (requires +2.5s delay).
"""

import sys
import os
import logging
import tempfile
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


def verify_subtitle_sync(traj, env_info, task_info):
    """
    Verify that subtitle delay has been correctly configured in VLC.
    
    The task requires fixing subtitles that appear 2.5 seconds too early,
    which requires setting a positive delay of approximately +2.5 seconds
    (+2,500,000 microseconds in VLC's internal format).
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info dict with 'copy_from_env' function
        task_info: Task info dict (unused)
        
    Returns:
        dict with 'passed', 'score', and 'feedback' keys
    """
    try:
        copy_from_env = env_info.get('copy_from_env')
        if not copy_from_env:
            logger.error("copy_from_env function not available")
            return {
                'passed': False,
                'score': 0,
                'feedback': "Environment interface error: copy_from_env not available"
            }
        
        # Define expected values
        EXPECTED_DELAY_SECONDS = 2.5
        TOLERANCE_SECONDS = 0.3  # Allow ±300ms tolerance
        
        # Calculate acceptable range in microseconds
        MIN_DELAY_US = int((EXPECTED_DELAY_SECONDS - TOLERANCE_SECONDS) * 1_000_000)
        MAX_DELAY_US = int((EXPECTED_DELAY_SECONDS + TOLERANCE_SECONDS) * 1_000_000)
        
        logger.info("=" * 60)
        logger.info("Verifying Subtitle Synchronization Task")
        logger.info("=" * 60)
        logger.info(f"Expected delay: {EXPECTED_DELAY_SECONDS}s ± {TOLERANCE_SECONDS}s")
        logger.info(f"Acceptable range: {MIN_DELAY_US:,} to {MAX_DELAY_US:,} microseconds")
        logger.info(f"Acceptable range: {MIN_DELAY_US/1_000_000:.2f}s to {MAX_DELAY_US/1_000_000:.2f}s")
        
        # Copy VLC config file from container
        temp_config = tempfile.NamedTemporaryFile(mode='w+', delete=False, suffix='.txt')
        temp_config_path = temp_config.name
        temp_config.close()
        
        try:
            copy_from_env("/tmp/vlc_subtitle_sync_config.txt", temp_config_path)
            logger.info(f"✅ Successfully copied VLC config to {temp_config_path}")
        except Exception as e:
            logger.error(f"Failed to copy VLC config: {e}")
            # Try alternative path
            try:
                copy_from_env("/tmp/vlcrc", temp_config_path)
                logger.info(f"✅ Successfully copied VLC config from /tmp/vlcrc")
            except Exception as e2:
                logger.error(f"Failed to copy VLC config from alternative path: {e2}")
                return {
                    'passed': False,
                    'score': 0,
                    'feedback': f"Could not access VLC configuration file. Task may not have run. Error: {str(e)}"
                }
        
        # Check if config file exists and has content
        if not os.path.exists(temp_config_path) or os.path.getsize(temp_config_path) == 0:
            logger.error("VLC config file is empty or doesn't exist")
            os.unlink(temp_config_path)
            return {
                'passed': False,
                'score': 0,
                'feedback': "VLC configuration file is empty. VLC may not have been used or settings not saved."
            }
        
        # Parse VLC configuration
        logger.info("Parsing VLC configuration...")
        config = parse_vlc_config(temp_config_path)
        
        if not config:
            logger.warning("Could not parse VLC config or config is empty")
            os.unlink(temp_config_path)
            return {
                'passed': False,
                'score': 0,
                'feedback': "Could not parse VLC configuration file or config is empty."
            }
        
        logger.info(f"Parsed VLC config with {len(config)} settings")
        
        # Look for subtitle delay settings
        # VLC can use different keys: spu-delay, sub-delay, audio-desync
        delay_us = None
        delay_key = None
        
        # Check common subtitle delay keys
        SUBTITLE_DELAY_KEYS = ['spu-delay', 'sub-delay', 'audio-desync', 'subsdelay-delay']
        
        for key in SUBTITLE_DELAY_KEYS:
            if key in config:
                try:
                    delay_us = int(config[key])
                    delay_key = key
                    logger.info(f"✓ Found subtitle delay setting: {key}={delay_us:,} microseconds")
                    break
                except (ValueError, TypeError) as e:
                    logger.warning(f"Could not parse {key} value: {config[key]} - {e}")
                    continue
        
        if delay_us is None:
            # No subtitle delay found - check if any subtitle-related settings exist
            subtitle_keys = [k for k in config.keys() if 'sub' in k.lower() or 'spu' in k.lower()]
            logger.warning(f"No subtitle delay found. Subtitle-related keys in config: {subtitle_keys}")
            
            os.unlink(temp_config_path)
            return {
                'passed': False,
                'score': 0,
                'feedback': (
                    "No subtitle delay setting found in VLC configuration. "
                    "The subtitle synchronization was not adjusted. "
                    "Try using: (1) H key to increase delay, (2) Tools → Track Synchronization menu, "
                    "or (3) Tools → Preferences → All → Input/Codecs → Subtitle codecs."
                )
            }
        
        # Convert to seconds for readable feedback
        delay_seconds = delay_us / 1_000_000
        
        logger.info(f"Subtitle delay: {delay_us:,} microseconds ({delay_seconds:.3f} seconds)")
        logger.info(f"Expected range: {MIN_DELAY_US:,} to {MAX_DELAY_US:,} microseconds")
        
        # Clean up temp file
        os.unlink(temp_config_path)
        
        # Evaluate the delay value
        if MIN_DELAY_US <= delay_us <= MAX_DELAY_US:
            # Perfect! Delay is in correct range
            logger.info("✓✓✓ Subtitle delay is correctly configured!")
            return {
                'passed': True,
                'score': 100,
                'feedback': (
                    f"✅ Perfect! Subtitle delay correctly set to {delay_seconds:.2f} seconds "
                    f"({delay_us:,} microseconds). "
                    f"This compensates for the 2.5-second early timing issue. "
                    f"The subtitles should now sync properly with the video content. "
                    f"Setting found: {delay_key}={delay_us} μs"
                )
            }
        
        # Delay is set but not in correct range - provide specific feedback
        elif delay_us < MIN_DELAY_US:
            # Delay too small (or negative)
            if delay_us < 0:
                logger.warning(f"Subtitle delay is NEGATIVE: {delay_us} ({delay_seconds:.2f}s)")
                return {
                    'passed': False,
                    'score': 15,
                    'feedback': (
                        f"❌ Subtitle delay is NEGATIVE ({delay_seconds:.2f}s / {delay_us:,} μs). "
                        f"Since subtitles appear TOO EARLY, you need POSITIVE delay (+2.5s), "
                        f"not negative delay. A negative delay makes subtitles appear even earlier! "
                        f"Direction error: You went the wrong way. "
                        f"Try using the H key (not G) to INCREASE delay, or set to +2500ms in menu."
                    )
                }
            elif delay_us == 0:
                logger.warning("Subtitle delay is set to zero")
                return {
                    'passed': False,
                    'score': 10,
                    'feedback': (
                        f"❌ Subtitle delay is set to 0 (no delay). "
                        f"The subtitles appear 2.5 seconds too early, so you need approximately "
                        f"+2.5 seconds (+2,500,000 μs) of positive delay to fix the timing. "
                        f"Use the H key or Tools → Track Synchronization to add delay."
                    )
                }
            else:
                # Positive but too small
                shortfall = EXPECTED_DELAY_SECONDS - delay_seconds
                progress_pct = int((delay_us / MIN_DELAY_US) * 100)
                logger.warning(f"Subtitle delay too small: {delay_us} ({delay_seconds:.2f}s)")
                return {
                    'passed': False,
                    'score': min(60, progress_pct),
                    'feedback': (
                        f"⚠️ Subtitle delay is set to {delay_seconds:.2f}s ({delay_us:,} μs), "
                        f"but this is too small. "
                        f"The subtitles appear 2.5 seconds too early, so you need approximately "
                        f"+2.5 seconds of delay. Your current setting of {delay_seconds:.2f}s "
                        f"would only partially fix the problem. "
                        f"Increase the delay by about {shortfall:.2f}s more. "
                        f"({int(shortfall * 1_000_000):,} microseconds more needed)"
                    )
                }
        
        else:  # delay_us > MAX_DELAY_US
            # Delay too large
            excess = delay_seconds - EXPECTED_DELAY_SECONDS
            logger.warning(f"Subtitle delay too large: {delay_us} ({delay_seconds:.2f}s)")
            return {
                'passed': False,
                'score': 50,
                'feedback': (
                    f"⚠️ Subtitle delay is set to {delay_seconds:.2f}s ({delay_us:,} μs), "
                    f"but this is too much. "
                    f"The subtitles only appear 2.5 seconds too early, so a delay of "
                    f"approximately +2.5 seconds is needed. Your current setting of "
                    f"{delay_seconds:.2f}s would make subtitles appear TOO LATE "
                    f"(overcompensating by {excess:.2f}s). "
                    f"Decrease the delay by about {excess:.2f}s. "
                    f"Target: ~2,500,000 microseconds (2.5 seconds)"
                )
            }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            'passed': False,
            'score': 0,
            'feedback': f"Verification failed with error: {type(e).__name__}: {str(e)}"
        }
