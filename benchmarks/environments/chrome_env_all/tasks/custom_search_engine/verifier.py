#!/usr/bin/env python3
"""
Verifier for Chrome Custom Search Engine Task
Checks if a custom Wikipedia search engine with keyword 'wiki' was added to Chrome
"""

import sys
import os
import json
import re
import logging
from pathlib import Path
from typing import Dict, Any, Optional, List

# Add utils to path
sys.path.insert(0, "/workspace/utils")
from chrome_verification_utils import (
    copy_chrome_file,
    parse_preferences,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_search_engine_entry(prefs: Dict[str, Any], 
                             expected_name: str = "wikipedia",
                             expected_keyword: str = "wiki") -> Optional[Dict[str, Any]]:
    """
    Find custom search engine entry in Chrome Preferences
    
    Args:
        prefs: Parsed Preferences JSON
        expected_name: Expected search engine name (case-insensitive)
        expected_keyword: Expected keyword (case-sensitive)
    
    Returns:
        Dictionary with search engine entry if found, None otherwise
    """
    # Chrome stores custom search engines in multiple possible locations
    # depending on version
    search_locations = []
    
    # Location 1: default_search_provider_data.template_url_data
    if 'default_search_provider_data' in prefs:
        template_data = prefs['default_search_provider_data'].get('template_url_data', [])
        if isinstance(template_data, list):
            search_locations.extend(template_data)
    
    # Location 2: search_provider_overrides
    if 'search_provider_overrides' in prefs:
        overrides = prefs['search_provider_overrides']
        if isinstance(overrides, list):
            search_locations.extend(overrides)
    
    # Location 3: custom_search_providers (older Chrome versions)
    if 'custom_search_providers' in prefs:
        custom = prefs['custom_search_providers']
        if isinstance(custom, list):
            search_locations.extend(custom)
    
    # Location 4: Check in profile.default_search_provider_data (nested)
    if 'profile' in prefs:
        profile_search = prefs['profile'].get('default_search_provider_data', {})
        template_data = profile_search.get('template_url_data', [])
        if isinstance(template_data, list):
            search_locations.extend(template_data)
    
    logger.info(f"Searching through {len(search_locations)} search engine entries")
    
    # Search through all possible locations
    for entry in search_locations:
        if not isinstance(entry, dict):
            continue
        
        # Get entry fields (Chrome uses different field names in different versions)
        name = entry.get('short_name', entry.get('name', '')).lower()
        keyword = entry.get('keyword', entry.get('shortcut', ''))
        url = entry.get('url', '')
        
        logger.debug(f"Checking entry: name='{name}', keyword='{keyword}', url='{url[:50]}...'")
        
        # Check if this matches our expected search engine
        name_match = expected_name.lower() in name
        keyword_match = keyword == expected_keyword
        
        if name_match and keyword_match:
            logger.info(f"Found matching entry: {entry.get('short_name', 'unnamed')}")
            return entry
    
    return None


def validate_search_engine_url(url: str) -> bool:
    """
    Validate that the search engine URL is correct for Wikipedia
    
    Args:
        url: The search engine URL pattern
    
    Returns:
        True if URL is valid for Wikipedia search
    """
    if not url:
        return False
    
    url_lower = url.lower()
    
    # Must contain wikipedia.org domain
    if 'wikipedia.org' not in url_lower:
        logger.warning("URL does not contain wikipedia.org")
        return False
    
    # Must contain a search placeholder
    # Chrome may use: %s, {searchTerms}, or %25s (URL-encoded %s)
    placeholders = ['%s', '{searchterms}', '%25s', '{searchtermdata}']
    has_placeholder = any(p in url_lower for p in placeholders)
    
    if not has_placeholder:
        logger.warning(f"URL does not contain search placeholder: {url}")
        return False
    
    # Should be a search URL (not just main page)
    search_indicators = ['search', 'special:search', 'w/index.php']
    has_search_path = any(indicator in url_lower for indicator in search_indicators)
    
    if not has_search_path:
        logger.warning("URL does not appear to be a search URL")
        return False
    
    return True


def verify_custom_search_engine(traj, env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Main verification function for custom search engine task
    
    Args:
        traj: Trajectory information (not used for this task)
        env_info: Environment information with copy_from_env function
        task_info: Task information
    
    Returns:
        Dictionary with 'passed', 'score', and 'feedback' keys
    """
    logger.info("=== Starting Custom Search Engine Verification ===")
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Error: copy_from_env function not available"
        }
    
    try:
        # Copy Preferences file from container
        success, prefs_path, error = copy_chrome_file("Preferences", copy_from_env)
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Chrome Preferences: {error}"
            }
        
        logger.info(f"Preferences file copied to: {prefs_path}")
        
        # Parse Preferences JSON
        prefs = parse_preferences(prefs_path)
        if not prefs:
            cleanup_verification_temp()
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to parse Chrome Preferences file"
            }
        
        logger.info(f"Preferences file parsed successfully, size: {len(str(prefs))} chars")
        
        # Find the custom search engine entry
        entry = find_search_engine_entry(prefs, 
                                        expected_name="wikipedia",
                                        expected_keyword="wiki")
        
        if not entry:
            cleanup_verification_temp()
            return {
                "passed": False,
                "score": 0,
                "feedback": "Custom search engine with name 'Wikipedia' and keyword 'wiki' not found in Chrome settings"
            }
        
        logger.info(f"Found search engine entry: {entry.get('short_name', 'unnamed')}")
        
        # Validate the URL
        url = entry.get('url', '')
        url_valid = validate_search_engine_url(url)
        
        if not url_valid:
            cleanup_verification_temp()
            return {
                "passed": False,
                "score": 50,
                "feedback": f"Custom search engine found but URL is invalid: {url[:100]}"
            }
        
        # Success!
        cleanup_verification_temp()
        
        name = entry.get('short_name', entry.get('name', 'Wikipedia'))
        keyword = entry.get('keyword', 'wiki')
        
        return {
            "passed": True,
            "score": 100,
            "feedback": f"Successfully added custom search engine '{name}' with keyword '{keyword}' and valid Wikipedia search URL"
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
