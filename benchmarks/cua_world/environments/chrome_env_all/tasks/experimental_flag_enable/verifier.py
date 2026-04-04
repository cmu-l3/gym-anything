#!/usr/bin/env python3
"""
Verifier for Chrome Experimental Flag Configuration Task (experimental_flag_enable@1)
Task: Enable 'Parallel downloading' experimental feature via chrome://flags

Verification Strategy:
- Copy Chrome's Local State file from container
- Parse JSON structure to extract browser.enabled_labs_experiments array
- Check if target flag is present in the enabled experiments list
- Handle various flag name formats and variations
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for experimental_flag_enable@1.
    
    Verifies that the specified experimental flag has been enabled in Chrome.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information with target flag metadata
        
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

    # Get target flag from task metadata
    target_flag = "enable-parallel-downloading"  # Default if not in metadata
    if task_info and 'metadata' in task_info:
        target_flag = task_info['metadata'].get('target_flag_internal', target_flag)
    
    logger.info(f"Verifying experimental flag: {target_flag}")

    try:
        # Extract enabled experiments from Local State
        experiments, error_msg = extract_enabled_experiments(copy_from_env)
        
        if experiments is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Local State: {error_msg}"
            }
        
        # Validate flag is enabled
        is_enabled, score, feedback = validate_flag_enabled(
            target_flag, 
            experiments
        )
        
        cleanup_verification_temp()
        
        return {
            "passed": is_enabled,
            "score": score,
            "feedback": feedback,
            "details": {
                "target_flag": target_flag,
                "experiments_count": len(experiments),
                "enabled_experiments": experiments
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


def extract_enabled_experiments(copy_from_env) -> Tuple[Optional[List[str]], str]:
    """
    Extract enabled experiments list from Chrome's Local State file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (experiments_list: List[str] or None, error_message: str)
    """
    temp_file = None
    try:
        # Create temporary file for Local State
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        local_state_paths = [
            "/tmp/local_state_export.json",
            "/home/ga/.config/google-chrome-cdp/Local State",
            "/home/ga/.config/google-chrome/Local State"
        ]
        
        local_state_data = None
        source_path = None
        
        for container_path in local_state_paths:
            try:
                logger.info(f"Trying to copy Local State from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 10:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        local_state_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully loaded Local State from: {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not local_state_data:
            return None, "Could not access Local State file from any known location"
        
        # Navigate to enabled_labs_experiments array
        browser_section = local_state_data.get('browser', {})
        experiments = browser_section.get('enabled_labs_experiments', [])
        
        logger.info(f"Found {len(experiments)} enabled experiment(s)")
        for exp in experiments:
            logger.info(f"  - {exp}")
        
        return experiments, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Local State JSON: {e}"
    except Exception as e:
        return None, f"Error extracting experiments: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def validate_flag_enabled(target_flag: str, experiments: List[str]) -> Tuple[bool, int, str]:
    """
    Validate that the target experimental flag is in the enabled list.
    
    Args:
        target_flag: Internal flag name (e.g., "enable-parallel-downloading")
        experiments: List of enabled experiment strings from Local State
        
    Returns:
        Tuple of (is_enabled: bool, score: int, feedback: str)
    """
    if not experiments:
        return False, 0, "No experimental flags are enabled. Please navigate to chrome://flags and enable the 'Parallel downloading' flag."
    
    # Generate possible flag name variations
    # Chrome flags can appear in various formats in Local State:
    # - "enable-parallel-downloading"
    # - "enable-parallel-downloading@1"
    # - "parallel-downloading"
    # - etc.
    flag_variants = generate_flag_variants(target_flag)
    
    logger.info(f"Checking for flag variants: {flag_variants}")
    
    # Check if any variant is in the experiments list
    found_flag = None
    for exp in experiments:
        exp_lower = exp.lower()
        for variant in flag_variants:
            if variant.lower() in exp_lower or exp_lower in variant.lower():
                found_flag = exp
                break
        if found_flag:
            break
    
    if found_flag:
        return True, 100, f"✓ Experimental flag successfully enabled: '{found_flag}'\nParallel downloading is now active in Chrome."
    else:
        # Flag not found, but check if something related was enabled
        partial_matches = []
        for exp in experiments:
            if any(keyword in exp.lower() for keyword in ['parallel', 'download']):
                partial_matches.append(exp)
        
        if partial_matches:
            return False, 50, f"Found related flags enabled: {partial_matches}\nHowever, the specific 'Parallel downloading' flag was not detected."
        else:
            return False, 0, f"Target flag '{target_flag}' not found in enabled experiments.\nEnabled flags: {experiments if len(experiments) <= 5 else f'{experiments[:5]} (showing first 5 of {len(experiments)})'}"


def generate_flag_variants(base_flag: str) -> List[str]:
    """
    Generate possible variations of a flag name as it might appear in Local State.
    
    Args:
        base_flag: Base flag name (e.g., "enable-parallel-downloading")
        
    Returns:
        List of possible flag name variations
    """
    variants = [base_flag]
    
    # Add version suffixes
    variants.append(f"{base_flag}@1")
    variants.append(f"{base_flag}@2")
    
    # Try without "enable-" prefix if present
    if base_flag.startswith("enable-"):
        without_enable = base_flag[7:]  # Remove "enable-"
        variants.append(without_enable)
        variants.append(f"{without_enable}@1")
    
    # Try with "enable-" prefix if not present
    if not base_flag.startswith("enable-"):
        with_enable = f"enable-{base_flag}"
        variants.append(with_enable)
        variants.append(f"{with_enable}@1")
    
    # Normalize separators (hyphens vs underscores)
    if '-' in base_flag:
        underscore_version = base_flag.replace('-', '_')
        variants.append(underscore_version)
    
    if '_' in base_flag:
        hyphen_version = base_flag.replace('_', '-')
        variants.append(hyphen_version)
    
    # Remove duplicates while preserving order
    seen = set()
    unique_variants = []
    for v in variants:
        if v not in seen:
            seen.add(v)
            unique_variants.append(v)
    
    return unique_variants
