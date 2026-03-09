#!/usr/bin/env python3
"""
Verifier for Chrome Spell Check Configuration and Custom Dictionary Task
Task: Configure Chrome's spell check for English and add custom words to dictionary

Verification Strategy:
- Copy Chrome Preferences file to verify spell check configuration
- Copy Custom Dictionary.txt to verify custom words were added
- Multi-criteria verification:
  1. Spell check is enabled in settings
  2. English language is configured for spell checking
  3. Custom Dictionary file exists and was modified recently
  4. At least one custom word was added to the dictionary
  5. Custom dictionary file format is valid
"""

import logging
import sys
import os
import json
import tempfile
import time
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
try:
    from chrome_verification_utils import (
        copy_chrome_file,
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
    Main verification function for spellcheck_custom_dictionary@1.
    
    Verifies:
    1. Spell check is enabled (browser.enable_spellchecking = true)
    2. English language configured (spellcheck.dictionaries contains "en")
    3. Custom Dictionary file exists and was recently modified
    4. At least 1 custom word added to dictionary
    5. Dictionary file format is valid (proper text format)
    
    Scoring:
    - 100%: All 5 criteria met (perfect configuration)
    - 75-99%: 4/5 criteria met (minor issue, still passing)
    - 50-74%: 3/5 criteria met (partial success, failing)
    - 25-49%: 2/5 criteria met (significant issues)
    - 0-24%: 0-1 criteria met (task failed)
    
    Pass threshold: 75% (requires at least 4 out of 5 criteria)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration info
        
    Returns:
        Dict with passed, score, feedback, and details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }
    
    try:
        # Get spell check configuration from Preferences
        prefs_data, prefs_error = get_preferences_data(copy_from_env)
        
        # Get custom dictionary data
        dict_data, dict_error = get_custom_dictionary_data(copy_from_env)
        
        # Perform multi-criteria verification
        verification_result = verify_spellcheck_configuration(
            prefs_data, 
            dict_data,
            prefs_error,
            dict_error
        )
        
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


