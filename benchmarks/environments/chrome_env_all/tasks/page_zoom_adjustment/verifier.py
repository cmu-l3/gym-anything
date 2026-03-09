#!/usr/bin/env python3
"""
Verifier for Chrome Page Zoom Adjustment Task (page_zoom_adjustment@1)
Task: Adjust webpage zoom level to 150% for improved readability

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract per-host zoom levels for wikipedia.org
- Validate that zoom level is set to 1.5 (150%)
- Allow small tolerance (148%-152% acceptable)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        parse_preferences,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def parse_preferences(path):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for page_zoom_adjustment@1.
    
    Verifies that Chrome's page zoom has been increased to 150% (1.5x) for the Wikipedia page.
    
    Args:
        traj: Trajectory data (not used for this verification)
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
            "feedback": "Copy function not available in environment"
        }

    try:
        # Extract zoom level from Chrome Preferences
        zoom_level, domain, error_msg = extract_zoom_level(copy_from_env)
        
        if zoom_level is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract zoom level: {error_msg}"
            }
        
        # Validate zoom level
        is_valid, score, feedback = validate_zoom_level(zoom_level, domain)
        
        # Clean up
        cleanup_verification_temp()
        
        return {
            "passed": is_valid,
            "score": score,
            "feedback": feedback,
            "details": {
                "zoom_level": zoom_level,
                "zoom_percentage": int(zoom_level * 100),
                "domain": domain,
                "target_zoom": 1.5,
                "target_percentage": 150
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_zoom_level(copy_from_env) -> Tuple[Optional[float], Optional[str], str]:
    """
    Extract zoom level setting from Chrome Preferences file.
    
    Chrome stores per-host zoom levels in the Preferences file under:
    - partition.per_host_zoom_levels.<hostname>
    - profile.per_host_zoom_levels.<hostname>
    
    Zoom is stored as decimal: 1.0 = 100%, 1.5 = 150%, 2.0 = 200%
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (zoom_level: float or None, domain: str or None, error_message: str)
    """
    temp_file = None
    try:
        # Create temporary file for preferences
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        preferences_paths = [
            "/tmp/chrome_zoom_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in preferences_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs_data:
            return None, None, "Could not access Chrome Preferences file from any known location"
        
        # Extract zoom levels from preferences
        # Chrome stores zoom in multiple possible locations depending on version
        zoom_level, domain = extract_zoom_from_prefs_data(prefs_data)
        
        if zoom_level is None:
            return None, None, "No zoom level found in Preferences (zoom may not have been changed)"
        
        logger.info(f"Extracted zoom level: {zoom_level} ({int(zoom_level * 100)}%) for domain: {domain}")
        return zoom_level, domain, ""
        
    except json.JSONDecodeError as e:
        return None, None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, None, f"Error extracting zoom level: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def extract_zoom_from_prefs_data(prefs: Dict[str, Any]) -> Tuple[Optional[float], Optional[str]]:
    """
    Extract zoom level from parsed Preferences data.
    
    Chrome stores zoom levels in nested structures. We need to search through:
    1. partition.per_host_zoom_levels
    2. profile.per_host_zoom_levels
    3. Look for wikipedia.org or en.wikipedia.org entries
    
    Args:
        prefs: Parsed Preferences JSON data
        
    Returns:
        Tuple of (zoom_level: float or None, domain: str or None)
    """
    target_domains = ['wikipedia.org', 'en.wikipedia.org', 'en.m.wikipedia.org']
    
    # Try partition.per_host_zoom_levels first (newer Chrome versions)
    partition = prefs.get('partition', {})
    per_host_zoom = partition.get('per_host_zoom_levels', {})
    
    # Also check profile location (older Chrome versions)
    if not per_host_zoom:
        profile = prefs.get('profile', {})
        per_host_zoom = profile.get('per_host_zoom_levels', {})
    
    logger.info(f"Found per_host_zoom_levels keys: {list(per_host_zoom.keys())}")
    
    # Search for zoom levels in the data structure
    # The structure can vary:
    # - Direct mapping: {"en.wikipedia.org,443,1": 1.5}
    # - Nested: {"x": {"en.wikipedia.org,443,1": 1.5}}
    
    # Check direct keys
    for key, value in per_host_zoom.items():
        if isinstance(value, dict):
            # Nested structure, recurse
            for nested_key, nested_value in value.items():
                if any(domain in str(nested_key).lower() for domain in target_domains):
                    if isinstance(nested_value, (int, float)):
                        return float(nested_value), extract_domain_from_key(nested_key)
        else:
            # Direct value
            if any(domain in str(key).lower() for domain in target_domains):
                if isinstance(value, (int, float)):
                    return float(value), extract_domain_from_key(key)
    
    # Check for default zoom level as fallback
    default_zoom = partition.get('default_zoom_level')
    if default_zoom and default_zoom != 0.0:
        logger.info(f"Using default zoom level: {default_zoom}")
        return float(default_zoom), "default"
    
    # Also check profile default
    profile_default = prefs.get('profile', {}).get('default_zoom_level')
    if profile_default and profile_default != 0.0:
        logger.info(f"Using profile default zoom level: {profile_default}")
        return float(profile_default), "default"
    
    return None, None


def extract_domain_from_key(key: str) -> str:
    """
    Extract domain name from Chrome's zoom key format.
    
    Chrome uses keys like: "en.wikipedia.org,443,1" or "wikipedia.org"
    
    Args:
        key: Chrome zoom key
        
    Returns:
        Domain name (e.g., "en.wikipedia.org")
    """
    if ',' in key:
        # Format: "domain,port,partition"
        return key.split(',')[0]
    return key


def validate_zoom_level(zoom_level: float, domain: Optional[str]) -> Tuple[bool, int, str]:
    """
    Validate that zoom level was appropriately set to 150%.
    
    Args:
        zoom_level: Zoom level as decimal (1.5 for 150%)
        domain: Domain the zoom was applied to
        
    Returns:
        Tuple of (is_valid: bool, score: int, feedback: str)
    """
    TARGET_ZOOM = 1.5  # 150%
    DEFAULT_ZOOM = 1.0  # 100%
    EXACT_TOLERANCE = 0.01  # ±1% for perfect score
    GOOD_TOLERANCE = 0.02  # ±2% for passing score
    ACCEPTABLE_TOLERANCE = 0.05  # ±5% for partial credit
    
    zoom_percentage = int(zoom_level * 100)
    target_percentage = int(TARGET_ZOOM * 100)
    difference = abs(zoom_level - TARGET_ZOOM)
    difference_pct = abs(zoom_percentage - target_percentage)
    
    # Check if zoom is at default (not changed)
    if abs(zoom_level - DEFAULT_ZOOM) < 0.01:
        return False, 0, f"✗ Zoom level unchanged at {zoom_percentage}% (default). Task requires increasing zoom to {target_percentage}%."
    
    # Check if zoom was decreased instead of increased
    if zoom_level < DEFAULT_ZOOM:
        return False, 0, f"✗ Zoom level was decreased to {zoom_percentage}% instead of increased. Target is {target_percentage}%."
    
    # Check if zoom is in wrong direction (too high)
    if zoom_level > 2.0:  # 200%
        return False, 40, f"⚠ Zoom level at {zoom_percentage}% is too high (exceeds 200%). Target is {target_percentage}%."
    
    # Perfect match (within ±1%)
    if difference <= EXACT_TOLERANCE:
        feedback = f"✓ Perfect! Zoom level set to {zoom_percentage}% (target: {target_percentage}%)."
        if domain and 'wikipedia' in domain.lower():
            feedback += f" Applied to {domain}."
        return True, 100, feedback
    
    # Very close (within ±2%, passing)
    if difference <= GOOD_TOLERANCE:
        feedback = f"✓ Excellent! Zoom level at {zoom_percentage}% is very close to target {target_percentage}% (difference: {difference_pct}%)."
        if domain:
            feedback += f" Applied to {domain}."
        return True, 95, feedback
    
    # Acceptable (within ±5%, passing)
    if difference <= ACCEPTABLE_TOLERANCE:
        feedback = f"✓ Good! Zoom level at {zoom_percentage}% is close to target {target_percentage}% (difference: {difference_pct}%)."
        if domain:
            feedback += f" Applied to {domain}."
        return True, 85, feedback
    
    # Changed but not to target (wrong zoom level)
    if zoom_level > DEFAULT_ZOOM:
        if zoom_level < TARGET_ZOOM:
            feedback = f"⚠ Zoom increased to {zoom_percentage}% but didn't reach target {target_percentage}%. Need {difference_pct}% more."
            score = 60  # Partial credit
        else:
            feedback = f"⚠ Zoom increased to {zoom_percentage}% which exceeds target {target_percentage}% by {difference_pct}%."
            score = 70  # Partial credit
        
        return False, score, feedback
    
    # Default case
    return False, 0, f"✗ Zoom level at {zoom_percentage}% does not match target {target_percentage}%."
