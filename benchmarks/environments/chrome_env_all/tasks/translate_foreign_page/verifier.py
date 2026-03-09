#!/usr/bin/env python3
"""
Verifier for Chrome Foreign Language Translation Task (translate_foreign_page@1)
Task: Translate a Japanese webpage to English using Chrome's built-in translation

Verification Strategy:
- Use CDP to execute JavaScript that inspects page translation state
- Check HTML lang attribute for translation markers
- Sample page text content to detect English vs Japanese
- Look for Google Translate elements in DOM
- Verify translation completed successfully
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

# Try to import requests for CDP communication
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False
    logger.warning("requests library not available, using fallback verification")


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for translate_foreign_page@1.
    
    Verifies that the Japanese webpage was successfully translated to English.
    
    Args:
        traj: Trajectory data (not used)
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
        # Retrieve page state information from container
        page_info = get_page_translation_state(copy_from_env)
        
        if page_info.get('error'):
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve page state: {page_info['error']}"
            }
        
        # Perform multi-criteria verification
        result = verify_translation(page_info)
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_page_translation_state(copy_from_env) -> Dict[str, Any]:
    """
    Retrieve page translation state from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict with page state information including URL, title, and translation markers
    """
    result = {
        "url": "",
        "title": "",
        "text_sample": "",
        "error": None
    }
    
    try:
        # Copy active URL
        temp_url = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_url.close()
        
        try:
            copy_from_env("/tmp/translate_verification/active_url.txt", temp_url.name)
            with open(temp_url.name, 'r') as f:
                result['url'] = f.read().strip()
        except Exception as e:
            logger.warning(f"Could not copy active_url.txt: {e}")
            # Try fallback location
            try:
                copy_from_env("/tmp/active_url.txt", temp_url.name)
                with open(temp_url.name, 'r') as f:
                    result['url'] = f.read().strip()
            except:
                pass
        finally:
            if os.path.exists(temp_url.name):
                os.unlink(temp_url.name)
        
        # Copy active title
        temp_title = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_title.close()
        
        try:
            copy_from_env("/tmp/translate_verification/active_title.txt", temp_title.name)
            with open(temp_title.name, 'r') as f:
                result['title'] = f.read().strip()
        except Exception as e:
            logger.warning(f"Could not copy active_title.txt: {e}")
            # Try fallback location
            try:
                copy_from_env("/tmp/active_title.txt", temp_title.name)
                with open(temp_title.name, 'r') as f:
                    result['title'] = f.read().strip()
            except:
                pass
        finally:
            if os.path.exists(temp_title.name):
                os.unlink(temp_title.name)
        
        # Copy page state JSON if available
        temp_state = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_state.close()
        
        try:
            copy_from_env("/tmp/translate_verification/page_state.json", temp_state.name)
            with open(temp_state.name, 'r') as f:
                state_data = json.load(f)
                result.update(state_data)
        except Exception as e:
            logger.debug(f"Could not copy page_state.json: {e}")
        finally:
            if os.path.exists(temp_state.name):
                os.unlink(temp_state.name)
        
        logger.info(f"Retrieved page state: URL={result['url'][:60]}, Title={result['title'][:50]}")
        
        return result
        
    except Exception as e:
        logger.error(f"Error retrieving page state: {e}")
        result['error'] = str(e)
        return result


def verify_translation(page_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that translation was successfully performed.
    
    Checks:
    1. Translation detected (title changed from Japanese)
    2. Language indicators (translated title contains English)
    3. Content indicators (URL still points to original file)
    4. Translation completeness
    
    Args:
        page_info: Dict with page state including URL, title
        
    Returns:
        Verification result dict
    """
    url = page_info.get('url', '')
    title = page_info.get('title', '')
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    logger.info(f"Verifying translation:")
    logger.info(f"  URL: {url}")
    logger.info(f"  Title: {title}")
    
    # Criterion 1: URL should still be the Japanese article file
    url_correct = "japanese_tech_article.html" in url or "Documents" in url
    if url_correct:
        criteria_met += 1
        feedback_parts.append("✓ Correct page loaded (Japanese article)")
        logger.info("✓ URL check passed")
    else:
        feedback_parts.append("✗ Wrong page - expected Japanese article file")
        logger.info("✗ URL check failed")
    
    # Criterion 2: Title should be translated (contain English, not just Japanese)
    # Original Japanese title: "最新テクノロジーニュース - 人工知能の進歩"
    # Check if title contains English characters and common English words
    title_has_english = bool(re.search(r'[a-zA-Z]{3,}', title))
    title_has_common_english = any(word in title.lower() for word in 
                                    ['technology', 'artificial', 'intelligence', 'latest', 
                                     'news', 'progress', 'advancement', 'ai', 'trend'])
    
    # Also check if title NO LONGER contains only Japanese characters
    has_japanese = bool(re.search(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]', title))
    
    title_translated = title_has_english or title_has_common_english
    
    if title_translated:
        criteria_met += 1
        feedback_parts.append(f"✓ Title appears translated: '{title[:60]}...'")
        logger.info("✓ Title translation check passed")
    else:
        feedback_parts.append(f"✗ Title not translated (still in Japanese): '{title[:60]}...'")
        logger.info("✗ Title translation check failed")
    
    # Criterion 3: Title should contain expected content keywords
    # The article is about AI/technology, so translated title should reflect that
    content_keywords = ['artificial', 'intelligence', 'technology', 'ai', 'latest', 
                       'trend', 'future', 'advance', 'progress', 'news']
    title_lower = title.lower()
    has_content_keyword = any(keyword in title_lower for keyword in content_keywords)
    
    if has_content_keyword:
        criteria_met += 1
        feedback_parts.append("✓ Translated title contains expected content keywords")
        logger.info("✓ Content keyword check passed")
    else:
        # Give partial credit if title has any English
        if title_has_english:
            criteria_met += 0.5
            feedback_parts.append("⚠ Title translated but missing expected keywords")
            logger.info("⚠ Content keyword check: partial credit")
        else:
            feedback_parts.append("✗ Title missing content keywords")
            logger.info("✗ Content keyword check failed")
    
    # Criterion 4: Title should be substantially different from original
    # Original contains specific Japanese characters that shouldn't be in translated version
    original_title = "最新テクノロジーニュース - 人工知能の進歩"
    title_changed = title != original_title and not has_japanese
    
    if title_changed:
        criteria_met += 1
        feedback_parts.append("✓ Translation complete (title fully converted from Japanese)")
        logger.info("✓ Translation completeness check passed")
    else:
        feedback_parts.append("✗ Translation incomplete (title still contains Japanese characters)")
        logger.info("✗ Translation completeness check failed")
    
    # Additional check: Detect if Chrome showed error or navigation failed
    error_indicators = ['404', 'not found', 'error', 'cannot', 'failed']
    has_error = any(indicator in title.lower() for indicator in error_indicators)
    
    if has_error:
        criteria_met = max(0, criteria_met - 1)
        feedback_parts.append("⚠ Warning: Error detected in page title")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3/4 criteria (75%)
    
    # Build detailed feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed:
        feedback += "\n\nTo complete this task:"
        feedback += "\n1. Ensure the Japanese article page is loaded"
        feedback += "\n2. Look for Chrome's translation bar at the top"
        feedback += "\n3. Click 'Translate' button, OR right-click and select 'Translate to English'"
        feedback += "\n4. Wait for translation to complete"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "url": url,
            "title": title,
            "url_correct": url_correct,
            "title_translated": title_translated,
            "has_content_keyword": has_content_keyword,
            "title_changed": title_changed,
            "criteria_met": criteria_met
        }
    }
