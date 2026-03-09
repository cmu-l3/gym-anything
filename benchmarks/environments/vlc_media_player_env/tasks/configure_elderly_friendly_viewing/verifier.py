#!/usr/bin/env python3
"""
Verifier for Configure Elderly-Friendly Viewing task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_elderly_friendly_config(config):
    """
    Verify all elderly-friendly settings are configured.
    
    Checks 6 criteria:
    1. Subtitle size increased significantly
    2. Subtitle styling (bold)
    3. Audio normalization
    4. Audio compression
    5. Interface simplification
    6. Prompts disabled
    
    Returns: (score, max_score, feedback_list)
    """
    
    score = 0
    max_score = 6
    feedback = []
    
    # Criterion 1: Subtitle size (CRITICAL)
    font_size = int(config.get('freetype-fontsize', 0))
    rel_font_size = int(config.get('freetype-rel-fontsize', 16))  # 16 is default
    
    # Check if either absolute or relative font size is large enough
    # Absolute: ≥72pt, Relative: ≥40 (default is 16, so 40 is ~2.5x)
    if font_size >= 72:
        score += 1
        feedback.append(f"✅ Subtitle size significantly increased (absolute: {font_size}pt)")
    elif rel_font_size >= 40:
        score += 1
        feedback.append(f"✅ Subtitle size significantly increased (relative: {rel_font_size})")
    else:
        feedback.append(f"❌ Subtitle size too small (fontsize={font_size}pt, rel={rel_font_size}). Need ≥72pt or rel≥40 for elderly readability")
    
    # Criterion 2: Subtitle styling - bold (IMPORTANT)
    bold = config.get('freetype-bold', '0')
    if bold == '1':
        score += 1
        feedback.append("✅ Subtitle text bold enabled for better visibility")
    else:
        feedback.append("❌ Subtitles not bold - harder to read for elderly users")
    
    # Criterion 3: Audio normalization (CRITICAL)
    # Multiple ways to enable this in VLC
    norm_level = config.get('norm-max-level', '')
    replay_gain = config.get('audio-replay-gain-mode', '')
    audio_normalizer = config.get('audio-filter', '')
    
    normalization_enabled = False
    if norm_level:
        normalization_enabled = True
        norm_method = f"norm-max-level={norm_level}"
    elif replay_gain and replay_gain != 'none':
        normalization_enabled = True
        norm_method = f"replay-gain={replay_gain}"
    elif 'normvol' in audio_normalizer:
        normalization_enabled = True
        norm_method = "audio-filter includes normvol"
    
    if normalization_enabled:
        score += 1
        feedback.append(f"✅ Audio normalization enabled ({norm_method}) - prevents volume jumps")
    else:
        feedback.append("❌ Audio normalization not enabled - volumes will vary between videos, frustrating elderly users")
    
    # Criterion 4: Audio compression/night mode (IMPORTANT for dialogue)
    compressor = config.get('audio-compressor', '0')
    compressor_ratio = config.get('compressor-ratio', '')
    compressor_attack = config.get('compressor-attack', '')
    audio_filter = config.get('audio-filter', '')
    
    compression_enabled = False
    if compressor == '1':
        compression_enabled = True
        comp_method = "audio-compressor=1"
    elif compressor_ratio:
        compression_enabled = True
        comp_method = f"compressor-ratio={compressor_ratio}"
    elif 'compressor' in audio_filter:
        compression_enabled = True
        comp_method = "audio-filter includes compressor"
    # norm-max-level also provides some compression
    elif norm_level:
        compression_enabled = True
        comp_method = "via norm-max-level"
    
    if compression_enabled:
        score += 1
        feedback.append(f"✅ Audio compression enabled ({comp_method}) - enhances dialogue clarity")
    else:
        feedback.append("❌ Audio compression not enabled - dialogue may be hard to hear over background sounds")
    
    # Criterion 5: Interface simplification (HELPFUL)
    minimal_view = config.get('qt-minimal-view', '0')
    privacy_ask = config.get('qt-privacy-ask', '1')  # 1 is default (asks), 0 is disabled
    simple_prefs = config.get('qt-simple-prefs-show', '1')
    
    interface_simplified = False
    if minimal_view == '1':
        interface_simplified = True
        simple_method = "minimal-view enabled"
    elif privacy_ask == '0':
        interface_simplified = True
        simple_method = "privacy prompts disabled"
    
    if interface_simplified:
        score += 1
        feedback.append(f"✅ Interface simplified ({simple_method}) - reduces confusion")
    else:
        feedback.append("⚠️ Interface not simplified - may be overwhelming for elderly users")
    
    # Criterion 6: Prompts/notifications disabled (HELPFUL)
    updates_notif = config.get('qt-updates-notif', '1')  # 1 is default (enabled)
    privacy_ask = config.get('qt-privacy-ask', '1')
    
    prompts_disabled = False
    if privacy_ask == '0' and updates_notif == '0':
        prompts_disabled = True
        prompt_method = "both privacy and update prompts disabled"
    elif privacy_ask == '0':
        prompts_disabled = True
        prompt_method = "privacy prompts disabled"
        score += 0.5  # Partial credit
    elif updates_notif == '0':
        prompts_disabled = True
        prompt_method = "update prompts disabled"
        score += 0.5  # Partial credit
    
    if prompts_disabled and privacy_ask == '0' and updates_notif == '0':
        score += 1
        feedback.append(f"✅ Prompts disabled ({prompt_method}) - prevents confusing dialogs")
    elif prompts_disabled:
        feedback.append(f"⚠️ Some prompts disabled ({prompt_method}) - partial credit")
    else:
        feedback.append("⚠️ Prompts still enabled - may cause confusion for elderly users")
    
    return score, max_score, feedback


def verify_configure_elderly_friendly(traj, env_info, task_info):
    """
    Main verification function for configure_elderly_friendly_viewing task.
    
    Checks:
    1. VLC config file exists and is parseable
    2. Required elderly-friendly settings are configured
    3. At least 4/6 criteria met (67% threshold)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Copy VLC config from container
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        # Copy config file
        copy_from_env("/tmp/vlc_elderly_config.txt", temp_config.name)
        logger.info(f"Copied VLC config to {temp_config.name}")
        
    except Exception as e:
        logger.error(f"Error copying VLC config: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"VLC config file not found or not accessible: {str(e)}"
        }
    
    # Parse VLC config
    try:
        config = parse_vlc_config(temp_config.name)
        
        if not config:
            os.unlink(temp_config.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "VLC config file is empty or could not be parsed"
            }
        
        logger.info(f"Parsed VLC config with {len(config)} entries")
        
    except Exception as e:
        logger.error(f"Error parsing VLC config: {e}", exc_info=True)
        os.unlink(temp_config.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error parsing VLC config: {str(e)}"
        }
    
    # Verify elderly-friendly configuration
    try:
        criteria_score, max_criteria, feedback_list = verify_elderly_friendly_config(config)
        
        logger.info(f"Configuration score: {criteria_score}/{max_criteria}")
        
    except Exception as e:
        logger.error(f"Error verifying config: {e}", exc_info=True)
        os.unlink(temp_config.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error during verification: {str(e)}"
        }
    
    # Cleanup
    os.unlink(temp_config.name)
    
    # Calculate final score (out of 100)
    score_percent = int((criteria_score / max_criteria) * 100)
    
    # Pass threshold: at least 4/6 criteria (67%)
    passed = criteria_score >= 4
    
    # Build feedback string
    feedback_header = f"Configuration score: {criteria_score}/{max_criteria} ({score_percent}%)\n\n"
    feedback_body = "\n".join(feedback_list)
    
    if passed:
        feedback_conclusion = "\n\n✅ VLC successfully configured for elderly-friendly viewing!"
    else:
        feedback_conclusion = f"\n\n❌ Need at least 4/6 criteria. Missing critical settings for elderly accessibility."
    
    full_feedback = feedback_header + feedback_body + feedback_conclusion
    
    return {
        "passed": passed,
        "score": score_percent,
        "feedback": full_feedback,
        "criteria_met": criteria_score,
        "criteria_total": max_criteria
    }