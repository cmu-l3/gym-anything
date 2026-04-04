#!/usr/bin/env python3
"""
Chrome verification utilities for gym-anything tasks
Provides helper functions to verify Chrome-based tasks using CDP and file system checks
"""

import json
import os
import sqlite3
import logging
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional, Callable

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_chrome_profile_path(user="ga", profile="Default"):
    """Get the path to Chrome profile directory"""
    return f"/home/{user}/.config/google-chrome/{profile}"


def copy_chrome_file(filename: str, copy_from_env_fn: Callable, user="ga", profile="Default") -> Tuple[bool, str, str]:
    """
    Copy a Chrome configuration/data file from container to host
    
    Args:
        filename: Name of file to copy (e.g., "Bookmarks", "History", "Cookies")
        copy_from_env_fn: Function to copy file from container
        user: Chrome user name
        profile: Chrome profile name
        
    Returns:
        Tuple of (success, local_path, error_message)
    """
    chrome_path = get_chrome_profile_path(user, profile)
    container_path = f"{chrome_path}/{filename}"
    
    temp_dir = Path(os.getcwd()) / "temp_chrome_verification"
    temp_dir.mkdir(exist_ok=True)
    
    host_path = temp_dir / filename
    
    try:
       copy_from_env_fn(container_path, str(host_path))
       success = True
    except Exception as e:
        success = False
        error = str(e)
    
    if not success:
        return False, "", f"Failed to copy {filename}: {error}"
    
    if not host_path.exists() or host_path.stat().st_size == 0:
        return False, "", f"{filename} not found or empty"
    
    return True, str(host_path), ""


def get_active_tab_info_from_cdp(copy_from_env_fn: Callable) -> Dict[str, Any]:
    """
    Get active tab information using CDP utility
    
    Returns:
        Dict with 'url', 'title', and other tab info
    """
    # We'll execute the CDP utility script inside the container
    # and get its output via a temp file
    temp_file = "/tmp/active_tab_info.json"
    
    try:
        # This would be executed via the container's exec
        # For now, return structure - implementation depends on how exec works
        return {"url": "", "title": "", "content": ""}
    except Exception as e:
        logger.error(f"Error getting active tab info: {e}")
        return {}


