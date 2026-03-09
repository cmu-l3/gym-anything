#!/usr/bin/env python3
"""
Verifier for Chrome Page Translation Task: page_translation@1
Task: Translate a Spanish language webpage to English using Chrome's built-in translation

Verification Strategy:
- Compare initial (Spanish) and final (should be English) page titles
- Use multiple language detection methods (heuristics, keyword matching)
- Check for expected translated terms
- Verify URL remained the same (same page, just translated)
- Analyze character distribution (Spanish has more accented characters)
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp, parse_preferences
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass

# Try to import langdetect library (may not be available)
try:
    from langdetect import detect, LangDetectException
    LANGDETECT_AVAILABLE = True
except ImportError:
    LANGDETECT_AVAILABLE = False
    logger.info("langdetect library not available, using heuristic detection only")


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for page_translation@1 task.
    
    Verifies that:
    1. Page language changed from Spanish to English (title analysis)
    2. Page content changed (title text is different)
    3. URL remained the same (same page, just translated)
    4. English keywords present in final title
    5. Spanish keywords absent from final title
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
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
        # Extract initial and final page states
        initial_title, final_title, final_url = get_page_states(copy_from_env)
        
        if final_title is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve final page state from Chrome CDP"
            }
        
        # Perform multi-criteria verification
        verification_result = verify_translation(initial_title, final_title, final_url)
        
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


def get_page_states(copy_from_env) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """
    Extract initial and final page states from exported files.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (initial_title, final_title, final_url)
    """
    initial_title = None
    final_title = None
    final_url = None
    
    temp_files = []
    
    try:
        # Get initial title
        try:
            temp_initial = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
            temp_files.append(temp_initial.name)
            temp_initial.close()
            
            copy_from_env("/tmp/initial_title.txt", temp_initial.name)
            with open(temp_initial.name, 'r', encoding='utf-8') as f:
                initial_title = f.read().strip()
            logger.info(f"Initial title: {initial_title}")
        except Exception as e:
            logger.warning(f"Could not get initial title: {e}")
            initial_title = None
        
        # Get final title
        try:
            temp_final = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
            temp_files.append(temp_final.name)
            temp_final.close()
            
            copy_from_env("/tmp/final_title.txt", temp_final.name)
            with open(temp_final.name, 'r', encoding='utf-8') as f:
                final_title = f.read().strip()
            logger.info(f"Final title: {final_title}")
        except Exception as e:
            logger.error(f"Could not get final title: {e}")
            return None, None, None
        
        # Get final URL
        try:
            temp_url = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
            temp_files.append(temp_url.name)
            temp_url.close()
            
            copy_from_env("/tmp/final_url.txt", temp_url.name)
            with open(temp_url.name, 'r', encoding='utf-8') as f:
                final_url = f.read().strip()
            logger.info(f"Final URL: {final_url}")
        except Exception as e:
            logger.warning(f"Could not get final URL: {e}")
            final_url = None
        
        return initial_title, final_title, final_url
        
    finally:
        # Clean up temp files
        for temp_file in temp_files:
            try:
                if os.path.exists(temp_file):
                    os.unlink(temp_file)
            except:
                pass


def simple_language_detect(text: str) -> str:
    """
    Simple heuristic language detection based on common words.
    
    Args:
        text: Text to analyze
        
    Returns:
        'en' for English, 'es' for Spanish, 'unknown' if uncertain
    """
    if not text:
        return 'unknown'
    
    text_lower = text.lower()
    
    # Common English words
    english_words = ['the', 'is', 'are', 'and', 'to', 'of', 'in', 'for', 'artificial', 'intelligence']
    # Common Spanish words
    spanish_words = ['el', 'la', 'los', 'las', 'es', 'de', 'que', 'por', 'inteligencia', 'artificial']
    
    english_score = sum(word in text_lower for word in english_words)
    spanish_score = sum(word in text_lower for word in spanish_words)
    
    logger.info(f"Language detection - English score: {english_score}, Spanish score: {spanish_score}")
    
    if english_score > spanish_score * 1.5:
        return 'en'
    elif spanish_score > english_score * 1.5:
        return 'es'
    
    return 'unknown'


def detect_language(text: str) -> str:
    """
    Detect language using available methods.
    
    Args:
        text: Text to analyze
        
    Returns:
        Language code ('en', 'es', 'unknown')
    """
    # Try langdetect library if available
    if LANGDETECT_AVAILABLE and text:
        try:
            detected = detect(text)
            logger.info(f"langdetect result: {detected}")
            return detected
        except LangDetectException as e:
            logger.warning(f"langdetect failed: {e}")
    
    # Fall back to heuristic detection
    return simple_language_detect(text)


def analyze_character_distribution(text: str) -> Dict[str, Any]:
    """
    Analyze character distribution to help identify language.
    
    Spanish has specific accented characters: á, é, í, ó, ú, ñ, ¿, ¡
    
    Args:
        text: Text to analyze
        
    Returns:
        Dict with character analysis metrics
    """
    if not text:
        return {'spanish_specific': 0, 'total_alpha': 0, 'spanish_ratio': 0.0}
    
    spanish_chars = 'áéíóúñ¿¡'
    text_lower = text.lower()
    
    total_alpha = sum(c.isalpha() for c in text)
    spanish_specific = sum(c in spanish_chars for c in text_lower)
    
    spanish_ratio = spanish_specific / max(total_alpha, 1)
    
    return {
        'spanish_specific': spanish_specific,
        'total_alpha': total_alpha,
        'spanish_ratio': spanish_ratio
    }


def check_translation_keywords(initial_title: str, final_title: str) -> Tuple[bool, bool]:
    """
    Check for specific expected translation patterns.
    
    For the AI article:
    - Spanish: "Inteligencia artificial"
    - English: "Artificial intelligence"
    
    Args:
        initial_title: Original Spanish title
        final_title: Translated English title
        
    Returns:
        Tuple of (has_english_keywords, lacks_spanish_keywords)
    """
    if not final_title:
        return False, False
    
    final_lower = final_title.lower()
    
    # Check for English keywords
    english_keywords = ['artificial intelligence', 'artificial', 'intelligence']
    has_english = any(kw in final_lower for kw in english_keywords)
    
    # Check that Spanish keywords are absent
    spanish_keywords = ['inteligencia artificial', 'inteligencia']
    lacks_spanish = not any(kw in final_lower for kw in spanish_keywords)
    
    logger.info(f"Keyword check - Has English: {has_english}, Lacks Spanish: {lacks_spanish}")
    
    return has_english, lacks_spanish


def verify_url_unchanged(final_url: str, expected_base: str = "es.wikipedia.org/wiki/Inteligencia_artificial") -> bool:
    """
    Verify that URL is still the Spanish Wikipedia article (translation doesn't change URL).
    
    Args:
        final_url: Final page URL
        expected_base: Expected URL base
        
    Returns:
        True if URL is correct
    """
    if not final_url:
        return False
    
    final_lower = final_url.lower()
    return expected_base.lower() in final_lower


def verify_translation(initial_title: Optional[str], final_title: str, final_url: Optional[str]) -> Dict[str, Any]:
    """
    Verify that page translation was successful.
    
    Verification criteria (5 total, need 4+ to pass):
    1. Title changed from initial (content was modified)
    2. Final title is in English (language detection)
    3. English keywords present in final title
    4. Spanish keywords absent from final title
    5. URL unchanged (still on Spanish Wikipedia page)
    
    Args:
        initial_title: Original Spanish title (may be None)
        final_title: Final page title
        final_url: Final page URL
        
    Returns:
        Verification result dict
    """
    criteria_results = []
    feedback_parts = []
    
    # Criterion 1: Title changed (content was modified)
    title_changed = False
    if initial_title and final_title:
        title_changed = initial_title != final_title
        logger.info(f"Title change check: {title_changed}")
        criteria_results.append(title_changed)
        if title_changed:
            feedback_parts.append(f"✓ Title changed (content modified)")
        else:
            feedback_parts.append(f"✗ Title unchanged (no translation detected)")
    else:
        # Can't verify without initial title, give partial credit if other checks pass
        logger.warning("Initial title not available, skipping title change check")
        feedback_parts.append(f"⚠ Title change not verifiable (no initial state)")
    
    # Criterion 2: Final title is in English
    detected_lang = detect_language(final_title)
    is_english = detected_lang == 'en'
    criteria_results.append(is_english)
    logger.info(f"Language detection: {detected_lang} (is_english: {is_english})")
    
    if is_english:
        feedback_parts.append(f"✓ Page language detected as English")
    else:
        feedback_parts.append(f"✗ Page language detected as '{detected_lang}' (expected 'en')")
    
    # Criterion 3 & 4: Keyword checks
    has_english_kw, lacks_spanish_kw = check_translation_keywords(initial_title or "", final_title)
    criteria_results.append(has_english_kw)
    criteria_results.append(lacks_spanish_kw)
    
    if has_english_kw:
        feedback_parts.append(f"✓ English keywords present in title")
    else:
        feedback_parts.append(f"✗ English keywords missing from title")
    
    if lacks_spanish_kw:
        feedback_parts.append(f"✓ Spanish keywords removed from title")
    else:
        feedback_parts.append(f"✗ Spanish keywords still present in title")
    
    # Criterion 5: URL unchanged
    url_correct = verify_url_unchanged(final_url or "")
    criteria_results.append(url_correct)
    logger.info(f"URL verification: {url_correct}")
    
    if url_correct:
        feedback_parts.append(f"✓ URL correct (still on Spanish Wikipedia page)")
    else:
        feedback_parts.append(f"⚠ URL verification inconclusive")
    
    # Additional analysis: character distribution
    char_analysis = analyze_character_distribution(final_title)
    if char_analysis['spanish_ratio'] < 0.02:  # Less than 2% Spanish-specific chars
        feedback_parts.append(f"✓ Character distribution supports English (Spanish chars: {char_analysis['spanish_ratio']:.1%})")
    else:
        feedback_parts.append(f"⚠ Higher Spanish character ratio than expected: {char_analysis['spanish_ratio']:.1%}")
    
    # Calculate score
    # If we have initial title, use all 5 criteria; otherwise, use 4 criteria and adjust
    if initial_title:
        total_criteria = 5
        criteria_met = sum(criteria_results)
    else:
        # Without initial title, we can't verify title change, so use 4 criteria
        total_criteria = 4
        criteria_met = sum(criteria_results)
    
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 80  # Need 80% (4/5 or 3.2/4)
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not initial_title:
        feedback += "\n\n⚠ Note: Initial title not available, using reduced criteria set"
    
    if not LANGDETECT_AVAILABLE:
        feedback += "\n\n⚠ Note: langdetect library not available, using heuristic language detection"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "initial_title": initial_title,
            "final_title": final_title,
            "final_url": final_url,
            "detected_language": detected_lang,
            "title_changed": title_changed if initial_title else None,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "char_analysis": char_analysis
        }
    }
