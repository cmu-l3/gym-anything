#!/usr/bin/env python3
"""
Verifier for Chrome Site-Specific Zoom Configuration Task (site_specific_zoom@1)
Task: Configure different zoom levels for three different websites

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract profile.per_host_zoom_levels
- Check for all three target domains with correct zoom multipliers
- Validate zoom values are within acceptable tolerance (±0.05)
- Calculate score based on number of correctly configured sites
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
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
    
    def parse_preferences(path):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for site_specific_zoom@1 task.
    
    Verifies that three websites have different zoom levels configured:
    - example.com: 150% (1.5)
    - info.cern.ch: 75% (0.75)
    - textfiles.com: 125% (1.25)
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    # Expected zoom configuration
    expected_zooms = {
        "example.com": 1.5,      # 150%
        "info.cern.ch": 0.75,    # 75%
        "textfiles.com": 1.25    # 125%
    }

    try:
        # Extract zoom settings from Preferences
        zoom_levels, error_msg = extract_zoom_settings(copy_from_env)
        
        if zoom_levels is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract zoom settings: {error_msg}"
            }
        
        # Verify zoom configuration
        verification_result = verify_zoom_configuration(zoom_levels, expected_zooms)
        
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


def extract_zoom_settings(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract per-site zoom settings from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (zoom_levels_dict or None, error_message)
    """
    temp_file = None
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
            logger.info("Attempting to use chrome_verification_utils...")
            success, files, error = setup_chrome_verification(
                copy_from_env,
                ["Preferences"],
                user="ga",
                profile="Default"
            )
            
            if success:
                prefs_path = files["Preferences"]
                prefs = parse_preferences(prefs_path)
                zoom_levels = prefs.get('profile', {}).get('per_host_zoom_levels', {})
                cleanup_verification_temp()
                
                logger.info(f"Successfully extracted zoom levels using utils: {zoom_levels}")
                return zoom_levels, ""
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
        
        # Fallback: Manual extraction
        logger.info("Using fallback method to extract Preferences...")
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try to copy from /tmp first (where export script puts it)
        copy_success = False
        for container_path in [
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied and has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    logger.info(f"✓ Successfully copied from: {container_path}")
                    copy_success = True
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not copy_success:
            return None, "Could not copy Preferences file from any known location"
        
        # Parse JSON
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            prefs = json.load(f)
        
        # Extract per-site zoom levels
        zoom_levels = prefs.get('profile', {}).get('per_host_zoom_levels', {})
        
        logger.info(f"Extracted per-site zoom levels: {zoom_levels}")
        
        return zoom_levels, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting zoom settings: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def normalize_domain(domain: str) -> str:
    """
    Normalize domain string for comparison.
    Chrome may store domains with port numbers (e.g., "example.com:80")
    
    Args:
        domain: Domain string from Preferences
        
    Returns:
        Normalized domain (lowercase, without port)
    """
    domain = domain.lower()
    # Remove port if present
    if ':' in domain:
        domain = domain.split(':')[0]
    return domain


def find_zoom_for_domain(zoom_levels: Dict[str, float], target_domain: str) -> Optional[float]:
    """
    Find zoom level for a target domain in the zoom_levels dict.
    Handles domain variations (with/without port, etc.)
    
    Args:
        zoom_levels: Dict mapping domain strings to zoom multipliers
        target_domain: Target domain to search for (e.g., "example.com")
        
    Returns:
        Zoom multiplier if found, None otherwise
    """
    target_normalized = normalize_domain(target_domain)
    
    for stored_domain, zoom_value in zoom_levels.items():
        stored_normalized = normalize_domain(stored_domain)
        
        # Check for exact match or if target is contained in stored domain
        if target_normalized == stored_normalized or target_normalized in stored_normalized:
            return zoom_value
    
    return None


def verify_zoom_configuration(zoom_levels: Dict[str, float], 
                              expected_zooms: Dict[str, float],
                              tolerance: float = 0.05) -> Dict[str, Any]:
    """
    Verify that zoom levels match expected configuration.
    
    Args:
        zoom_levels: Actual zoom levels from Preferences
        expected_zooms: Expected zoom configuration
        tolerance: Acceptable difference in zoom values (default ±0.05)
        
    Returns:
        Verification result dict with passed, score, feedback, and details
    """
    if not zoom_levels:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No per-site zoom levels configured. Please set zoom levels for the three websites.",
            "details": {
                "configured_sites": 0,
                "correct_sites": 0,
                "total_expected": len(expected_zooms),
                "zoom_levels": {}
            }
        }
    
    # Check each expected domain
    matches = 0
    details_list = []
    site_results = {}
    
    for domain, expected_zoom in expected_zooms.items():
        actual_zoom = find_zoom_for_domain(zoom_levels, domain)
        
        if actual_zoom is None:
            details_list.append(f"✗ {domain}: NOT CONFIGURED")
            site_results[domain] = {"configured": False, "correct": False}
        else:
            # Check if zoom value is within tolerance
            zoom_diff = abs(actual_zoom - expected_zoom)
            is_correct = zoom_diff <= tolerance
            
            if is_correct:
                details_list.append(
                    f"✓ {domain}: {int(actual_zoom * 100)}% "
                    f"(expected {int(expected_zoom * 100)}%)"
                )
                matches += 1
                site_results[domain] = {
                    "configured": True, 
                    "correct": True,
                    "actual": actual_zoom,
                    "expected": expected_zoom
                }
            else:
                details_list.append(
                    f"✗ {domain}: {int(actual_zoom * 100)}% "
                    f"(expected {int(expected_zoom * 100)}%, difference: {zoom_diff:.2f})"
                )
                site_results[domain] = {
                    "configured": True,
                    "correct": False,
                    "actual": actual_zoom,
                    "expected": expected_zoom
                }
    
    # Calculate score
    total_sites = len(expected_zooms)
    score = int((matches / total_sites) * 100)
    passed = matches >= 2  # Pass if at least 2/3 sites are correct (≥75%)
    
    # Generate feedback
    feedback_lines = [
        f"Per-site zoom configuration verification: {matches}/{total_sites} sites correct",
        ""
    ]
    feedback_lines.extend(details_list)
    feedback_lines.append("")
    
    if matches == total_sites:
        feedback_lines.append("✅ Perfect! All sites have correct zoom levels configured.")
    elif matches >= 2:
        feedback_lines.append("✅ Task passed with correct zoom configuration for most sites.")
    elif matches == 1:
        feedback_lines.append("⚠ Only one site configured correctly. Please check zoom settings.")
    else:
        feedback_lines.append("❌ Task failed. Please configure zoom levels for all three websites.")
    
    # Add helpful information
    if matches < total_sites:
        feedback_lines.append("")
        feedback_lines.append("Expected zoom levels:")
        for domain, zoom in expected_zooms.items():
            feedback_lines.append(f"  - {domain}: {int(zoom * 100)}%")
    
    feedback = "\n".join(feedback_lines)
    
    logger.info(f"Verification complete: {matches}/{total_sites} correct, score={score}%, passed={passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "configured_sites": len(zoom_levels),
            "correct_sites": matches,
            "total_expected": total_sites,
            "site_results": site_results,
            "zoom_levels": zoom_levels
        }
    }
