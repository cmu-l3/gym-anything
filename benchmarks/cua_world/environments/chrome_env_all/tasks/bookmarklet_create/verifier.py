#!/usr/bin/env python3
"""
Verifier for Chrome JavaScript Bookmarklet Creation Task (bookmarklet_create@1)

Task: Create a JavaScript bookmarklet named 'Page Highlighter' that highlights 
      all paragraphs on a webpage with yellow background color.

Verification Strategy:
1. Copy Bookmarks file from container
2. Parse JSON to find bookmark bar items
3. Verify bookmarklet exists with appropriate name
4. Verify URL starts with javascript: protocol
5. Verify JavaScript code contains required components:
   - Element selector (querySelectorAll, getElementsByTagName, etc.)
   - Style manipulation (style.backgroundColor or similar)
   - Yellow color reference (yellow, #ffff00, rgb(255,255,0), etc.)
6. Verify bookmarklet is in bookmark bar (not other folders)

Scoring:
- 100%: All 5 criteria met (name, javascript:, selector, style, color)
- 80%: 4/5 criteria met
- 60%: 3/5 criteria met
- 40%: 2/5 criteria met
- 0-20%: 0-1 criteria met

Pass threshold: 75% (requires at least 4 out of 5 criteria)
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

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import (
        parse_bookmarks,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def parse_bookmarks(path):
        """Fallback bookmark parser"""
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        """Fallback cleanup"""
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for bookmarklet_create@1 task.
    
    Verifies that a JavaScript bookmarklet was created with correct name,
    javascript: protocol, and required code components.
    
    Args:
        traj: Trajectory data (not used for this verification)
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
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get bookmarks data from container
        bookmarks_data, error_msg = get_bookmarks_data(copy_from_env)
        
        if bookmarks_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve bookmarks: {error_msg}"
            }
        
        # Verify bookmarklet creation
        verification_result = verify_bookmarklet(bookmarks_data)
        
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


def get_bookmarks_data(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Retrieve and parse bookmarks data from container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (bookmarks_data dict or None, error_message)
    """
    temp_file = None
    try:
        # Create temporary file for bookmarks
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        bookmarks_paths = [
            "/tmp/bookmarks_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks"
        ]
        
        bookmarks_data = None
        source_path = None
        
        for container_path in bookmarks_paths:
            try:
                logger.info(f"Trying to copy bookmarks from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully loaded bookmarks from: {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to load from {container_path}: {e}")
                continue
        
        if bookmarks_data is None:
            return None, "Could not access bookmarks file from any known location"
        
        return bookmarks_data, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Bookmarks JSON: {e}"
    except Exception as e:
        return None, f"Error retrieving bookmarks: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def verify_bookmarklet(bookmarks_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify bookmarklet creation in bookmark bar.
    
    Checks:
    1. Bookmarklet exists in bookmark bar
    2. Name contains "highlighter" or "highlight"
    3. URL starts with javascript: protocol
    4. Code contains element selector
    5. Code contains style manipulation with yellow color
    
    Args:
        bookmarks_data: Parsed bookmarks JSON data
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    if not bookmarks_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Bookmarks data is empty or invalid"
        }
    
    # Navigate to bookmark bar
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    logger.info(f"Found {len(children)} item(s) in bookmark bar")
    
    # Initialize criteria tracking
    criteria = {
        "bookmarklet_found": False,
        "has_javascript_protocol": False,
        "has_selector": False,
        "has_style_manipulation": False,
        "has_yellow_color": False
    }
    
    feedback_parts = []
    bookmarklet_name = None
    bookmarklet_url = None
    
    # Search for bookmarklet in bookmark bar
    for child in children:
        if child.get('type') != 'url':
            continue
        
        name = child.get('name', '').lower()
        url = child.get('url', '')
        
        # Check if this looks like our bookmarklet (by name)
        if any(keyword in name for keyword in ['highlight', 'page', 'paragraph', 'yellow']):
            bookmarklet_name = child.get('name', '')
            bookmarklet_url = url
            criteria["bookmarklet_found"] = True
            
            logger.info(f"Found potential bookmarklet: '{bookmarklet_name}'")
            logger.info(f"URL: {url[:100]}...")
            
            # Analyze the bookmarklet
            analysis = analyze_bookmarklet_code(bookmarklet_name, url)
            criteria.update(analysis['criteria'])
            feedback_parts.extend(analysis['feedback'])
            
            break
    
    if not criteria["bookmarklet_found"]:
        # Check if there's ANY javascript: bookmark
        for child in children:
            if child.get('type') == 'url':
                url = child.get('url', '')
                if url.startswith('javascript:'):
                    bookmarklet_name = child.get('name', '')
                    bookmarklet_url = url
                    criteria["bookmarklet_found"] = True
                    
                    logger.info(f"Found javascript bookmark with different name: '{bookmarklet_name}'")
                    
                    # Analyze it anyway
                    analysis = analyze_bookmarklet_code(bookmarklet_name, url)
                    criteria.update(analysis['criteria'])
                    feedback_parts.extend(analysis['feedback'])
                    feedback_parts.insert(0, f"⚠ Bookmarklet found but name is '{bookmarklet_name}' instead of 'Page Highlighter'")
                    
                    break
    
    if not criteria["bookmarklet_found"]:
        feedback_parts.append("✗ No bookmarklet found in bookmark bar")
        feedback_parts.append("  Expected: Bookmark with name containing 'highlight' or 'page'")
        feedback_parts.append("  Location: Bookmark bar (not in folders)")
    
    # Calculate score
    criteria_met = sum(criteria.values())
    score = (criteria_met / 5) * 100
    passed = score >= 75  # Need at least 4/5 criteria (80%)
    
    # Generate summary feedback
    summary = []
    summary.append(f"Verification Results: {criteria_met}/5 criteria met")
    summary.append("")
    summary.extend(feedback_parts)
    summary.append("")
    summary.append(f"Final Score: {int(score)}%")
    summary.append(f"Status: {'✅ PASSED' if passed else '❌ FAILED'}")
    
    if passed:
        summary.append("")
        summary.append("Bookmarklet created successfully!")
    elif criteria_met == 0:
        summary.append("")
        summary.append("No valid bookmarklet found. Please create a bookmark with javascript: URL.")
    else:
        summary.append("")
        summary.append("Bookmarklet partially created but missing required components.")
    
    feedback = "\n".join(summary)
    
    logger.info(f"Verification complete: passed={passed}, score={int(score)}")
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": {
            "criteria": criteria,
            "criteria_met": criteria_met,
            "bookmarklet_name": bookmarklet_name,
            "bookmarklet_found": criteria["bookmarklet_found"]
        }
    }


