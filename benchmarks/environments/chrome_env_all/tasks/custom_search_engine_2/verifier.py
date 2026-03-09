#!/usr/bin/env python3
"""
Verifier for Chrome Custom Search Engine Task (custom_search_engine@1)

Task: Add a custom search engine in Chrome with:
  - Name: Wikipedia
  - Keyword: wiki
  - URL: https://en.wikipedia.org/wiki/Special:Search?search=%s

Verification Strategy:
  - Parse Chrome's Preferences JSON file
  - Look for custom search engine entry in multiple possible locations
  - Verify name matches "Wikipedia" (case-insensitive)
  - Verify keyword matches "wiki" (case-sensitive)
  - Verify URL contains Wikipedia search URL with placeholder (%s or {searchTerms})
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add workspace utils to path
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))


def parse_preferences(prefs_path: str) -> Dict[str, Any]:
    """Parse Chrome Preferences JSON file."""
    try:
        with open(prefs_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Error parsing Preferences file: {e}")
        return {}


def find_custom_search_engine(prefs: Dict[str, Any], 
                              expected_name: str = "wikipedia",
                              expected_keyword: str = "wiki") -> Optional[Dict[str, Any]]:
    """
    Find custom search engine entry in Chrome Preferences.
    
    Chrome stores custom search engines in different locations depending on version:
    1. default_search_provider_data.template_url_data (array)
    2. search_provider_overrides (array)
    3. profile.custom_search_providers (array)
    """
    
    search_locations = [
        ('default_search_provider_data', 'template_url_data'),
        ('search_provider_overrides', None),
        ('profile', 'custom_search_providers'),
    ]
    
    for location in search_locations:
        data = prefs
        for key in location:
            if key is None:
                break
            data = data.get(key, {})
            if not data:
                break
        
        if isinstance(data, list):
            logger.info(f"Searching in location: {' -> '.join(filter(None, location))}, found {len(data)} entries")
            
            for entry in data:
                if not isinstance(entry, dict):
                    continue
                
                # Check various field names that Chrome might use
                name = entry.get('short_name', entry.get('name', '')).lower()
                keyword = entry.get('keyword', entry.get('shortcut', ''))
                url = entry.get('url', '')
                
                logger.debug(f"Checking entry: name={name}, keyword={keyword}, url={url[:50]}...")
                
                # Match by keyword first (most specific), then verify name
                if keyword == expected_keyword:
                    logger.info(f"Found entry with matching keyword '{expected_keyword}': name={name}")
                    if expected_name in name:
                        return entry
                
                # Also check if name matches and keyword is close
                if expected_name in name and keyword == expected_keyword:
                    return entry
    
    # If exact keyword match not found, try broader search
    logger.info("Exact keyword match not found, trying broader search...")
    for location in search_locations:
        data = prefs
        for key in location:
            if key is None:
                break
            data = data.get(key, {})
            if not data:
                break
        
        if isinstance(data, list):
            for entry in data:
                if not isinstance(entry, dict):
                    continue
                
                name = entry.get('short_name', entry.get('name', '')).lower()
                keyword = entry.get('keyword', entry.get('shortcut', ''))
                
                # Check if both name and keyword are present (even if not exact)
                if expected_name in name and expected_keyword in keyword.lower():
                    logger.info(f"Found partial match: name={name}, keyword={keyword}")
                    return entry
    
    return None


def validate_search_engine_url(url: str, expected_domain: str = "wikipedia.org") -> bool:
    """
    Validate that the search engine URL is correct.
    
    The URL should:
    1. Contain the expected domain (wikipedia.org)
    2. Contain a search query placeholder (%s, {searchTerms}, or %25s URL-encoded)
    """
    if not url:
        return False
    
    url_lower = url.lower()
    
    # Check domain
    if expected_domain.lower() not in url_lower:
        logger.info(f"Domain check failed: {expected_domain} not in {url}")
        return False
    
    # Check for query placeholder (various formats Chrome might use)
    placeholders = ['%s', '{searchterms}', '%25s', '{searchTerms}']
    has_placeholder = any(ph in url.lower() for ph in [p.lower() for p in placeholders])
    
    if not has_placeholder:
        logger.info(f"Placeholder check failed: no valid placeholder found in {url}")
        return False
    
    return True


def verify_task(traj, env_info, task_info):
    """
    Main verification function for custom search engine task.
    
    Returns:
        dict: Verification result with keys: passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    try:
        # Get Chrome Preferences file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        success = copy_from_env("/tmp/chrome_preferences.json", temp_path)
        
        if not success:
            # Try alternate return format (tuple)
            result = copy_from_env("/tmp/chrome_preferences.json", temp_path)
            if isinstance(result, tuple):
                success = result[0]
        
        if not success or not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve Chrome Preferences file. Ensure Chrome was closed properly."
            }
        
        # Parse Preferences
        prefs = parse_preferences(temp_path)
        os.unlink(temp_path)  # Clean up temp file
        
        if not prefs:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to parse Chrome Preferences JSON"
            }
        
        # Find the custom search engine
        entry = find_custom_search_engine(prefs, expected_name="wikipedia", expected_keyword="wiki")
        
        if not entry:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Custom search engine with keyword 'wiki' not found in Chrome Preferences. "
                           "Make sure to add the search engine through chrome://settings/searchEngines."
            }
        
        # Validate the entry
        name = entry.get('short_name', entry.get('name', ''))
        keyword = entry.get('keyword', entry.get('shortcut', ''))
        url = entry.get('url', '')
        
        logger.info(f"Found search engine - Name: {name}, Keyword: {keyword}, URL: {url}")
        
        # Check name (case-insensitive)
        name_valid = 'wikipedia' in name.lower()
        if not name_valid:
            return {
                "passed": False,
                "score": 40,
                "feedback": f"Search engine found with keyword 'wiki' but name is '{name}' instead of 'Wikipedia'"
            }
        
        # Check keyword (case-sensitive for keywords)
        keyword_valid = keyword == 'wiki'
        if not keyword_valid:
            return {
                "passed": False,
                "score": 40,
                "feedback": f"Search engine found but keyword is '{keyword}' instead of 'wiki'"
            }
        
        # Check URL
        url_valid = validate_search_engine_url(url, expected_domain="wikipedia.org")
        if not url_valid:
            return {
                "passed": False,
                "score": 60,
                "feedback": f"Search engine configured but URL is invalid: {url}. "
                           "Expected Wikipedia search URL with %s placeholder."
            }
        
        # All checks passed
        return {
            "passed": True,
            "score": 100,
            "feedback": f"✓ Custom Wikipedia search engine successfully configured!\n"
                       f"  Name: {name}\n"
                       f"  Keyword: {keyword}\n"
                       f"  URL: {url}\n"
                       f"You can now type 'wiki <query>' in the address bar for quick Wikipedia searches."
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
