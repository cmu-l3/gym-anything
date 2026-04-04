#!/usr/bin/env python3
"""
Verifier for Chrome Page Rendering Debug Task (page_rendering_debug@1)

Task: Diagnose and fix CSS rendering issue using DevTools and cache clearing

Verification Strategy:
1. Compare final screenshot with reference (working) screenshot using SSIM
2. Check if rendering improved compared to initial broken state
3. Verify CSS file was recently accessed (indicates reload happened)
4. Check Chrome preferences for DevTools usage indicators
5. Validate final page state matches expected rendering

Scoring:
- 5 criteria total, need 4+ to pass (80%+ score)
- Pass threshold: 75%
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

# Try to import image processing libraries
try:
    from PIL import Image
    import numpy as np
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL not available, image comparison will be limited")

try:
    from skimage.metrics import structural_similarity as ssim
    HAS_SKIMAGE = True
except ImportError:
    HAS_SKIMAGE = False
    logger.warning("scikit-image not available, will use basic image comparison")

# Add Chrome utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for page_rendering_debug@1 task.
    
    Verifies that the agent:
    1. Successfully fixed the rendering issue
    2. Used appropriate diagnostic tools
    3. Applied correct fix (cache clearing)
    
    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    try:
        # Copy verification files from container
        logger.info("Retrieving verification files from container...")
        verify_files = copy_verification_files(copy_from_env)
        
        if not verify_files:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve verification files from container"
            }
        
        # Perform multi-criteria verification
        result = perform_verification(verify_files)
        
        # Cleanup
        cleanup_temp_files(verify_files)
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def copy_verification_files(copy_from_env) -> Dict[str, str]:
    """
    Copy all necessary verification files from container.
    
    Returns:
        Dict mapping file types to local temporary paths
    """
    files = {}
    temp_dir = Path(tempfile.mkdtemp(prefix="chrome_debug_verify_"))
    
    file_mappings = {
        'screenshot_final': '/tmp/screenshot_final.png',
        'screenshot_broken': '/tmp/screenshot_broken_initial.png',
        'screenshot_reference': '/tmp/screenshot_correct_reference.png',
        'preferences': '/tmp/chrome_preferences.json',
        'cdp_tabs': '/tmp/chrome_tabs.json',
        'css_stat': '/tmp/css_file_stat.txt',
        'cache_info': '/tmp/cache_info.txt',
        'devtools_state': '/tmp/devtools_state.txt',
    }
    
    for file_type, container_path in file_mappings.items():
        try:
            local_path = temp_dir / f"{file_type}.tmp"
            copy_from_env(container_path, str(local_path))
            
            if local_path.exists() and local_path.stat().st_size > 0:
                files[file_type] = str(local_path)
                logger.info(f"✓ Copied {file_type}")
            else:
                logger.warning(f"⚠ {file_type} is empty or not found")
        except Exception as e:
            logger.warning(f"Could not copy {file_type}: {e}")
    
    files['temp_dir'] = str(temp_dir)
    return files


def perform_verification(files: Dict[str, str]) -> Dict[str, Any]:
    """
    Perform multi-criteria verification of the debugging task.
    
    Returns:
        Verification result with passed, score, and feedback
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Page rendering improved (screenshot comparison)
    logger.info("Checking if page rendering improved...")
    rendering_ok, rendering_score, rendering_feedback = check_rendering_improvement(files)
    
    if rendering_ok:
        criteria_met += 1
        feedback_parts.append(f"✓ {rendering_feedback}")
    else:
        feedback_parts.append(f"✗ {rendering_feedback}")
    
    # Criterion 2: Final rendering matches reference (page is actually fixed)
    logger.info("Checking if final rendering matches reference...")
    matches_reference, match_score, match_feedback = check_matches_reference(files)
    
    if matches_reference:
        criteria_met += 1
        feedback_parts.append(f"✓ {match_feedback}")
    else:
        feedback_parts.append(f"✗ {match_feedback}")
    
    # Criterion 3: CSS file was accessed (indicates reload occurred)
    logger.info("Checking if CSS file was reloaded...")
    css_accessed, css_feedback = check_css_access(files)
    
    if css_accessed:
        criteria_met += 1
        feedback_parts.append(f"✓ {css_feedback}")
    else:
        feedback_parts.append(f"✗ {css_feedback}")
    
    # Criterion 4: Evidence of cache clearing or hard reload
    logger.info("Checking for cache clearing evidence...")
    cache_cleared, cache_feedback = check_cache_cleared(files)
    
    if cache_cleared:
        criteria_met += 1
        feedback_parts.append(f"✓ {cache_feedback}")
    else:
        feedback_parts.append(f"⚠ {cache_feedback}")
        # Give partial credit if rendering is fixed (might have used different method)
        if matches_reference:
            criteria_met += 0.5
            feedback_parts[-1] = f"⚠ {cache_feedback} (but rendering fixed, partial credit)"
    
    # Criterion 5: DevTools usage detected
    logger.info("Checking for DevTools usage...")
    devtools_used, devtools_feedback = check_devtools_usage(files)
    
    if devtools_used:
        criteria_met += 1
        feedback_parts.append(f"✓ {devtools_feedback}")
    else:
        feedback_parts.append(f"⚠ {devtools_feedback}")
        # Give partial credit if problem was solved
        if matches_reference:
            criteria_met += 0.3
            feedback_parts[-1] = f"⚠ {devtools_feedback} (partial credit for solving issue)"
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'✅ PASSED' if passed else '❌ FAILED'}"
    
    if not HAS_PIL or not HAS_SKIMAGE:
        feedback += "\n\n⚠ Note: Image comparison libraries not fully available, verification may be limited"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "rendering_improved": rendering_ok,
            "matches_reference": matches_reference,
            "css_accessed": css_accessed,
            "cache_cleared": cache_cleared,
            "devtools_used": devtools_used
        }
    }


