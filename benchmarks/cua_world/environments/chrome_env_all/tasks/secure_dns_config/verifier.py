#!/usr/bin/env python3
"""
Verifier for Chrome Secure DNS Configuration Task (secure_dns_config@1)
Task: Configure Chrome's Secure DNS (DNS-over-HTTPS) to use Cloudflare (1.1.1.1)

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract dns_over_https configuration
- Validate that mode is set to "secure" (not "off" or "automatic")
- Verify templates contain Cloudflare provider URLs
- Ensure proper DoH URI template format
- Confirm configuration is persisted to file
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
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
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
    
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for secure_dns_config@1.
    
    Verifies that Chrome's Secure DNS is configured with Cloudflare provider.
    
    Checks:
    1. DNS-over-HTTPS mode is set to "secure" (not "off")
    2. DNS templates contain Cloudflare provider URLs
    3. Configuration is properly formatted (https:// URI templates)
    4. Settings are persisted to Preferences file
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), feedback (str), and optional metrics
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Cannot access environment files - copy_from_env function not available"
        }

    try:
        # Extract DNS configuration from Preferences file
        dns_config, error_msg = extract_dns_config_from_prefs(copy_from_env)
        
        if dns_config is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Chrome Preferences: {error_msg}"
            }
        
        # Validate DNS configuration against Cloudflare requirements
        validation_result = validate_dns_config(dns_config)
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return validation_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_dns_config_from_prefs(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract DNS-over-HTTPS configuration from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (dns_config dict or None, error_message string)
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
                prefs = parse_preferences(files["Preferences"])
                if prefs:
                    dns_config = prefs.get('dns_over_https', {})
                    logger.info(f"Extracted DNS config via utils: {dns_config}")
                    return dns_config, ""
                else:
                    logger.warning("Utility-based parsing returned empty, trying fallback")
        
        # Fallback: Manual extraction
        logger.info("Using fallback method to extract DNS configuration...")
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_locations = [
            "/tmp/chrome_preferences_dns.json",
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences",
            "/home/ga/.config/chromium/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in prefs_locations:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 10:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
                    break
                else:
                    logger.debug(f"File copied but empty or too small")
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs_data:
            return None, "Could not access Chrome Preferences file from any known location"
        
        # Extract DNS-over-HTTPS configuration
        dns_config = prefs_data.get('dns_over_https', {})
        
        if not dns_config:
            logger.warning("No dns_over_https section found in Preferences")
            # Return empty dict rather than None - indicates no config set
            return {}, ""
        
        logger.info(f"Extracted DNS configuration: {dns_config}")
        return dns_config, ""
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse Preferences JSON: {e}")
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        logger.error(f"Error extracting DNS config: {e}", exc_info=True)
        return None, f"Error extracting DNS configuration: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except Exception as e:
                logger.warning(f"Could not delete temp file: {e}")


def validate_dns_config(dns_config: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate DNS-over-HTTPS configuration against task requirements.
    
    Checks 4 criteria:
    1. DNS mode is "secure" (not "off" or "automatic")
    2. DNS templates contain Cloudflare patterns
    3. URI templates are properly formatted (start with https://)
    4. Configuration exists and is persisted
    
    Args:
        dns_config: Dictionary containing dns_over_https configuration
        
    Returns:
        Dict with passed, score, feedback, and metrics
    """
    # Cloudflare DNS-over-HTTPS URL patterns to match
    CLOUDFLARE_PATTERNS = [
        'cloudflare-dns.com',
        '1.1.1.1',
        '1.0.0.1'
    ]
    
    criteria_results = {}
    feedback_parts = []
    
    # Criterion 1: Check if DNS configuration exists
    if not dns_config:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No DNS-over-HTTPS configuration found. Did you enable Secure DNS in Chrome Settings?",
            "metrics": {
                "config_exists": False,
                "mode_secure": False,
                "provider_cloudflare": False,
                "format_valid": False
            }
        }
    
    criteria_results['config_exists'] = True
    
    # Extract configuration values
    mode = dns_config.get('mode', '')
    templates = dns_config.get('templates', '')
    
    logger.info(f"Validating DNS config: mode='{mode}', templates='{templates}'")
    
    # Criterion 2: Check DNS mode is "secure"
    mode_secure = (mode == 'secure')
    criteria_results['mode_secure'] = mode_secure
    
    if mode_secure:
        feedback_parts.append("✓ Secure DNS mode enabled correctly")
    elif mode == 'off':
        feedback_parts.append("✗ Secure DNS is turned OFF (mode: 'off')")
    elif mode == 'automatic':
        feedback_parts.append("✗ DNS mode is 'automatic' instead of 'secure' (custom provider not selected)")
    elif not mode:
        feedback_parts.append("✗ DNS mode not set")
    else:
        feedback_parts.append(f"✗ DNS mode is '{mode}' (expected 'secure')")
    
    # Criterion 3: Check DNS templates contain Cloudflare patterns
    templates_lower = templates.lower() if templates else ''
    provider_cloudflare = any(pattern in templates_lower for pattern in CLOUDFLARE_PATTERNS)
    criteria_results['provider_cloudflare'] = provider_cloudflare
    
    if provider_cloudflare:
        matched_patterns = [p for p in CLOUDFLARE_PATTERNS if p in templates_lower]
        feedback_parts.append(f"✓ Cloudflare DNS provider configured (detected: {', '.join(matched_patterns)})")
    else:
        if templates:
            feedback_parts.append(f"✗ DNS provider is not Cloudflare (templates: {templates[:100]}...)")
        else:
            feedback_parts.append("✗ No DNS templates configured (custom provider not selected)")
    
    # Criterion 4: Check DoH URI format is valid
    format_valid = templates.startswith('https://') if templates else False
    criteria_results['format_valid'] = format_valid
    
    if format_valid:
        feedback_parts.append("✓ DoH URI format is valid (starts with https://)")
    elif templates:
        feedback_parts.append(f"✗ DNS templates format invalid (should start with https://): {templates[:50]}...")
    else:
        feedback_parts.append("✗ No DNS templates found")
    
    # Calculate score based on criteria met
    # All 4 criteria must be true for full marks
    criteria_met = sum([
        criteria_results['config_exists'],
        criteria_results['mode_secure'],
        criteria_results['provider_cloudflare'],
        criteria_results['format_valid']
    ])
    
    score = (criteria_met / 4.0) * 100
    passed = score >= 75  # Need at least 3/4 criteria (75%)
    
    # Generate detailed feedback
    feedback = "DNS Configuration Verification Results:\n"
    feedback += "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}\n"
    feedback += f"Criteria Met: {criteria_met}/4\n"
    feedback += f"Final Score: {int(score)}%\n"
    
    # Add configuration details
    feedback += f"\nDNS Configuration Details:\n"
    feedback += f"  Mode: {mode if mode else 'not set'}\n"
    feedback += f"  Templates: {templates[:100] if templates else 'not set'}{'...' if len(templates) > 100 else ''}\n"
    
    if passed:
        feedback += f"\n✅ Task completed successfully! Chrome is now using Cloudflare's secure DNS."
    else:
        feedback += f"\n❌ Task incomplete - DNS configuration does not meet requirements."
        
        # Provide helpful hints based on what's missing
        if not criteria_results['mode_secure']:
            feedback += "\n\n💡 Hint: Make sure to select 'With custom' or 'Choose another provider' option, not 'Automatic'."
        if not criteria_results['provider_cloudflare']:
            feedback += "\n\n💡 Hint: Select 'Cloudflare (1.1.1.1)' from the DNS provider dropdown menu."
    
    logger.info(f"Verification complete: passed={passed}, score={int(score)}, criteria_met={criteria_met}/4")
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "metrics": {
            "criteria_met": criteria_met,
            "config_exists": criteria_results['config_exists'],
            "mode_secure": criteria_results['mode_secure'],
            "provider_cloudflare": criteria_results['provider_cloudflare'],
            "format_valid": criteria_results['format_valid'],
            "mode": mode,
            "templates": templates
        }
    }