def parse_bookmarks(bookmarks_path: str) -> Dict[str, Any]:
    """Parse Chrome bookmarks file"""
    try:
        with open(bookmarks_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Error parsing bookmarks: {e}")
        return {}


def get_bookmark_bar_folders(bookmarks_path: str) -> List[str]:
    """Get folder names from bookmarks bar"""
    bookmarks = parse_bookmarks(bookmarks_path)
    if not bookmarks:
        return []
    
    bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    return [child['name'] for child in children if child.get('type') == 'folder']


def get_bookmark_bar_urls(bookmarks_path: str) -> List[str]:
    """Get URLs from bookmarks bar"""
    bookmarks = parse_bookmarks(bookmarks_path)
    if not bookmarks:
        return []
    
    bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    return [child['url'] for child in children if child.get('type') == 'url']


def get_folder_bookmarks(bookmarks_path: str, folder_name: str) -> List[str]:
    """Get URLs from a specific bookmark folder"""
    bookmarks = parse_bookmarks(bookmarks_path)
    if not bookmarks:
        return []
    
    bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    for child in children:
        if child.get('type') == 'folder' and child.get('name') == folder_name:
            return [item['url'] for item in child.get('children', []) if item.get('type') == 'url']
    
    return []


def parse_history(history_path: str) -> List[Tuple[str, str]]:
    """
    Parse Chrome history database
    
    Returns:
        List of (url, title) tuples
    """
    try:
        conn = sqlite3.connect(history_path)
        cursor = conn.cursor()
        cursor.execute("SELECT url, title FROM urls ORDER BY last_visit_time DESC")
        results = cursor.fetchall()
        conn.close()
        return results
    except Exception as e:
        logger.error(f"Error parsing history: {e}")
        return []


def parse_cookies(cookies_path: str) -> List[Tuple[str, str]]:
    """
    Parse Chrome cookies database
    
    Returns:
        List of (name, host_key) tuples
    """
    try:
        conn = sqlite3.connect(cookies_path)
        cursor = conn.cursor()
        cursor.execute("SELECT name, host_key FROM cookies")
        results = cursor.fetchall()
        conn.close()
        return results
    except Exception as e:
        logger.error(f"Error parsing cookies: {e}")
        return []


def parse_preferences(prefs_path: str) -> Dict[str, Any]:
    """Parse Chrome Preferences file"""
    try:
        with open(prefs_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Error parsing preferences: {e}")
        return {}


def get_font_size(prefs_path: str) -> Dict[str, int]:
    """Get font size settings from preferences"""
    prefs = parse_preferences(prefs_path)
    webkit = prefs.get('webkit', {}).get('webprefs', {})
    
    return {
        'default_font_size': webkit.get('default_font_size', 16),
        'default_fixed_font_size': webkit.get('default_fixed_font_size', 13),
        'minimum_font_size': webkit.get('minimum_font_size', 0)
    }


def get_installed_extensions(extensions_dir: str) -> List[str]:
    """
    Get list of installed Chrome extensions
    
    Args:
        extensions_dir: Path to Chrome extensions directory
        
    Returns:
        List of extension IDs
    """
    try:
        if not os.path.exists(extensions_dir):
            return []
        
        extensions = []
        for item in os.listdir(extensions_dir):
            item_path = os.path.join(extensions_dir, item)
            if os.path.isdir(item_path):
                # Check if it's a valid extension (has manifest.json)
                manifest_path = os.path.join(item_path, "manifest.json")
                if os.path.exists(manifest_path):
                    extensions.append(item)
        
        return extensions
    except Exception as e:
        logger.error(f"Error getting extensions: {e}")
        return []


def check_history_contains_keyword(history_path: str, keyword: str) -> bool:
    """Check if history contains a URL with the given keyword"""
    history = parse_history(history_path)
    for url, _ in history:
        if keyword.lower() in url.lower():
            return True
    return False


def check_cookie_for_domain(cookies_path: str, domain: str) -> bool:
    """Check if cookies exist for a specific domain"""
    cookies = parse_cookies(cookies_path)
    for _, host_key in cookies:
        if domain.lower() in host_key.lower():
            return True
    return False


def cleanup_verification_temp(temp_dir: Optional[str] = None):
    """Clean up temporary verification files"""
    if temp_dir is None:
        temp_dir = os.path.join(os.getcwd(), "temp_chrome_verification")
    
    import shutil
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)


def setup_chrome_verification(copy_from_env_fn: Callable, files_to_copy: List[str], 
                              user="ga", profile="Default") -> Tuple[bool, Dict[str, str], str]:
    """
    Set up Chrome verification environment by copying necessary files
    
    Args:
        copy_from_env_fn: Function to copy files from container
        files_to_copy: List of file names to copy (e.g., ["Bookmarks", "History"])
        user: Chrome user name
        profile: Chrome profile name
        
    Returns:
        Tuple of (success, file_paths_dict, error_message)
    """
    file_paths = {}
    
    for filename in files_to_copy:
        success, local_path, error = copy_chrome_file(filename, copy_from_env_fn, user, profile)
        if not success:
            cleanup_verification_temp()
            return False, {}, error
        file_paths[filename] = local_path
    
    return True, file_paths, ""


# Example verifier functions matching OSWorld Chrome metrics

def verify_url_pattern(active_tab_url: str, patterns: List[str]) -> bool:
    """Verify URL matches expected patterns (regex)"""
    import re
    for pattern in patterns:
        if not re.search(pattern, active_tab_url):
            return False
    return True


def verify_bookmarks_folders(bookmarks_path: str, expected_folders: List[str]) -> bool:
    """Verify bookmark bar contains expected folders"""
    actual_folders = set(get_bookmark_bar_folders(bookmarks_path))
    expected_set = set(expected_folders)
    return actual_folders == expected_set


def verify_bookmarks_urls(bookmarks_path: str, expected_urls: List[str]) -> bool:
    """Verify bookmark bar contains expected URLs"""
    actual_urls = set(get_bookmark_bar_urls(bookmarks_path))
    expected_set = set(expected_urls)
    return actual_urls == expected_set