def check_rendering_improvement(files: Dict[str, str]) -> Tuple[bool, float, str]:
    """
    Check if rendering improved from broken to final state.
    """
    if not HAS_PIL:
        return None, 0, "Image comparison not available (PIL missing)"
    
    try:
        broken_img_path = files.get('screenshot_broken')
        final_img_path = files.get('screenshot_final')
        reference_img_path = files.get('screenshot_reference')
        
        if not all([broken_img_path, final_img_path, reference_img_path]):
            return False, 0, "Missing screenshot files"
        
        broken_img = Image.open(broken_img_path).convert('RGB')
        final_img = Image.open(final_img_path).convert('RGB')
        reference_img = Image.open(reference_img_path).convert('RGB')
        
        # Resize if needed to match dimensions
        if broken_img.size != final_img.size:
            final_img = final_img.resize(broken_img.size, Image.LANCZOS)
        if reference_img.size != broken_img.size:
            reference_img = reference_img.resize(broken_img.size, Image.LANCZOS)
        
        if HAS_SKIMAGE:
            # Use SSIM for comparison
            broken_arr = np.array(broken_img)
            final_arr = np.array(final_img)
            reference_arr = np.array(reference_img)
            
            # Compare final to reference
            final_vs_ref_ssim = ssim(final_arr, reference_arr, channel_axis=2, data_range=255)
            
            # Compare broken to reference (should be lower)
            broken_vs_ref_ssim = ssim(broken_arr, reference_arr, channel_axis=2, data_range=255)
            
            improvement = final_vs_ref_ssim - broken_vs_ref_ssim
            
            logger.info(f"SSIM scores - Broken: {broken_vs_ref_ssim:.3f}, Final: {final_vs_ref_ssim:.3f}, Improvement: {improvement:.3f}")
            
            if final_vs_ref_ssim >= 0.75:
                return True, final_vs_ref_ssim, f"Rendering significantly improved (SSIM: {final_vs_ref_ssim:.2f})"
            elif improvement > 0.1:
                return True, improvement, f"Rendering improved (SSIM gain: +{improvement:.2f})"
            else:
                return False, final_vs_ref_ssim, f"Rendering not significantly improved (SSIM: {final_vs_ref_ssim:.2f})"
        else:
            # Fallback: simple pixel difference
            broken_arr = np.array(broken_img)
            final_arr = np.array(final_img)
            reference_arr = np.array(reference_img)
            
            final_diff = np.mean(np.abs(final_arr.astype(float) - reference_arr.astype(float)))
            broken_diff = np.mean(np.abs(broken_arr.astype(float) - reference_arr.astype(float)))
            
            improvement_pct = ((broken_diff - final_diff) / broken_diff) * 100 if broken_diff > 0 else 0
            
            if final_diff < 30 or improvement_pct > 30:
                return True, improvement_pct, f"Rendering improved ({improvement_pct:.1f}% better)"
            else:
                return False, improvement_pct, f"Insufficient improvement ({improvement_pct:.1f}%)"
                
    except Exception as e:
        logger.error(f"Error checking rendering improvement: {e}")
        return False, 0, f"Could not compare screenshots: {str(e)}"


def check_matches_reference(files: Dict[str, str]) -> Tuple[bool, float, str]:
    """
    Check if final rendering closely matches the reference (correctly rendered) page.
    """
    if not HAS_PIL:
        return None, 0, "Image comparison not available"
    
    try:
        final_img_path = files.get('screenshot_final')
        reference_img_path = files.get('screenshot_reference')
        
        if not all([final_img_path, reference_img_path]):
            return False, 0, "Missing screenshot files"
        
        final_img = Image.open(final_img_path).convert('RGB')
        reference_img = Image.open(reference_img_path).convert('RGB')
        
        if reference_img.size != final_img.size:
            reference_img = reference_img.resize(final_img.size, Image.LANCZOS)
        
        if HAS_SKIMAGE:
            final_arr = np.array(final_img)
            reference_arr = np.array(reference_img)
            
            similarity = ssim(final_arr, reference_arr, channel_axis=2, data_range=255)
            
            logger.info(f"Final vs Reference SSIM: {similarity:.3f}")
            
            if similarity >= 0.80:
                return True, similarity, f"Page correctly rendered (similarity: {similarity:.2f})"
            elif similarity >= 0.65:
                return False, similarity, f"Page partially rendered (similarity: {similarity:.2f}, need 0.80+)"
            else:
                return False, similarity, f"Page still broken (similarity: {similarity:.2f})"
        else:
            # Fallback method
            final_arr = np.array(final_img)
            reference_arr = np.array(reference_img)
            
            diff = np.mean(np.abs(final_arr.astype(float) - reference_arr.astype(float)))
            
            if diff < 25:
                return True, 100 - diff, "Page rendering matches reference"
            else:
                return False, 100 - diff, f"Page rendering differs from reference (diff: {diff:.1f})"
                
    except Exception as e:
        logger.error(f"Error comparing with reference: {e}")
        return False, 0, f"Could not compare with reference: {str(e)}"


