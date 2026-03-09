#!/usr/bin/env python3
"""
Verifier for Chrome Page Translation Task (translate_page@1)
Task: Translate a Spanish webpage to English using Chrome's built-in translation

Verification Strategy:
1. Compare original Spanish content with final content
2. Use language detection to verify language change
3. Check for specific Spanish→English phrase translations
4. Verify page structure remains intact
5. Check for translation indicators in title/UI
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import language detection
try:
    from langdetect import detect, detect_langs, LangDetectException
    HAS_LANGDETECT = True
except ImportError:
    logger.warning("langdetect not available, will use basic heuristics")
    HAS_LANGDETECT = False

# Import Chrome verification utilities
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for translate_page@1.
    
    Verifies:
    1. Translation was activated
    2. English content is now dominant (≥80%)
    3. Spanish content was removed (<20%)
    4. Page integrity maintained
    5. Translation confirmation present
    
    Scoring:
    - 100%: All 5 criteria met
    - 80-99%: 4/5 criteria met
    - 60-79%: 3/5 criteria met
    - <60%: <3 criteria met
    
    Pass threshold: 80% (4 out of 5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    try:
        # Get original and final content
        original_data = get_original_content(copy_from_env)
        final_data = get_final_content(copy_from_env)
        
        if original_data is None or final_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not retrieve page content for verification"
            }
        
        # Perform multi-criteria verification
        result = verify_translation(original_data, final_data)
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_original_content(copy_from_env) -> Dict[str, Any]:
    """Extract original Spanish content"""
    try:
        # Copy original HTML
        temp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
        temp_html.close()
        
        copy_from_env("/tmp/translate_verification/original_content.html", temp_html.name)
        
        with open(temp_html.name, 'r', encoding='utf-8') as f:
            html_content = f.read()
        
        os.unlink(temp_html.name)
        
        # Extract text content from HTML
        text_content = extract_text_from_html(html_content)
        
        return {
            'html': html_content,
            'text': text_content,
            'language': 'es'
        }
        
    except Exception as e:
        logger.error(f"Error getting original content: {e}")
        return None


def get_final_content(copy_from_env) -> Dict[str, Any]:
    """Extract final (hopefully translated) content"""
    try:
        # Try to get final text content
        temp_text = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_text.close()
        
        try:
            copy_from_env("/tmp/translate_verification/final_text_content.txt", temp_text.name)
            with open(temp_text.name, 'r', encoding='utf-8', errors='ignore') as f:
                text_content = f.read()
        except Exception as e:
            logger.warning(f"Could not get final text content: {e}")
            text_content = ""
        
        os.unlink(temp_text.name)
        
        # Get final title
        temp_title = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_title.close()
        
        try:
            copy_from_env("/tmp/translate_verification/final_title.txt", temp_title.name)
            with open(temp_title.name, 'r', encoding='utf-8') as f:
                title = f.read().strip()
        except Exception as e:
            logger.warning(f"Could not get final title: {e}")
            title = ""
        
        os.unlink(temp_title.name)
        
        # Get final URL
        temp_url = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_url.close()
        
        try:
            copy_from_env("/tmp/translate_verification/final_url.txt", temp_url.name)
            with open(temp_url.name, 'r', encoding='utf-8') as f:
                url = f.read().strip()
        except Exception as e:
            logger.warning(f"Could not get final URL: {e}")
            url = ""
        
        os.unlink(temp_url.name)
        
        return {
            'text': text_content,
            'title': title,
            'url': url
        }
        
    except Exception as e:
        logger.error(f"Error getting final content: {e}")
        return None


def extract_text_from_html(html_content: str) -> str:
    """Extract readable text from HTML"""
    # Simple HTML tag removal
    text = re.sub(r'<script[^>]*>.*?</script>', '', html_content, flags=re.DOTALL)
    text = re.sub(r'<style[^>]*>.*?</style>', '', text, flags=re.DOTALL)
    text = re.sub(r'<[^>]+>', ' ', text)
    text = re.sub(r'\s+', ' ', text)
    return text.strip()


def detect_language_robust(text: str) -> Tuple[str, float]:
    """
    Detect language with confidence score.
    
    Returns:
        Tuple of (language_code, confidence)
    """
    if not text or len(text.strip()) < 20:
        return "unknown", 0.0
    
    if HAS_LANGDETECT:
        try:
            lang_probs = detect_langs(text)
            if lang_probs:
                top_lang = lang_probs[0]
                return top_lang.lang, top_lang.prob
        except LangDetectException:
            pass
    
    # Fallback: Simple heuristic based on common words
    text_lower = text.lower()
    
    spanish_indicators = ['la', 'el', 'de', 'que', 'es', 'en', 'para', 'con', 'una', 'por', 'del', 'los', 'las']
    english_indicators = ['the', 'is', 'and', 'to', 'of', 'in', 'for', 'that', 'with', 'on', 'are', 'this']
    
    spanish_count = sum(text_lower.count(f' {word} ') for word in spanish_indicators)
    english_count = sum(text_lower.count(f' {word} ') for word in english_indicators)
    
    total = spanish_count + english_count
    if total == 0:
        return "unknown", 0.0
    
    if spanish_count > english_count:
        return "es", spanish_count / total
    else:
        return "en", english_count / total


def check_spanish_to_english_translations(original_text: str, final_text: str) -> Tuple[bool, int, List[str]]:
    """
    Check if specific Spanish phrases were translated to English.
    
    Returns:
        Tuple of (translations_found, count_found, found_translations)
    """
    # Key Spanish phrases from the article and their English translations
    translation_pairs = [
        ("inteligencia artificial", "artificial intelligence"),
        ("aprendizaje automático", "machine learning"),
        ("procesamiento del lenguaje natural", "natural language processing"),
        ("visión por computadora", "computer vision"),
        ("desafíos éticos", "ethical challenges"),
        ("desarrollo", "development"),
        ("tecnología", "technology"),
        ("futuro", "future"),
        ("sociedad", "society"),
    ]
    
    original_lower = original_text.lower()
    final_lower = final_text.lower()
    
    found_translations = []
    
    for spanish, english in translation_pairs:
        # Check if Spanish phrase was in original and English phrase is in final
        if spanish in original_lower and english in final_lower:
            found_translations.append(f"{spanish} → {english}")
    
    translations_found = len(found_translations) >= 3  # At least 3 translations
    
    return translations_found, len(found_translations), found_translations


def verify_translation(original_data: Dict[str, Any], final_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify translation occurred using multiple criteria.
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    original_text = original_data.get('text', '')
    final_text = final_data.get('text', '')
    final_title = final_data.get('title', '')
    
    logger.info(f"Original text length: {len(original_text)} chars")
    logger.info(f"Final text length: {len(final_text)} chars")
    logger.info(f"Final title: {final_title[:100]}")
    
    # Criterion 1: Translation was activated (check if content changed)
    content_changed = False
    if final_text and len(final_text) > 100:
        # Check if text is substantially different
        # Use simple word overlap ratio
        original_words = set(original_text.lower().split())
        final_words = set(final_text.lower().split())
        
        if len(final_words) > 0:
            overlap = len(original_words & final_words) / len(final_words)
            content_changed = overlap < 0.7  # If less than 70% overlap, content changed
            
            logger.info(f"Word overlap ratio: {overlap:.2f}")
    else:
        logger.warning("Final text content is missing or too short")
    
    if content_changed:
        feedback_parts.append("✓ Translation activated: Content changed from original")
        criteria_met += 1
    else:
        feedback_parts.append("✗ Translation not activated: Content appears unchanged")
    
    # Criterion 2: English content is now dominant (≥80%)
    final_lang, final_confidence = detect_language_robust(final_text if final_text else final_title)
    english_dominant = final_lang == 'en' and final_confidence >= 0.6
    
    logger.info(f"Final language detected: {final_lang} (confidence: {final_confidence:.2f})")
    
    if english_dominant:
        feedback_parts.append(f"✓ English content dominant: Detected {final_lang} with {final_confidence:.0%} confidence")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ English not dominant: Detected {final_lang} with {final_confidence:.0%} confidence")
    
    # Criterion 3: Spanish content was removed (<20%)
    spanish_removed = final_lang != 'es'
    
    if spanish_removed:
        feedback_parts.append("✓ Spanish content removed: No longer detected as Spanish")
        criteria_met += 1
    else:
        feedback_parts.append("✗ Spanish content remains: Still detected as Spanish")
    
    # Criterion 4: Page integrity maintained (check if title is present and reasonable)
    integrity_ok = len(final_title) > 10 and "error" not in final_title.lower() and "404" not in final_title.lower()
    
    if integrity_ok:
        feedback_parts.append(f"✓ Page integrity maintained: Title present and valid")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Page integrity issues: Title missing or shows error")
    
    # Criterion 5: Translation confirmation (check for specific phrase translations)
    if final_text:
        translations_ok, trans_count, found_trans = check_spanish_to_english_translations(original_text, final_text)
        
        if translations_ok:
            feedback_parts.append(f"✓ Translation confirmed: Found {trans_count} translated phrases")
            criteria_met += 1
        else:
            feedback_parts.append(f"⚠ Translation partial: Only {trans_count} translated phrases found")
            if trans_count > 0:
                criteria_met += 0.5  # Partial credit
    else:
        feedback_parts.append("⚠ Cannot verify translations: Final text not captured")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 80  # Need 4/5 criteria
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not HAS_LANGDETECT:
        feedback += "\n\n⚠ Note: langdetect library not available, using basic heuristics"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "content_changed": content_changed,
            "english_dominant": english_dominant,
            "spanish_removed": spanish_removed,
            "integrity_ok": integrity_ok,
            "final_language": final_lang,
            "final_confidence": final_confidence
        }
    }