def get_preferences_data(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Retrieve Chrome Preferences file and parse spell check settings.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (preferences_dict or None, error_message)
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences_spellcheck.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    return prefs_data, ""
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        return None, "Could not access Preferences file from any known location"
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error getting Preferences: {e}"
    finally:
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def get_custom_dictionary_data(copy_from_env) -> Tuple[Optional[List[str]], str]:
    """
    Retrieve Chrome Custom Dictionary file and parse word list.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (word_list or None, error_message)
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_custom_dictionary.txt",
            "/home/ga/.config/google-chrome-cdp/Default/Custom Dictionary.txt",
            "/home/ga/.config/google-chrome/Default/Custom Dictionary.txt"
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Custom Dictionary from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file exists and has content
                if os.path.exists(temp_path):
                    file_size = os.path.getsize(temp_path)
                    mod_time = os.path.getmtime(temp_path)
                    
                    # Read words from dictionary
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        words = [line.strip() for line in f if line.strip()]
                    
                    logger.info(f"✓ Successfully loaded Custom Dictionary from: {container_path}")
                    logger.info(f"  File size: {file_size} bytes, Words: {len(words)}")
                    
                    return words, ""
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        return None, "Could not access Custom Dictionary file from any known location"
        
    except Exception as e:
        return None, f"Error getting Custom Dictionary: {e}"
    finally:
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def verify_spellcheck_configuration(
    prefs_data: Optional[Dict],
    dict_words: Optional[List[str]],
    prefs_error: str,
    dict_error: str
) -> Dict[str, Any]:
    """
    Verify spell check configuration and custom dictionary.
    
    Args:
        prefs_data: Parsed Chrome Preferences data
        dict_words: List of words from Custom Dictionary
        prefs_error: Error message from preferences retrieval
        dict_error: Error message from dictionary retrieval
        
    Returns:
        Verification result with passed, score, feedback, and details
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Spell check is enabled
    spellcheck_enabled = False
    if prefs_data:
        spellcheck_enabled = prefs_data.get('browser', {}).get('enable_spellchecking', False)
    
    if spellcheck_enabled:
        feedback_parts.append("✓ Spell check is enabled")
        criteria_met += 1
        logger.info("Criterion 1: PASS - Spell check enabled")
    else:
        if prefs_data:
            feedback_parts.append("✗ Spell check is not enabled in settings")
        else:
            feedback_parts.append(f"✗ Could not verify spell check settings: {prefs_error}")
        logger.info("Criterion 1: FAIL - Spell check not enabled")
    
    # Criterion 2: English language configured
    english_configured = False
    spell_languages = []
    
    if prefs_data:
        spell_languages = prefs_data.get('spellcheck', {}).get('dictionaries', [])
        # Check if any English variant is configured (en-US, en-GB, en, etc.)
        english_configured = any('en' in lang.lower() for lang in spell_languages)
    
    if english_configured:
        feedback_parts.append(f"✓ English spell check configured: {spell_languages}")
        criteria_met += 1
        logger.info(f"Criterion 2: PASS - English configured: {spell_languages}")
    else:
        if prefs_data:
            feedback_parts.append(f"✗ English not configured for spell check (found: {spell_languages})")
        else:
            feedback_parts.append("✗ Could not verify spell check language configuration")
        logger.info(f"Criterion 2: FAIL - English not configured")
    
    # Criterion 3: Custom Dictionary file exists and was modified
    dict_exists = dict_words is not None
    
    if dict_exists:
        feedback_parts.append("✓ Custom Dictionary file exists")
        criteria_met += 1
        logger.info("Criterion 3: PASS - Dictionary file exists")
    else:
        feedback_parts.append(f"✗ Custom Dictionary file not found: {dict_error}")
        logger.info("Criterion 3: FAIL - Dictionary file not found")
    
    # Criterion 4: At least one custom word added
    has_custom_words = False
    word_count = 0
    
    if dict_words is not None:
        word_count = len(dict_words)
        has_custom_words = word_count >= 1
    
    if has_custom_words:
        word_preview = ', '.join(dict_words[:5])
        if word_count > 5:
            word_preview += f", ... ({word_count - 5} more)"
        feedback_parts.append(f"✓ Custom dictionary contains {word_count} word(s): {word_preview}")
        criteria_met += 1
        logger.info(f"Criterion 4: PASS - {word_count} custom word(s) added")
    else:
        if dict_exists:
            feedback_parts.append("✗ No custom words added to dictionary")
        else:
            feedback_parts.append("✗ Cannot verify custom words (dictionary file missing)")
        logger.info("Criterion 4: FAIL - No custom words")
    
    # Criterion 5: Dictionary file format is valid
    format_valid = False
    
    if dict_words is not None:
        # Check format validity:
        # - Words should be non-empty strings
        # - Words should not contain invalid characters
        # - Each word should be reasonable length
        format_valid = all(
            word and 
            len(word) > 0 and 
            len(word) < 100 and
            isinstance(word, str)
            for word in dict_words
        )
    
    if format_valid:
        feedback_parts.append("✓ Dictionary file format is valid")
        criteria_met += 1
        logger.info("Criterion 5: PASS - Dictionary format valid")
    else:
        if dict_exists:
            feedback_parts.append("✗ Dictionary file has invalid format")
        else:
            feedback_parts.append("✗ Cannot verify dictionary format (file missing)")
        logger.info("Criterion 5: FAIL - Dictionary format invalid or not verified")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 4/5 criteria
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if passed:
        feedback += "\n\n✅ Spell check configuration and custom dictionary successfully set up!"
    else:
        feedback += "\n\n❌ Task incomplete - ensure spell check is enabled AND custom words are added"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "spellcheck_enabled": spellcheck_enabled,
            "english_configured": english_configured,
            "spell_languages": spell_languages,
            "dictionary_exists": dict_exists,
            "custom_word_count": word_count,
            "custom_words": dict_words if dict_words else [],
            "format_valid": format_valid,
            "criteria_met": criteria_met,
            "criteria_total": total_criteria
        }
    }
