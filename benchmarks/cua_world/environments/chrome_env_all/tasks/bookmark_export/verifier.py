#!/usr/bin/env python3
"""
Verifier for Chrome Bookmark Export Task (bookmark_export@1)
Task: Export Chrome bookmarks to an HTML file for backup

Verification Strategy:
- Check that HTML file exists in Downloads directory
- Validate Netscape bookmark format (DOCTYPE, structure)
- Parse HTML to extract bookmark entries
- Verify expected bookmarks from setup are present
- Check folder structure is preserved
"""

import logging
import sys
import os
import re
import tempfile
from pathlib import Path
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import HTML parsing libraries
try:
    from bs4 import BeautifulSoup
    HAS_BS4 = True
except ImportError:
    HAS_BS4 = False
    logger.warning("BeautifulSoup4 not available, using regex-based parsing")


def verify_task(traj, env_info, task_info):
    """
    Main verification function for bookmark_export@1 task.
    
    Verifies:
    1. HTML file exists in Downloads
    2. Valid Netscape bookmark format
    3. Contains bookmark entries (minimum 1)
    4. Expected bookmarks from setup are present
    
    Scoring:
    - 100%: All 4 criteria met (perfect export)
    - 75-99%: 3/4 criteria met (successful export with minor issues)
    - 50-74%: 2/4 criteria met (file created but significant problems)
    - 0-49%: <2 criteria met (export failed)
    
    Pass threshold: 75% (requires at least 3 out of 4 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: HTML file exists
    logger.info("Checking if bookmark HTML file exists...")
    success, html_path, html_name, error = find_bookmark_html(copy_from_env)
    
    if not success:
        feedback = f"✗ Bookmark HTML file not found\n{error}"
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback
        }
    
    feedback_parts.append(f"✓ Exported file found: {html_name}")
    criteria_met += 1
    
    # Read HTML content
    try:
        with open(html_path, 'r', encoding='utf-8', errors='ignore') as f:
            html_content = f.read()
    except Exception as e:
        return {
            "passed": False,
            "score": 25,
            "feedback": f"✗ Could not read HTML file: {e}"
        }
    
    # Criterion 2: Valid Netscape bookmark format
    logger.info("Validating Netscape bookmark format...")
    format_ok, format_feedback = validate_bookmark_format(html_content)
    if format_ok:
        feedback_parts.append(f"✓ {format_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {format_feedback}")
    
    # Criterion 3: Contains bookmark entries
    logger.info("Checking for bookmark entries...")
    bookmarks = extract_bookmarks(html_content)
    bookmark_count = len(bookmarks)
    
    if bookmark_count >= 1:
        feedback_parts.append(f"✓ Found {bookmark_count} bookmark(s) in export")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ No bookmarks found in exported file")
    
    # Criterion 4: Expected bookmarks present
    logger.info("Verifying expected bookmarks...")
    expected_urls = [
        "https://www.google.com",
        "https://github.com",
        "https://portal.company.com",
        "https://mail.company.com",
        "https://docs.example.com"
    ]
    
    found_urls = [bookmark['url'] for bookmark in bookmarks]
    expected_found = 0
    for url in expected_urls:
        if any(normalize_url(url) == normalize_url(found) for found in found_urls):
            expected_found += 1
    
    if expected_found >= 3:  # At least 3 out of 5 expected bookmarks
        feedback_parts.append(f"✓ Expected bookmarks present ({expected_found}/{len(expected_urls)} found)")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Missing expected bookmarks (only {expected_found}/{len(expected_urls)} found)")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not HAS_BS4:
        feedback += "\n\n⚠ Note: BeautifulSoup4 not available, using basic parsing"
    
    # Clean up temporary file
    try:
        if html_path and os.path.exists(html_path):
            os.unlink(html_path)
    except:
        pass
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "file_found": success,
            "format_valid": format_ok,
            "bookmark_count": bookmark_count,
            "expected_found": expected_found,
            "expected_total": len(expected_urls)
        }
    }


def find_bookmark_html(copy_from_env):
    """
    Find and copy the exported bookmark HTML file.
    
    Returns:
        tuple: (success, local_path, filename, error_message)
    """
    try:
        # First, try to get the filename that was found
        temp_filename = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/bookmark_filename.txt", temp_filename.name)
            with open(temp_filename.name, 'r') as f:
                found_name = f.read().strip()
            os.unlink(temp_filename.name)
            
            if found_name == "none":
                return False, "", "", "No HTML file was found in Downloads folder"
        except Exception as e:
            logger.warning(f"Could not read bookmark_filename.txt: {e}")
            found_name = "bookmarks.html"  # fallback
        
        # Try to copy the HTML file
        temp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/exported_bookmarks.html",
            f"/home/ga/Downloads/{found_name}",
            "/home/ga/Downloads/bookmarks.html",
            "/home/ga/Downloads/chrome_bookmarks.html",
        ]
        
        # Also try common Chrome bookmark export filenames with dates
        import time
        today = datetime.now().strftime("%m_%d_%y")
        yesterday = (datetime.now() - timedelta(days=1)).strftime("%m_%d_%y")
        possible_paths.extend([
            f"/home/ga/Downloads/bookmarks_{today}.html",
            f"/home/ga/Downloads/bookmarks_{yesterday}.html",
        ])
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_html.name)
                
                # Check if file has content
                if Path(temp_html.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied HTML from: {container_path}")
                    return True, temp_html.name, found_name, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_html.name)
        return False, "", "", "HTML file could not be copied from container"
        
    except Exception as e:
        logger.error(f"Error finding HTML: {e}", exc_info=True)
        return False, "", "", f"Error finding HTML: {str(e)}"


def validate_bookmark_format(html_content):
    """
    Validate that HTML follows Netscape bookmark format.
    
    Returns:
        tuple: (is_valid, feedback_message)
    """
    # Check for DOCTYPE
    doctype_patterns = [
        r'<!DOCTYPE\s+NETSCAPE-Bookmark-file-1>',
        r'<!DOCTYPE\s+NETSCAPE-Bookmark-file-1\s*>',
    ]
    
    has_doctype = any(re.search(pattern, html_content, re.IGNORECASE) for pattern in doctype_patterns)
    
    if not has_doctype:
        return False, "Missing NETSCAPE-Bookmark-file-1 DOCTYPE declaration"
    
    # Check for essential HTML structure
    has_html_tag = bool(re.search(r'<html', html_content, re.IGNORECASE))
    has_dl_tag = bool(re.search(r'<DL', html_content, re.IGNORECASE))
    
    if not has_html_tag:
        return False, "Missing HTML structure"
    
    if not has_dl_tag:
        return False, "Missing bookmark list structure (<DL> tags)"
    
    return True, "Valid Netscape bookmark format"


def extract_bookmarks(html_content):
    """
    Extract bookmark entries from HTML.
    
    Returns:
        list: List of dicts with 'url', 'title', and optionally 'folder'
    """
    bookmarks = []
    
    if HAS_BS4:
        # Use BeautifulSoup for robust parsing
        try:
            soup = BeautifulSoup(html_content, 'lxml')
            for a_tag in soup.find_all('a'):
                href = a_tag.get('href', '')
                title = a_tag.get_text(strip=True)
                if href:
                    bookmarks.append({
                        'url': href,
                        'title': title
                    })
        except Exception as e:
            logger.warning(f"BeautifulSoup parsing failed: {e}, falling back to regex")
    
    if not bookmarks:
        # Fallback: regex-based parsing
        # Pattern for bookmark entries: <DT><A HREF="url">title</A>
        pattern = r'<DT><A\s+HREF="([^"]+)"[^>]*>([^<]+)</A>'
        matches = re.findall(pattern, html_content, re.IGNORECASE)
        
        for url, title in matches:
            bookmarks.append({
                'url': url,
                'title': title
            })
    
    logger.info(f"Extracted {len(bookmarks)} bookmark(s)")
    return bookmarks


def normalize_url(url):
    """Normalize URL for comparison"""
    if not url:
        return ""
    # Remove trailing slashes
    url = url.rstrip('/')
    # Convert to lowercase
    url = url.lower()
    # Handle http vs https
    url = url.replace('http://', '').replace('https://', '')
    return url
