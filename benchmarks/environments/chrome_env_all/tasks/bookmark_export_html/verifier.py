#!/usr/bin/env python3
"""
Verifier for Chrome Bookmark Export Task (bookmark_export_html@1)
Task: Export Chrome bookmarks to HTML file for backup

Verification Strategy:
- Check if HTML export file exists in Downloads folder
- Validate HTML follows Netscape bookmark format
- Parse exported HTML to extract URLs and folder structure
- Compare with source Chrome bookmarks JSON
- Score based on completeness, accuracy, and format compliance
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional
from html.parser import HTMLParser

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
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
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    def cleanup_verification_temp():
        pass


class NetscapeBookmarkParser(HTMLParser):
    """
    Parser for Netscape bookmark HTML format.
    Extracts URLs, folder names, and bookmark structure.
    """
    
    def __init__(self):
        super().__init__()
        self.urls = []
        self.folders = []
        self.bookmark_names = {}  # url -> name mapping
        self.current_folder = None
        self.in_h3 = False
        self.in_a = False
        self.current_href = None
        
    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        
        if tag.lower() == 'a':
            href = attrs_dict.get('href', '')
            if href:
                self.current_href = href
                self.urls.append(href)
                self.in_a = True
        
        elif tag.lower() == 'h3':
            # Folder heading
            self.in_h3 = True
    
    def handle_data(self, data):
        data_stripped = data.strip()
        if not data_stripped:
            return
            
        if self.in_h3:
            # This is a folder name
            if data_stripped not in ['Bookmarks bar', 'Other bookmarks', 'Mobile bookmarks']:
                self.folders.append(data_stripped)
        
        elif self.in_a and self.current_href:
            # This is a bookmark name
            self.bookmark_names[self.current_href] = data_stripped
    
    def handle_endtag(self, tag):
        if tag.lower() == 'h3':
            self.in_h3 = False
        elif tag.lower() == 'a':
            self.in_a = False
            self.current_href = None


def extract_urls_from_chrome_bookmarks(bookmarks_json: Dict) -> Set[str]:
    """
    Recursively extract all URLs from Chrome bookmarks JSON.
    
    Args:
        bookmarks_json: Parsed Chrome bookmarks JSON
        
    Returns:
        Set of URLs found in bookmarks
    """
    urls = set()
    
    def traverse(node):
        if isinstance(node, dict):
            if node.get('type') == 'url':
                url = node.get('url', '')
                if url:
                    urls.add(normalize_url(url))
            elif node.get('type') == 'folder':
                children = node.get('children', [])
                for child in children:
                    traverse(child)
            else:
                # Traverse all values
                for value in node.values():
                    traverse(value)
        elif isinstance(node, list):
            for item in node:
                traverse(item)
    
    traverse(bookmarks_json)
    return urls


def extract_folders_from_chrome_bookmarks(bookmarks_json: Dict) -> Set[str]:
    """
    Recursively extract all folder names from Chrome bookmarks JSON.
    
    Args:
        bookmarks_json: Parsed Chrome bookmarks JSON
        
    Returns:
        Set of folder names (excluding root folders)
    """
    folders = set()
    
    def traverse(node):
        if isinstance(node, dict):
            if node.get('type') == 'folder':
                name = node.get('name', '')
                # Exclude root/system folders
                if name and name not in ['Bookmarks bar', 'Other bookmarks', 'Mobile bookmarks', 'Synced bookmarks']:
                    folders.add(name)
                children = node.get('children', [])
                for child in children:
                    traverse(child)
            else:
                for value in node.values():
                    traverse(value)
        elif isinstance(node, list):
            for item in node:
                traverse(item)
    
    traverse(bookmarks_json)
    return folders


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison by removing trailing slashes and lowercasing.
    
    Args:
        url: URL string
        
    Returns:
        Normalized URL
    """
    if not url:
        return ""
    # Remove trailing slashes
    url = url.rstrip('/')
    # Convert to lowercase
    url = url.lower()
    return url


