#!/usr/bin/env python3
"""
Verifier for Chrome Extension Installation Task (install_extension@1)
Task: Install an ad-blocking extension from Chrome Web Store

Verification Strategy:
- Compare extensions before and after task execution
- Parse manifest.json files to identify extension details
- Detect ad blocker extensions using multiple signals:
  * Known extension IDs (uBlock Origin, AdBlock, etc.)
  * Keywords in name/description
  * Permission patterns typical of ad blockers
- Validate that at least one new ad blocker was installed
"""

import logging
import sys
import os
import json
import tempfile
import shutil
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Known ad blocker extension IDs (common ones)
KNOWN_AD_BLOCKERS = {
    'cjpalhdlnbpafiamejdnhcphjbkeiagm': 'uBlock Origin',
    'gighmmpiobklfepjocnamgkkbiglidom': 'AdBlock',
    'cfhdojbkjhnklbpkdaibdccddilifddb': 'Adblock Plus',
    'bhmmomiinigofkjcapegjjndpbikblnp': 'Ghostery',
    'epcnnfbjfcgphgdmggkamkmgojdagdnn': 'Adguard AdBlocker',
    'bkdgflcldnnnapblkhphbgpggdiikppg': 'DuckDuckGo Privacy Essentials',
}


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for install_extension@1.
    
    Verifies that an ad-blocking extension was successfully installed.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get baseline and final extension lists
        baseline_extensions = get_extension_ids(copy_from_env, "/tmp/baseline_extensions.txt")
        final_extensions = get_extension_ids(copy_from_env, "/tmp/final_extensions.txt")
        
        logger.info(f"Baseline extensions: {len(baseline_extensions)}")
        logger.info(f"Final extensions: {len(final_extensions)}")
        
        # Find new extensions
        new_extension_ids = final_extensions - baseline_extensions
        
        if not new_extension_ids:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new extensions installed. Please navigate to Chrome Web Store and install an ad blocker.",
                "details": {
                    "baseline_count": len(baseline_extensions),
                    "final_count": len(final_extensions),
                    "new_extensions": 0
                }
            }
        
        logger.info(f"New extensions detected: {new_extension_ids}")
        
        # Get Chrome profile path
        chrome_profile = get_chrome_profile_path(copy_from_env)
        
        # Analyze new extensions to find ad blockers
        new_extensions_info = []
        for ext_id in new_extension_ids:
            ext_info = get_extension_info(copy_from_env, chrome_profile, ext_id)
            if ext_info:
                new_extensions_info.append(ext_info)
        
        if not new_extensions_info:
            return {
                "passed": False,
                "score": 25,
                "feedback": f"Extension(s) installed but could not read manifest data. Extension IDs: {', '.join(new_extension_ids)}",
                "details": {
                    "new_extension_ids": list(new_extension_ids),
                    "manifest_read_failed": True
                }
            }
        
        # Check if any new extension is an ad blocker
        ad_blocker_found = False
        ad_blocker_info = None
        
        for ext_info in new_extensions_info:
            if is_ad_blocker(ext_info):
                ad_blocker_found = True
                ad_blocker_info = ext_info
                break
        
        # Generate verification result
        if ad_blocker_found:
            score = 100
            passed = True
            feedback = (
                f"✅ Successfully installed ad-blocking extension!\n"
                f"Extension: {ad_blocker_info['name']}\n"
                f"ID: {ad_blocker_info['id']}\n"
                f"Version: {ad_blocker_info['version']}\n"
                f"Description: {ad_blocker_info['description'][:100]}..."
            )
        else:
            # Extension installed but not an ad blocker
            score = 50
            passed = False
            ext_info = new_extensions_info[0]
            feedback = (
                f"Extension installed, but it doesn't appear to be an ad blocker.\n"
                f"Installed: {ext_info['name']} (ID: {ext_info['id']})\n"
                f"Please install an ad-blocking extension like uBlock Origin, AdBlock, or Adblock Plus."
            )
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "baseline_count": len(baseline_extensions),
                "final_count": len(final_extensions),
                "new_extensions": len(new_extension_ids),
                "ad_blocker_found": ad_blocker_found,
                "installed_extensions": [ext['name'] for ext in new_extensions_info]
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_verification_temp()


