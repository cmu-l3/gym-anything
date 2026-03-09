#!/usr/bin/env python3
"""
Verifier for Chrome Page Zoom Accessibility Task (page_zoom_accessibility@1)
Task: Increase Chrome's page zoom to 125-150% for better readability

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract profile.per_host_zoom_levels
- Identify the zoom level for the Wikipedia domain (en.wikipedia.org)
- Convert Chrome's logarithmic zoom storage to percentage
- Validate zoom is between 125% and 200% (passing: ≥125%)
- Optimal range: 125-150%
"""

import logging
import sys
import os
import json
import math
import tempfile
from pathlib import Path
from urllib.parse import urlparse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        setup_chrome_verification,
        cleanup_verification_temp,
        parse_preferences
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False


def verify_task(traj, env_info, task_info):
    """
    Main verification function for page_zoom_accessibility@1.
    
    Verifies that Chrome's page zoom has been increased for the task page.
    
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
        # Get expected domain from task setup
        expected_domain = "en.wikipedia.org:443"
        
        # Extract zoom level from Chrome preferences
        zoom_data = extract_zoom_level_from_prefs(copy_from_env, expected_domain)
        
        if zoom_data["error"]:
            return {
                "passed": False,
                "score": 0,
                "feedback": zoom_data["error"],
                "details": {
                    "domain": expected_domain,
                    "zoom_percentage": None
                }
            }
        
        zoom_percentage = zoom_data["zoom_percentage"]
        zoom_factor = zoom_data["zoom_factor"]
        raw_value = zoom_data["raw_value"]
        
        # Validate zoom level
        is_valid, score, feedback = validate_zoom_level(
            zoom_percentage, 
            expected_domain
        )
        
        return {
            "passed": is_valid,
            "score": score,
            "feedback": feedback,
            "details": {
                "domain": expected_domain,
                "zoom_percentage": zoom_percentage,
                "zoom_factor": zoom_factor,
                "raw_stored_value": raw_value,
                "default_zoom": 100,
                "increase": zoom_percentage - 100
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_zoom_level_from_prefs(copy_from_env, expected_domain):
    """
    Extract zoom level for specific domain from Chrome Preferences file.
    
    Chrome stores zoom levels as: log(zoom_factor) / log(1.2)
    Example: 1.25x zoom → stored as ~1.29
             1.50x zoom → stored as ~2.43
    
    Args:
        copy_from_env: Function to copy files from container
        expected_domain: Domain to check zoom for (e.g., "en.wikipedia.org:443")
        
    Returns:
        Dict with zoom_percentage, zoom_factor, raw_value, and error keys
    """
    temp_file = None
    result = {
        "zoom_percentage": None,
        "zoom_factor": None,
        "raw_value": None,
        "error": None
    }
    
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
            success, files, error = setup_chrome_verification(
                copy_from_env,
                ["Preferences"],
                user="ga",
                profile="Default"
            )
            
            if success:
                prefs = parse_preferences(files["Preferences"])
                zoom_data = extract_zoom_from_prefs_data(prefs, expected_domain)
                cleanup_verification_temp()
                return zoom_data
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_paths = [
            "/tmp/zoom_verification/chrome_preferences.json",
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        for container_path in prefs_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    logger.info(f"Successfully loaded preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs:
            result["error"] = "Could not access Chrome Preferences file from any known location"
            return result
        
        # Extract zoom data
        zoom_data = extract_zoom_from_prefs_data(prefs, expected_domain)
        return zoom_data
        
    except json.JSONDecodeError as e:
        result["error"] = f"Failed to parse Preferences JSON: {e}"
        return result
    except Exception as e:
        result["error"] = f"Error extracting zoom level: {e}"
        return result
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def extract_zoom_from_prefs_data(prefs, expected_domain):
    """
    Extract zoom level from parsed preferences data.
    
    Args:
        prefs: Parsed Chrome preferences dictionary
        expected_domain: Domain to check zoom for
        
    Returns:
        Dict with zoom data or error
    """
    result = {
        "zoom_percentage": None,
        "zoom_factor": None,
        "raw_value": None,
        "error": None
    }
    
    try:
        # Navigate to per_host_zoom_levels
        profile = prefs.get('profile', {})
        per_host_zoom = profile.get('per_host_zoom_levels', {})
        
        if not per_host_zoom:
            result["error"] = "No per-host zoom levels found in preferences (zoom may not have been changed)"
            return result
        
        # Log all domains with zoom settings for debugging
        logger.info(f"Domains with zoom settings: {list(per_host_zoom.keys())}")
        
        # Check for exact domain match
        if expected_domain in per_host_zoom:
            raw_zoom = per_host_zoom[expected_domain]
        else:
            # Try without port
            domain_without_port = expected_domain.split(':')[0]
            matching_domains = [d for d in per_host_zoom.keys() if domain_without_port in d]
            
            if matching_domains:
                # Use the first matching domain
                matched_domain = matching_domains[0]
                raw_zoom = per_host_zoom[matched_domain]
                logger.info(f"Using zoom from matched domain: {matched_domain}")
            else:
                result["error"] = f"No zoom level set for {expected_domain} or similar domains. Available domains: {list(per_host_zoom.keys())}"
                return result
        
        # Convert Chrome's logarithmic zoom storage to zoom factor
        # Formula: zoom_factor = 1.2 ^ raw_zoom
        zoom_factor = math.pow(1.2, raw_zoom)
        zoom_percentage = zoom_factor * 100
        
        result["zoom_percentage"] = zoom_percentage
        result["zoom_factor"] = zoom_factor
        result["raw_value"] = raw_zoom
        
        logger.info(f"Extracted zoom: raw={raw_zoom:.4f}, factor={zoom_factor:.4f}, percentage={zoom_percentage:.1f}%")
        
        return result
        
    except Exception as e:
        result["error"] = f"Error parsing zoom data: {e}"
        return result


def validate_zoom_level(zoom_percentage, domain):
    """
    Validate that zoom level is appropriately increased for accessibility.
    
    Criteria:
    - Must be ≥125% to pass (75% threshold)
    - Optimal range: 125-150%
    - Maximum acceptable: 200%
    - Score based on how well it meets accessibility goals
    
    Args:
        zoom_percentage: Zoom level as percentage (e.g., 125.0 for 125%)
        domain: Domain the zoom was applied to
        
    Returns:
        Tuple of (is_valid: bool, score: int, feedback: str)
    """
    DEFAULT_ZOOM = 100.0
    MIN_PASSING = 125.0
    OPTIMAL_MIN = 125.0
    OPTIMAL_MAX = 150.0
    MAX_ACCEPTABLE = 200.0
    
    # Round to 1 decimal place for cleaner feedback
    zoom_percentage = round(zoom_percentage, 1)
    increase = zoom_percentage - DEFAULT_ZOOM
    
    feedback_parts = []
    
    # Check if zoom is unchanged (still at default)
    if abs(zoom_percentage - DEFAULT_ZOOM) < 1.0:  # Within 1% of default
        return (
            False, 
            0, 
            f"❌ Page zoom unchanged from default (100%)\n"
            f"Please increase zoom using Ctrl++ or Chrome menu → Zoom controls"
        )
    
    # Check if zoom was decreased instead of increased
    if zoom_percentage < DEFAULT_ZOOM:
        return (
            False,
            0,
            f"❌ Page zoom was decreased to {zoom_percentage:.0f}% instead of increased\n"
            f"Default zoom is 100%. Task requires increasing zoom to ≥125%"
        )
    
    # Check if increase is too small (less than 25% increase)
    if zoom_percentage < MIN_PASSING:
        return (
            False,
            max(30, int((zoom_percentage - DEFAULT_ZOOM) / (MIN_PASSING - DEFAULT_ZOOM) * 60)),
            f"❌ Page zoom only increased to {zoom_percentage:.0f}% (+{increase:.0f}%)\n"
            f"This is insufficient for accessibility needs. Minimum required: 125%\n"
            f"Press Ctrl++ a few more times to reach the target zoom level"
        )
    
    # Check if zoom is unreasonably high
    if zoom_percentage > MAX_ACCEPTABLE:
        return (
            False,
            50,
            f"❌ Page zoom of {zoom_percentage:.0f}% is unreasonably high\n"
            f"Maximum acceptable zoom is {MAX_ACCEPTABLE:.0f}% to maintain usability\n"
            f"Use Ctrl+0 to reset, then zoom to 125-150%"
        )
    
    # Zoom is passing (≥125%), now determine quality of the choice
    
    # Optimal range: 125-150%
    if OPTIMAL_MIN <= zoom_percentage <= OPTIMAL_MAX:
        feedback_parts.append(f"✅ Excellent! Page zoom set to {zoom_percentage:.0f}% (+{increase:.0f}%)")
        feedback_parts.append(f"This is the optimal range for accessibility and readability")
        feedback_parts.append(f"Domain: {domain}")
        return (True, 100, "\n".join(feedback_parts))
    
    # Slightly above optimal range (151-175%)
    if 150 < zoom_percentage <= 175:
        feedback_parts.append(f"✅ Good! Page zoom set to {zoom_percentage:.0f}% (+{increase:.0f}%)")
        feedback_parts.append(f"This is slightly higher than optimal (125-150%) but still very usable")
        feedback_parts.append(f"Domain: {domain}")
        return (True, 90, "\n".join(feedback_parts))
    
    # High but acceptable (176-200%)
    if 175 < zoom_percentage <= MAX_ACCEPTABLE:
        feedback_parts.append(f"✅ Page zoom set to {zoom_percentage:.0f}% (+{increase:.0f}%)")
        feedback_parts.append(f"⚠ This is near the maximum recommended zoom")
        feedback_parts.append(f"May require horizontal scrolling on some pages")
        feedback_parts.append(f"Domain: {domain}")
        return (True, 80, "\n".join(feedback_parts))
    
    # Minimal passing (exactly 125%)
    if zoom_percentage == MIN_PASSING:
        feedback_parts.append(f"✅ Page zoom set to {zoom_percentage:.0f}% (+{increase:.0f}%)")
        feedback_parts.append(f"This meets the minimum requirement for improved accessibility")
        feedback_parts.append(f"Domain: {domain}")
        return (True, 85, "\n".join(feedback_parts))
    
    # Should not reach here, but provide fallback
    return (True, 75, f"✅ Page zoom set to {zoom_percentage:.0f}% (+{increase:.0f}%)")