def verify_html_format(html_content: str) -> Tuple[bool, str]:
    """
    Verify HTML follows Netscape bookmark format.
    
    Args:
        html_content: HTML file content
        
    Returns:
        Tuple of (is_valid, feedback_message)
    """
    # Check for DOCTYPE
    if 'DOCTYPE NETSCAPE-Bookmark-file' not in html_content and 'DOCTYPE NETSCAPE' not in html_content:
        return False, "Missing Netscape bookmark DOCTYPE declaration"
    
    # Check for essential HTML structure elements
    required_elements = [
        '<DL>',  # Definition list
        '<DT>',  # Definition term (for bookmarks/folders)
    ]
    
    required_found = 0
    for element in required_elements:
        if element in html_content or element.lower() in html_content.lower():
            required_found += 1
    
    if required_found < len(required_elements):
        return False, f"Missing required HTML elements for bookmark format (found {required_found}/{len(required_elements)})"
    
    return True, "Valid Netscape bookmark format"


def verify_task(traj, env_info, task_info) -> Dict:
    """
    Main verification function for bookmark export task.
    
    Verifies:
    1. Export file exists in Downloads folder
    2. File has valid Netscape bookmark HTML format
    3. Complete bookmark set (≥95% URLs matched)
    4. Folder hierarchy preserved (≥90% folders matched)
    5. URL accuracy (no missing expected URLs)
    6. Reasonable file size (not empty or suspiciously small)
    
    Scoring:
    - 100%: All 6 criteria met
    - 85-99%: 5/6 criteria met (pass threshold)
    - 70-84%: 4/6 criteria met
    - 50-69%: 3/6 criteria met
    - <50%: <3 criteria met
    
    Pass threshold: 85% (requires 5 out of 6 criteria)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, feedback, and details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }
    
    results = {
        "passed": False,
        "score": 0,
        "feedback": "",
        "details": {}
    }
    
    try:
        # Get the exported HTML file
        export_html, export_filename, error = get_exported_html(copy_from_env)
        
        if not export_html:
            results["feedback"] = f"Export file not found: {error}"
            return results
        
        results["details"]["file_exists"] = True
        results["details"]["filename"] = export_filename
        logger.info(f"✓ Found export file: {export_filename}")
        
        # Check file size
        file_size = len(export_html)
        if file_size < 100:
            results["feedback"] = f"Export file too small ({file_size} bytes) - likely empty or incomplete"
            return results
        
        results["details"]["file_size_bytes"] = file_size
        results["details"]["file_size_ok"] = True
        logger.info(f"✓ File size OK: {file_size} bytes")
        
        # Verify HTML format
        format_valid, format_msg = verify_html_format(export_html)
        results["details"]["valid_format"] = format_valid
        
        if not format_valid:
            results["feedback"] = f"Invalid HTML format: {format_msg}"
            return results
        
        logger.info(f"✓ {format_msg}")
        
        # Parse exported HTML
        parser = NetscapeBookmarkParser()
        try:
            parser.feed(export_html)
        except Exception as e:
            results["feedback"] = f"Failed to parse HTML: {e}"
            return results
        
        exported_urls = set(normalize_url(url) for url in parser.urls)
        exported_folders = set(parser.folders)
        
        results["details"]["exported_url_count"] = len(exported_urls)
        results["details"]["exported_folder_count"] = len(exported_folders)
        logger.info(f"✓ Parsed export: {len(exported_urls)} URLs, {len(exported_folders)} folders")
        
        # Get source bookmarks from Chrome
        source_bookmarks = get_source_bookmarks(copy_from_env)
        if not source_bookmarks:
            results["feedback"] = "Failed to access source Chrome bookmarks for comparison"
            return results
        
        source_urls = extract_urls_from_chrome_bookmarks(source_bookmarks)
        source_folders = extract_folders_from_chrome_bookmarks(source_bookmarks)
        
        results["details"]["source_url_count"] = len(source_urls)
        results["details"]["source_folder_count"] = len(source_folders)
        logger.info(f"✓ Source bookmarks: {len(source_urls)} URLs, {len(source_folders)} folders")
        
        # Compare URLs
        matched_urls = exported_urls & source_urls
        missing_urls = source_urls - exported_urls
        extra_urls = exported_urls - source_urls
        
        url_match_ratio = len(matched_urls) / len(source_urls) if source_urls else 0
        results["details"]["url_match_ratio"] = url_match_ratio
        results["details"]["matched_url_count"] = len(matched_urls)
        results["details"]["missing_url_count"] = len(missing_urls)
        
        logger.info(f"✓ URL matching: {len(matched_urls)}/{len(source_urls)} matched ({url_match_ratio*100:.1f}%)")
        
        if missing_urls:
            logger.warning(f"  Missing URLs: {list(missing_urls)[:3]}")
            results["details"]["missing_urls_sample"] = list(missing_urls)[:5]
        
        # Compare folders
        matched_folders = exported_folders & source_folders
        missing_folders = source_folders - exported_folders
        
        folder_match_ratio = len(matched_folders) / len(source_folders) if source_folders else 1.0
        results["details"]["folder_match_ratio"] = folder_match_ratio
        results["details"]["matched_folder_count"] = len(matched_folders)
        results["details"]["missing_folder_count"] = len(missing_folders)
        
        logger.info(f"✓ Folder matching: {len(matched_folders)}/{len(source_folders)} matched ({folder_match_ratio*100:.1f}%)")
        
        if missing_folders:
            logger.warning(f"  Missing folders: {list(missing_folders)}")
            results["details"]["missing_folders"] = list(missing_folders)
        
        # Scoring criteria (6 total, need 5+ to pass)
        criteria_met = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: File exists
        if results["details"].get("file_exists"):
            criteria_met += 1
            feedback_parts.append(f"✓ Export file exists: {export_filename}")
        else:
            feedback_parts.append("✗ Export file not found")
        
        # Criterion 2: Valid format
        if results["details"].get("valid_format"):
            criteria_met += 1
            feedback_parts.append("✓ Valid Netscape bookmark format")
        else:
            feedback_parts.append(f"✗ Invalid format: {format_msg}")
        
        # Criterion 3: Complete bookmark set (≥95% URLs)
        if url_match_ratio >= 0.95:
            criteria_met += 1
            results["details"]["complete_bookmark_set"] = True
            feedback_parts.append(f"✓ Complete bookmark set ({url_match_ratio*100:.1f}% URLs matched)")
        else:
            results["details"]["complete_bookmark_set"] = False
            feedback_parts.append(f"✗ Incomplete bookmarks ({url_match_ratio*100:.1f}% URLs matched, need ≥95%)")
        
        # Criterion 4: Folder hierarchy preserved (≥90%)
        if folder_match_ratio >= 0.90:
            criteria_met += 1
            results["details"]["folder_hierarchy_preserved"] = True
            feedback_parts.append(f"✓ Folder hierarchy preserved ({folder_match_ratio*100:.1f}% folders matched)")
        else:
            results["details"]["folder_hierarchy_preserved"] = False
            feedback_parts.append(f"✗ Folder hierarchy incomplete ({folder_match_ratio*100:.1f}% folders matched, need ≥90%)")
        
        # Criterion 5: URL accuracy (all expected URLs present)
        if len(missing_urls) == 0:
            criteria_met += 1
            results["details"]["url_accuracy"] = True
            feedback_parts.append("✓ All URLs accurately exported")
        else:
            results["details"]["url_accuracy"] = False
            feedback_parts.append(f"✗ Missing {len(missing_urls)} URLs from export")
        
        # Criterion 6: Reasonable file size
        if results["details"].get("file_size_ok"):
            criteria_met += 1
            feedback_parts.append(f"✓ File size OK ({file_size} bytes)")
        else:
            feedback_parts.append("✗ File size too small")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        results["score"] = score
        results["passed"] = score >= 85
        results["details"]["criteria_met"] = criteria_met
        results["details"]["total_criteria"] = total_criteria
        
        # Build final feedback
        summary = f"Bookmark Export Verification: {criteria_met}/{total_criteria} criteria met"
        feedback = summary + "\n\n" + "\n".join(feedback_parts)
        
        feedback += f"\n\n{'='*60}"
        feedback += f"\nExport Statistics:"
        feedback += f"\n  - Exported: {len(exported_urls)} URLs, {len(exported_folders)} folders"
        feedback += f"\n  - Source: {len(source_urls)} URLs, {len(source_folders)} folders"
        feedback += f"\n  - Match rate: {url_match_ratio*100:.1f}% URLs, {folder_match_ratio*100:.1f}% folders"
        feedback += f"\n\nFinal Score: {score}%"
        feedback += f"\nResult: {'✅ PASSED' if results['passed'] else '❌ FAILED'}"
        
        if not results["passed"]:
            feedback += f"\n\nTo pass, need at least 5/6 criteria (85%). Currently: {criteria_met}/6."
        
        results["feedback"] = feedback
        
        logger.info(f"Verification complete: passed={results['passed']}, score={score}%")
        
        return results
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_exported_html(copy_from_env) -> Tuple[Optional[str], Optional[str], str]:
    """
    Get the exported HTML file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (html_content, filename, error_message)
    """
    try:
        # First, try to get the filename
        temp_filename_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_filename_file.close()
        
        try:
            copy_from_env("/tmp/export_filename.txt", temp_filename_file.name)
            with open(temp_filename_file.name, 'r') as f:
                found_name = f.read().strip()
            os.unlink(temp_filename_file.name)
            
            if found_name == "none":
                return None, None, "No HTML export file was found in Downloads folder"
        except Exception as e:
            logger.warning(f"Could not read export_filename.txt: {e}")
            found_name = "bookmarks_backup.html"
        
        # Try to copy the HTML export file
        temp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.html', mode='w+')
        temp_html_path = temp_html.name
        temp_html.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/bookmarks_export.html",
            f"/home/ga/Downloads/{found_name}",
            "/home/ga/Downloads/bookmarks_backup.html",
            "/home/ga/Downloads/bookmarks.html",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy HTML from: {container_path}")
                copy_from_env(container_path, temp_html_path)
                
                # Check if file has content
                if Path(temp_html_path).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied HTML from: {container_path}")
                    with open(temp_html_path, 'r', encoding='utf-8', errors='ignore') as f:
                        html_content = f.read()
                    os.unlink(temp_html_path)
                    return html_content, found_name, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        if os.path.exists(temp_html_path):
            os.unlink(temp_html_path)
        return None, None, "HTML export file could not be copied from container"
        
    except Exception as e:
        logger.error(f"Error getting exported HTML: {e}")
        return None, None, f"Error getting exported HTML: {str(e)}"


def get_source_bookmarks(copy_from_env) -> Optional[Dict]:
    """
    Get source Chrome bookmarks from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed bookmarks JSON dict, or None on failure
    """
    try:
        temp_bookmarks = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_bookmarks_path = temp_bookmarks.name
        temp_bookmarks.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/source_bookmarks.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy source bookmarks from: {container_path}")
                copy_from_env(container_path, temp_bookmarks_path)
                
                if Path(temp_bookmarks_path).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied source bookmarks from: {container_path}")
                    bookmarks_data = parse_bookmarks(temp_bookmarks_path)
                    os.unlink(temp_bookmarks_path)
                    return bookmarks_data
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        if os.path.exists(temp_bookmarks_path):
            os.unlink(temp_bookmarks_path)
        return None
        
    except Exception as e:
        logger.error(f"Error getting source bookmarks: {e}")
        return None