def get_extension_ids(copy_from_env, file_path: str) -> set:
    """
    Get set of extension IDs from a list file.
    
    Args:
        copy_from_env: Function to copy files from container
        file_path: Path to file containing extension IDs (one per line)
        
    Returns:
        Set of extension ID strings
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, mode='w+', suffix='.txt')
        temp_file.close()
        
        copy_from_env(file_path, temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            extension_ids = set(line.strip() for line in f if line.strip())
        
        os.unlink(temp_file.name)
        return extension_ids
        
    except Exception as e:
        logger.warning(f"Could not read {file_path}: {e}")
        return set()


def get_chrome_profile_path(copy_from_env) -> str:
    """
    Get Chrome profile path from container.
    
    Returns:
        Chrome profile path string
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, mode='w+', suffix='.txt')
        temp_file.close()
        
        copy_from_env("/tmp/chrome_profile_path.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            profile_path = f.read().strip()
        
        os.unlink(temp_file.name)
        return profile_path
        
    except Exception as e:
        logger.warning(f"Could not read Chrome profile path: {e}, using default")
        return "/home/ga/.config/google-chrome/Default"


def get_extension_info(copy_from_env, chrome_profile: str, extension_id: str) -> Optional[Dict[str, Any]]:
    """
    Get extension information by reading its manifest.json.
    
    Args:
        copy_from_env: Function to copy files from container
        chrome_profile: Chrome profile directory path
        extension_id: Extension ID string
        
    Returns:
        Dict with extension info or None if failed
    """
    try:
        extensions_dir = f"{chrome_profile}/Extensions/{extension_id}"
        
        # Extensions can have multiple versions, find the latest
        # First, try to list versions
        temp_dir = tempfile.mkdtemp(prefix='ext_verify_')
        
        try:
            # Try to copy the entire extension directory
            copy_from_env(extensions_dir, temp_dir)
            
            # Find manifest.json (may be in version subdirectory)
            manifest_paths = list(Path(temp_dir).rglob('manifest.json'))
            
            if not manifest_paths:
                logger.warning(f"No manifest.json found for extension {extension_id}")
                return None
            
            # Use the first manifest found (usually the latest version)
            manifest_path = manifest_paths[0]
            
            with open(manifest_path, 'r', encoding='utf-8') as f:
                manifest = json.load(f)
            
            # Extract key information
            extension_info = {
                'id': extension_id,
                'name': manifest.get('name', '').replace('__MSG_', '').replace('__', ''),
                'version': manifest.get('version', ''),
                'description': manifest.get('description', '').replace('__MSG_', '').replace('__', ''),
                'permissions': manifest.get('permissions', []),
                'manifest': manifest
            }
            
            logger.info(f"Loaded extension info: {extension_info['name']} v{extension_info['version']}")
            return extension_info
            
        finally:
            # Cleanup temp directory
            shutil.rmtree(temp_dir, ignore_errors=True)
            
    except Exception as e:
        logger.error(f"Error getting extension info for {extension_id}: {e}")
        return None


def is_ad_blocker(extension_info: Dict[str, Any]) -> bool:
    """
    Determine if an extension is an ad blocker using multiple signals.
    
    Args:
        extension_info: Extension information dict
        
    Returns:
        True if extension appears to be an ad blocker
    """
    ext_id = extension_info['id']
    name = extension_info['name'].lower()
    description = extension_info['description'].lower()
    permissions = extension_info.get('permissions', [])
    
    # Check 1: Known ad blocker extension IDs
    if ext_id in KNOWN_AD_BLOCKERS:
        logger.info(f"✓ Extension {ext_id} identified as known ad blocker: {KNOWN_AD_BLOCKERS[ext_id]}")
        return True
    
    # Check 2: Keywords in name or description
    ad_block_keywords = [
        'ad block', 'adblock', 'ad-block', 'adblocker', 'ad blocker',
        'advertisement block', 'popup block', 'anti-ad',
        'ublock', 'adguard', 'ghostery',
        'privacy badger', 'disconnect'
    ]
    
    text_to_check = name + ' ' + description
    for keyword in ad_block_keywords:
        if keyword in text_to_check:
            logger.info(f"✓ Extension matched keyword '{keyword}' in name/description")
            return True
    
    # Check 3: Permission patterns typical of ad blockers
    # Ad blockers typically need:
    # - webRequest / webRequestBlocking (to intercept and block requests)
    # - <all_urls> or broad URL permissions (to work on all sites)
    # - tabs (to manage tabs)
    # - storage (to save settings)
    
    has_webrequest = any('webRequest' in str(p) for p in permissions)
    has_broad_urls = any(
        '<all_urls>' in str(p) or 
        '*://*/*' in str(p) or
        'http://*/*' in str(p) or
        'https://*/*' in str(p)
        for p in permissions
    )
    
    # Also check host_permissions in manifest v3
    manifest = extension_info.get('manifest', {})
    host_permissions = manifest.get('host_permissions', [])
    if host_permissions:
        has_broad_urls = has_broad_urls or any(
            '<all_urls>' in str(p) or '*://*/*' in str(p)
            for p in host_permissions
        )
    
    if has_webrequest and has_broad_urls:
        # Additional check: does name/description mention blocking or filtering?
        if any(word in text_to_check for word in ['block', 'filter', 'protect', 'privacy']):
            logger.info("✓ Extension has ad blocker permission pattern (webRequest + broad URLs + blocking keywords)")
            return True
    
    logger.info(f"Extension '{extension_info['name']}' does not match ad blocker criteria")
    return False
