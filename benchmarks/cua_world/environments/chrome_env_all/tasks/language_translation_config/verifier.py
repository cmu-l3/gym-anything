#!/usr/bin/env python3
"""
Verifier for Chrome Language and Translation Configuration Task
Task: Add Spanish language, enable spell-check, disable auto-translation

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract language-related settings
- Verify Spanish is added to accept_languages
- Verify Spanish is in spell-check dictionaries
- Verify Spanish is in blocked translation languages
- Validate JSON structure integrity
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, Any, Tuple, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
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
    
    def cleanup_verification_temp():
        """Fallback cleanup function"""
        temp_dir = Path("/tmp/temp_chrome_verification")
        if temp_dir.exists():
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for language_translation_config@1.
    
    Verifies that:
    1. Spanish language was added to Chrome
    2. Spell-check is enabled for Spanish
    3. Auto-translation is disabled for Spanish
    4. Preferences file is valid JSON
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Extract preferences from container
        prefs_data, error_msg = extract_preferences(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract Chrome Preferences: {error_msg}"
            }
        
        # Perform verification checks
        verification_result = verify_language_configuration(prefs_data)
        
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


def extract_preferences(copy_from_env) -> Tuple[Dict[str, Any], str]:
    """
    Extract Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (preferences_dict, error_message)
    """
    temp_file = None
    
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
            try:
                success, files, error = setup_chrome_verification(
                    copy_from_env,
                    ["Preferences"],
                    user="ga",
                    profile="Default"
                )
                
                if success:
                    prefs_data = parse_preferences(files["Preferences"])
                    if prefs_data:
                        logger.info("✓ Successfully extracted preferences using utilities")
                        return prefs_data, ""
                    else:
                        logger.warning("Utility extraction returned empty preferences")
            except Exception as e:
                logger.warning(f"Utility-based extraction failed: {e}, trying fallback")
        
        # Fallback: Manual extraction from multiple possible locations
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        possible_locations = [
            "/tmp/chrome_preferences_export.json",
            "/tmp/language_prefs_backup.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences",
        ]
        
        for location in possible_locations:
            try:
                logger.info(f"Trying to copy Preferences from: {location}")
                copy_from_env(location, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    
                    logger.info(f"✓ Successfully copied and parsed Preferences from: {location}")
                    return prefs_data, ""
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {location}: {e}")
                continue
        
        # If we get here, none of the locations worked
        return None, "Could not access Preferences file from any known location"
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting preferences: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except Exception:
                pass


def check_spanish_in_languages(prefs_data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check if Spanish is in the accept_languages list.
    
    Args:
        prefs_data: Parsed Chrome Preferences
        
    Returns:
        Tuple of (is_present: bool, details: str)
    """
    try:
        # Navigate to intl.accept_languages
        intl_section = prefs_data.get('intl', {})
        accept_languages = intl_section.get('accept_languages', '')
        
        logger.info(f"accept_languages: {accept_languages}")
        
        # Check for various Spanish language codes
        # es = Spanish (generic)
        # es-ES = Spanish (Spain)
        # es-419 = Spanish (Latin America)
        # es-MX, es-AR, etc. = Country-specific variants
        
        spanish_patterns = [
            r'\bes\b',           # Just "es"
            r'\bes-[A-Z]{2}\b',  # es-XX (like es-ES, es-MX)
            r'\bes-\d{3}\b'      # es-419 (Latin America)
        ]
        
        accept_languages_lower = accept_languages.lower()
        
        for pattern in spanish_patterns:
            if re.search(pattern, accept_languages_lower):
                logger.info(f"✓ Found Spanish language code matching pattern: {pattern}")
                return True, f"Spanish found in accept_languages: {accept_languages}"
        
        return False, f"Spanish not found in accept_languages: {accept_languages}"
        
    except Exception as e:
        logger.error(f"Error checking accept_languages: {e}")
        return False, f"Error checking languages: {e}"


