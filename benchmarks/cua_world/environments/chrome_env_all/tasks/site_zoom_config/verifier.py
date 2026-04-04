#!/usr/bin/env python3
"""
Verifier for Chrome Site-Specific Zoom Configuration Task (site_zoom_config@1)
Task: Configure permanent site-specific zoom level for docs.python.org

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract profile.per_host_zoom_levels
- Find zoom setting for docs.python.org domain
- Validate zoom value is positive and represents increase (>100%)
- Convert logarithmic zoom value to percentage
- Ensure zoom is in reasonable range (115-200%)
"""

import logging
import sys
import os
import json
import tempfile
import math
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import (
        copy_chrome_file,
        parse_preferences,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def cleanup_verification_temp():
        """Fallback cleanup function"""
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for site_zoom_config@1.
    
    Verifies that site-specific zoom has been configured for docs.python.org
    with a meaningful increase from default (100%).
    
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
        # Extract zoom configuration from Preferences
        zoom_info = extract_site_zoom_config(copy_from_env)
        
        if zoom_info['error']:
            return {
                "passed": False,
                "score": 0,
                "feedback": zoom_info['error']
            }
        
        # Validate zoom configuration
        validation_result = validate_zoom_configuration(zoom_info)
        
        return validation_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_site_zoom_config(copy_from_env):
    """
    Extract site-specific zoom configuration from Chrome Preferences.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict with zoom configuration info or error message
    """
    temp_file = None
    try:
        # Create temporary file for Preferences
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations for Preferences file
        preferences_paths = [
            "/tmp/chrome_preferences_zoom.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in preferences_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs_data:
            return {
                'error': "Could not access Chrome Preferences file from any known location",
                'zoom_value': None,
                'zoom_percentage': None,
                'domain': None
            }
        
        # Extract per-host zoom levels
        profile = prefs_data.get('profile', {})
        per_host_zoom_levels = profile.get('per_host_zoom_levels', {})
        
        if not per_host_zoom_levels:
            return {
                'error': "No site-specific zoom settings found in Chrome Preferences. Agent may not have configured zoom.",
                'zoom_value': None,
                'zoom_percentage': None,
                'domain': None
            }
        
        # Look for docs.python.org specifically
        # Chrome may store domain with various formats
        target_domain = None
        zoom_value = None
        
        for domain_key, zoom_val in per_host_zoom_levels.items():
            if 'docs.python.org' in domain_key.lower():
                target_domain = domain_key
                zoom_value = zoom_val
                logger.info(f"Found zoom setting for: {domain_key} = {zoom_val}")
                break
        
        if target_domain is None or zoom_value is None:
            # List available domains for debugging
            available_domains = list(per_host_zoom_levels.keys())
            logger.warning(f"docs.python.org not found. Available domains: {available_domains}")
            return {
                'error': f"No zoom setting found for docs.python.org. Found zoom for: {available_domains if available_domains else 'no domains'}",
                'zoom_value': None,
                'zoom_percentage': None,
                'domain': None
            }
        
        # Convert log-scale zoom to percentage
        # Chrome stores zoom as log2(zoom_factor)
        # zoom_percentage = 100 * (2 ** zoom_value)
        try:
            zoom_value_float = float(zoom_value)
            zoom_percentage = 100.0 * (2 ** zoom_value_float)
        except (ValueError, TypeError) as e:
            return {
                'error': f"Invalid zoom value format: {zoom_value}",
                'zoom_value': zoom_value,
                'zoom_percentage': None,
                'domain': target_domain
            }
        
        logger.info(f"Zoom configuration: {target_domain} -> {zoom_value} (log scale) = {zoom_percentage:.1f}%")
        
        return {
            'error': None,
            'zoom_value': zoom_value_float,
            'zoom_percentage': zoom_percentage,
            'domain': target_domain
        }
        
    except json.JSONDecodeError as e:
        return {
            'error': f"Failed to parse Preferences JSON: {e}",
            'zoom_value': None,
            'zoom_percentage': None,
            'domain': None
        }
    except Exception as e:
        return {
            'error': f"Error extracting zoom configuration: {e}",
            'zoom_value': None,
            'zoom_percentage': None,
            'domain': None
        }
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
        cleanup_verification_temp()


def validate_zoom_configuration(zoom_info):
    """
    Validate that zoom configuration meets task requirements.
    
    Args:
        zoom_info: Dict with zoom configuration details
        
    Returns:
        Dict with passed, score, and feedback
    """
    zoom_percentage = zoom_info.get('zoom_percentage')
    zoom_value = zoom_info.get('zoom_value')
    domain = zoom_info.get('domain', 'docs.python.org')
    
    if zoom_percentage is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not extract valid zoom percentage from Preferences"
        }
    
    # Define thresholds
    DEFAULT_ZOOM = 100.0
    MIN_MEANINGFUL = 115.0  # At least 15% increase
    OPTIMAL_MIN = 125.0
    OPTIMAL_MAX = 150.0
    MAX_REASONABLE = 200.0
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Site-specific zoom for {domain}:")
    feedback_parts.append(f"  Zoom value: {zoom_value:.3f} (log scale)")
    feedback_parts.append(f"  Zoom percentage: {zoom_percentage:.1f}%")
    feedback_parts.append(f"  Increase: +{zoom_percentage - DEFAULT_ZOOM:.1f}%")
    
    # Validate zoom level
    if zoom_percentage <= DEFAULT_ZOOM:
        feedback_parts.append(f"\n✗ Zoom is at or below default ({DEFAULT_ZOOM}%). No increase detected.")
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts),
            "details": zoom_info
        }
    
    if zoom_percentage < MIN_MEANINGFUL:
        feedback_parts.append(f"\n✗ Zoom increase too small ({zoom_percentage:.1f}%). Need at least {MIN_MEANINGFUL:.1f}% for meaningful readability improvement.")
        return {
            "passed": False,
            "score": 30,
            "feedback": "\n".join(feedback_parts),
            "details": zoom_info
        }
    
    if zoom_percentage > MAX_REASONABLE:
        feedback_parts.append(f"\n✗ Zoom excessively large ({zoom_percentage:.1f}%). Should not exceed {MAX_REASONABLE:.1f}%.")
        return {
            "passed": False,
            "score": 50,
            "feedback": "\n".join(feedback_parts),
            "details": zoom_info
        }
    
    # Calculate score based on zoom appropriateness
    if OPTIMAL_MIN <= zoom_percentage <= OPTIMAL_MAX:
        score = 100
        quality = "excellent"
        feedback_parts.append(f"\n✓ Zoom configured perfectly! {zoom_percentage:.1f}% is in the optimal range ({OPTIMAL_MIN:.0f}-{OPTIMAL_MAX:.0f}%).")
    elif MIN_MEANINGFUL <= zoom_percentage < OPTIMAL_MIN:
        score = 85
        quality = "good"
        feedback_parts.append(f"\n✓ Zoom configured successfully. {zoom_percentage:.1f}% is acceptable, though slightly below optimal.")
    elif OPTIMAL_MAX < zoom_percentage <= 175.0:
        score = 90
        quality = "good"
        feedback_parts.append(f"\n✓ Zoom configured successfully. {zoom_percentage:.1f}% is higher than typical but acceptable.")
    elif 175.0 < zoom_percentage <= MAX_REASONABLE:
        score = 75
        quality = "acceptable"
        feedback_parts.append(f"\n✓ Zoom configured, but {zoom_percentage:.1f}% is quite high. Still within acceptable limits.")
    else:
        score = 75
        quality = "acceptable"
        feedback_parts.append(f"\n✓ Zoom configured successfully at {zoom_percentage:.1f}%.")
    
    feedback_parts.append(f"\n✓ Configuration quality: {quality.upper()}")
    feedback_parts.append(f"✓ Score: {score}/100")
    
    return {
        "passed": True,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": zoom_info
    }