def check_css_access(files: Dict[str, str]) -> Tuple[bool, str]:
    """
    Check if CSS file was accessed recently (indicates reload).
    """
    try:
        css_stat_path = files.get('css_stat')
        if not css_stat_path or not os.path.exists(css_stat_path):
            return False, "CSS access information not available"
        
        with open(css_stat_path, 'r') as f:
            stat_content = f.read()
        
        # Look for access time info
        if 'css_accessed_seconds_ago=' in stat_content:
            for line in stat_content.split('\n'):
                if 'css_accessed_seconds_ago=' in line:
                    seconds_ago = int(line.split('=')[1])
                    
                    # If accessed within last 3 minutes, consider it reloaded
                    if seconds_ago < 180:
                        return True, f"CSS file accessed recently ({seconds_ago}s ago)"
                    else:
                        return False, f"CSS file not accessed recently (last access {seconds_ago}s ago)"
        
        # If we have stat info but no recent access marker, consider it not accessed
        return False, "CSS file access time not recent"
        
    except Exception as e:
        logger.warning(f"Could not check CSS access: {e}")
        return False, f"Could not verify CSS access: {str(e)}"


def check_cache_cleared(files: Dict[str, str]) -> Tuple[bool, str]:
    """
    Check for evidence of cache clearing.
    """
    try:
        # Check preferences for cache disabled setting
        prefs_path = files.get('preferences')
        if prefs_path and os.path.exists(prefs_path):
            with open(prefs_path, 'r') as f:
                prefs = json.load(f)
            
            # Check if cache was disabled in DevTools
            devtools_prefs = prefs.get('devtools', {}).get('preferences', {})
            cache_disabled = devtools_prefs.get('cacheDisabled', 'false') == 'true'
            
            if cache_disabled:
                return True, "Cache disabled setting detected in DevTools"
        
        # Check cache info
        cache_info_path = files.get('cache_info')
        if cache_info_path and os.path.exists(cache_info_path):
            with open(cache_info_path, 'r') as f:
                cache_info = f.read()
            
            if 'cache_size_bytes=' in cache_info:
                size = int(cache_info.split('=')[1])
                # Very small cache might indicate clearing (though not definitive)
                if size < 100000:  # Less than 100KB
                    return True, "Cache appears to be cleared or minimal"
        
        # If CSS was accessed AND rendering is fixed, assume cache was cleared
        css_accessed, _ = check_css_access(files)
        if css_accessed:
            return True, "Indirect evidence: CSS reloaded successfully"
        
        return False, "No clear evidence of cache clearing detected"
        
    except Exception as e:
        logger.warning(f"Could not check cache state: {e}")
        return False, "Could not verify cache clearing"


def check_devtools_usage(files: Dict[str, str]) -> Tuple[bool, str]:
    """
    Check if DevTools was used during the task.
    """
    try:
        # Check devtools_state file
        devtools_state_path = files.get('devtools_state')
        if devtools_state_path and os.path.exists(devtools_state_path):
            with open(devtools_state_path, 'r') as f:
                state = f.read()
            
            if 'devtools_tabs=' in state:
                devtools_count = int(state.split('=')[1])
                if devtools_count > 0:
                    return True, f"DevTools tab detected ({devtools_count} instance(s))"
        
        # Check preferences for DevTools usage indicators
        prefs_path = files.get('preferences')
        if prefs_path and os.path.exists(prefs_path):
            with open(prefs_path, 'r') as f:
                prefs = json.load(f)
            
            # Check if devtools has been opened
            devtools_prefs = prefs.get('devtools', {})
            if devtools_prefs:
                return True, "DevTools preferences found (indicates usage)"
        
        return False, "No evidence of DevTools usage"
        
    except Exception as e:
        logger.warning(f"Could not check DevTools usage: {e}")
        return False, "Could not verify DevTools usage"


def cleanup_temp_files(files: Dict[str, str]):
    """Clean up temporary verification files."""
    temp_dir = files.get('temp_dir')
    if temp_dir and os.path.exists(temp_dir):
        try:
            import shutil
            shutil.rmtree(temp_dir)
            logger.info("Cleaned up temporary files")
        except Exception as e:
            logger.warning(f"Could not clean up temp dir: {e}")