def check_spanish_spellcheck(prefs_data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check if Spanish spell-check is enabled.
    
    Args:
        prefs_data: Parsed Chrome Preferences
        
    Returns:
        Tuple of (is_enabled: bool, details: str)
    """
    try:
        # Navigate to spellcheck.dictionaries
        spellcheck_section = prefs_data.get('spellcheck', {})
        dictionaries = spellcheck_section.get('dictionaries', [])
        
        logger.info(f"spellcheck.dictionaries: {dictionaries}")
        
        # Check if any Spanish language code is in dictionaries
        spanish_patterns = [r'^es$', r'^es-[A-Z]{2}$', r'^es-\d{3}$']
        
        for dictionary in dictionaries:
            dict_lower = dictionary.lower()
            for pattern in spanish_patterns:
                if re.match(pattern, dict_lower):
                    logger.info(f"✓ Found Spanish in spell-check dictionaries: {dictionary}")
                    return True, f"Spanish spell-check enabled: {dictionary}"
        
        return False, f"Spanish not found in spell-check dictionaries: {dictionaries}"
        
    except Exception as e:
        logger.error(f"Error checking spell-check dictionaries: {e}")
        return False, f"Error checking spell-check: {e}"


def check_spanish_translation_blocked(prefs_data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check if Spanish is in the blocked translation languages list.
    
    Args:
        prefs_data: Parsed Chrome Preferences
        
    Returns:
        Tuple of (is_blocked: bool, details: str)
    """
    try:
        # Navigate to translate_blocked_languages
        blocked_languages = prefs_data.get('translate_blocked_languages', [])
        
        logger.info(f"translate_blocked_languages: {blocked_languages}")
        
        # Check if any Spanish language code is in blocked list
        spanish_patterns = [r'^es$', r'^es-[A-Z]{2}$', r'^es-\d{3}$']
        
        for blocked_lang in blocked_languages:
            blocked_lower = blocked_lang.lower()
            for pattern in spanish_patterns:
                if re.match(pattern, blocked_lower):
                    logger.info(f"✓ Found Spanish in blocked translation languages: {blocked_lang}")
                    return True, f"Spanish auto-translation disabled: {blocked_lang}"
        
        return False, f"Spanish not found in blocked translation languages: {blocked_languages}"
        
    except Exception as e:
        logger.error(f"Error checking blocked translation languages: {e}")
        return False, f"Error checking translation settings: {e}"


def verify_language_configuration(prefs_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify all language configuration criteria.
    
    Checks:
    1. Spanish added to accept_languages
    2. Spanish in spell-check dictionaries
    3. Spanish in blocked translation languages
    4. Preferences file is valid (already confirmed by parsing)
    
    Scoring:
    - 100%: All 4 criteria met
    - 75-99%: 3/4 criteria met (passing)
    - 50-74%: 2/4 criteria met (failing)
    - <50%: <2 criteria met (failing)
    
    Pass threshold: 75% (at least 3 out of 4 criteria)
    
    Args:
        prefs_data: Parsed Chrome Preferences dictionary
        
    Returns:
        Verification result with passed, score, and feedback
    """
    criteria_results = {}
    feedback_parts = []
    
    # Criterion 1: Spanish in accept_languages
    spanish_added, lang_details = check_spanish_in_languages(prefs_data)
    criteria_results['spanish_in_languages'] = spanish_added
    
    if spanish_added:
        feedback_parts.append(f"✓ Spanish added to languages: {lang_details}")
    else:
        feedback_parts.append(f"✗ Spanish NOT in languages: {lang_details}")
    
    # Criterion 2: Spanish spell-check enabled
    spellcheck_enabled, spell_details = check_spanish_spellcheck(prefs_data)
    criteria_results['spanish_spell_check'] = spellcheck_enabled
    
    if spellcheck_enabled:
        feedback_parts.append(f"✓ Spanish spell-check enabled: {spell_details}")
    else:
        feedback_parts.append(f"✗ Spanish spell-check NOT enabled: {spell_details}")
    
    # Criterion 3: Spanish translation blocked
    translation_blocked, trans_details = check_spanish_translation_blocked(prefs_data)
    criteria_results['spanish_translation_blocked'] = translation_blocked
    
    if translation_blocked:
        feedback_parts.append(f"✓ Spanish auto-translation disabled: {trans_details}")
    else:
        feedback_parts.append(f"✗ Spanish auto-translation NOT disabled: {trans_details}")
    
    # Criterion 4: Preferences file valid (implicitly true if we got here)
    prefs_valid = bool(prefs_data)
    criteria_results['preferences_valid'] = prefs_valid
    
    if prefs_valid:
        feedback_parts.append("✓ Preferences file valid and parseable")
    else:
        feedback_parts.append("✗ Preferences file invalid or empty")
    
    # Calculate score
    criteria_met = sum(criteria_results.values())
    total_criteria = len(criteria_results)
    score = int((criteria_met / total_criteria) * 100)
    passed = criteria_met >= 3  # Need at least 3/4 criteria (75%)
    
    # Build feedback
    feedback = f"Language Configuration Verification: {criteria_met}/{total_criteria} criteria met\n"
    feedback += "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}\n"
    feedback += f"Final Score: {score}%\n"
    feedback += f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}\n"
    
    if not passed:
        feedback += "\nTo complete this task successfully:\n"
        if not spanish_added:
            feedback += "  - Navigate to chrome://settings/languages and add Spanish\n"
        if not spellcheck_enabled:
            feedback += "  - Enable spell-check for Spanish in language settings\n"
        if not translation_blocked:
            feedback += "  - Disable 'Offer to translate' for Spanish in language settings\n"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria": criteria_results,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "spanish_added": spanish_added,
            "spellcheck_enabled": spellcheck_enabled,
            "translation_blocked": translation_blocked
        }
    }