def analyze_bookmarklet_code(name: str, url: str) -> Dict[str, Any]:
    """
    Analyze bookmarklet code for required components.
    
    Args:
        name: Bookmarklet name
        url: Bookmarklet URL (should start with javascript:)
        
    Returns:
        Dict with criteria results and feedback messages
    """
    criteria = {
        "has_javascript_protocol": False,
        "has_selector": False,
        "has_style_manipulation": False,
        "has_yellow_color": False
    }
    
    feedback = []
    feedback.append(f"✓ Bookmarklet found: '{name}'")
    
    # Check javascript: protocol
    if url.startswith('javascript:'):
        criteria["has_javascript_protocol"] = True
        feedback.append("✓ Uses javascript: protocol")
    else:
        feedback.append("✗ Missing javascript: protocol (URL should start with 'javascript:')")
        return {"criteria": criteria, "feedback": feedback}
    
    # Extract and analyze JavaScript code
    js_code = url[11:]  # Remove 'javascript:' prefix
    js_code_lower = js_code.lower()
    
    logger.info(f"Analyzing JavaScript code: {js_code[:200]}...")
    
    # Check for element selector
    selector_patterns = [
        r'queryselectorall',
        r'getelementsbytagname',
        r'queryselector',
        r'getelementsby',
        r'document\..*\[',  # Array-style access
    ]
    
    for pattern in selector_patterns:
        if re.search(pattern, js_code_lower):
            criteria["has_selector"] = True
            feedback.append(f"✓ Contains element selector (detected: {pattern})")
            break
    
    if not criteria["has_selector"]:
        feedback.append("✗ Missing element selector (need querySelectorAll, getElementsByTagName, etc.)")
    
    # Check for style manipulation
    style_patterns = [
        r'\.style\.',
        r'style\.background',
        r'backgroundcolor',
        r'setattribute.*style',
    ]
    
    for pattern in style_patterns:
        if re.search(pattern, js_code_lower):
            criteria["has_style_manipulation"] = True
            feedback.append(f"✓ Contains style manipulation")
            break
    
    if not criteria["has_style_manipulation"]:
        feedback.append("✗ Missing style manipulation (need .style.backgroundColor or similar)")
    
    # Check for yellow color
    yellow_patterns = [
        r'yellow',
        r'#ffff00',
        r'#ff0',
        r'rgb\s*\(\s*255\s*,\s*255\s*,\s*0\s*\)',
        r'rgba\s*\(\s*255\s*,\s*255\s*,\s*0',
        r'hsl\s*\(\s*60',  # Yellow is at 60 degrees
    ]
    
    for pattern in yellow_patterns:
        if re.search(pattern, js_code_lower):
            criteria["has_yellow_color"] = True
            feedback.append(f"✓ Contains yellow color reference")
            break
    
    if not criteria["has_yellow_color"]:
        feedback.append("✗ Missing yellow color (need 'yellow', '#ffff00', or rgb(255,255,0))")
    
    return {"criteria": criteria, "feedback": feedback}
