#!/usr/bin/env python3
"""
Verifier for Fix Aspect Ratio task

Checks if the user correctly set VLC's aspect ratio to 4:3 for a video
with 4:3 content that was displaying incorrectly.
"""

import sys
import os
import logging
import tempfile
import re
from pathlib import Path
from typing import Dict, Any, Tuple

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def parse_vlc_config(config_path: str) -> Dict[str, str]:
    """
    Parse VLC configuration file (vlcrc).
    
    Args:
        config_path: Path to vlcrc file
        
    Returns:
        Dictionary of configuration key-value pairs
    """
    config = {}
    
    try:
        with open(config_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                
                # Skip comments, empty lines, and section headers
                if not line or line.startswith('#') or line.startswith('['):
                    continue
                
                # Parse key=value
                if '=' in line:
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip()
    
    except Exception as e:
        logger.error(f"Error parsing VLC config: {e}")
        return {}
    
    return config


def check_aspect_ratio_setting(config: Dict[str, str]) -> Tuple[bool, str, float]:
    """
    Check if aspect ratio is correctly set to 4:3.
    
    Args:
        config: VLC configuration dictionary
        
    Returns:
        Tuple of (is_correct, feedback_message, confidence_score)
    """
    # VLC stores aspect ratio in the 'aspect-ratio' key
    # Valid values for 4:3: "4:3", "1.33:1", "1.3333:1", or decimal ~1.333
    
    aspect_ratio = config.get('aspect-ratio', '').strip()
    
    if not aspect_ratio:
        return False, "✗ Aspect ratio not set (expected 4:3)", 0.0
    
    # Check exact match for 4:3
    if aspect_ratio == '4:3':
        return True, f"✓ Aspect ratio correctly set to 4:3", 1.0
    
    # Check alternative representations of 4:3
    if aspect_ratio in ['1.33:1', '1.3333:1', '1.333:1']:
        return True, f"✓ Aspect ratio set to {aspect_ratio} (equivalent to 4:3)", 1.0
    
    # Check if it's a ratio format (e.g., "16:9", "4:3")
    if ':' in aspect_ratio:
        try:
            parts = aspect_ratio.split(':')
            if len(parts) == 2:
                ratio = float(parts[0]) / float(parts[1])
                target_ratio = 4.0 / 3.0  # 1.333...
                
                # Allow 5% tolerance
                if abs(ratio - target_ratio) < 0.07:
                    return True, f"✓ Aspect ratio set to {aspect_ratio} (close to 4:3)", 0.9
                else:
                    return False, f"✗ Aspect ratio is {aspect_ratio} (ratio: {ratio:.3f}) but should be 4:3 (ratio: {target_ratio:.3f})", 0.2
        except (ValueError, ZeroDivisionError):
            pass
    
    # Check if it's a decimal value
    try:
        ratio = float(aspect_ratio)
        target_ratio = 4.0 / 3.0
        
        if abs(ratio - target_ratio) < 0.07:
            return True, f"✓ Aspect ratio set to {aspect_ratio} (close to 4:3)", 0.9
        else:
            return False, f"✗ Aspect ratio is {aspect_ratio} but should be ~1.333 (4:3)", 0.2
    except ValueError:
        pass
    
    # If aspect ratio is set but doesn't match
    return False, f"✗ Aspect ratio is set to '{aspect_ratio}' but should be '4:3'", 0.1


def check_vlc_usage(config: Dict[str, str], export_dir: str) -> Tuple[bool, str, float]:
    """
    Check if VLC was actually used to open the video.
    
    Args:
        config: VLC configuration dictionary
        export_dir: Path to export directory
        
    Returns:
        Tuple of (was_used, feedback_message, confidence_score)
    """
    # Check for recent files list (indicates video was opened)
    recent_indicators = [
        'recent-media',
        'file-caching',
        'last-played',
        'qt-recentplay',
    ]
    
    # Check if our target video appears in any recent file entries
    for key, value in config.items():
        if any(indicator in key.lower() for indicator in ['recent', 'history', 'list']):
            if 'old_family_video' in value:
                return True, "✓ VLC was used to open the target video", 1.0
    
    # Check recent files check export
    recent_check_path = Path(export_dir) / "vlc_recent_check.txt"
    if recent_check_path.exists():
        try:
            content = recent_check_path.read_text()
            if 'old_family_video' in content and 'not_in_recent' not in content:
                return True, "✓ VLC opened the target video", 0.9
        except Exception:
            pass
    
    # If config has reasonable size, assume it was used
    if len(config) > 10:
        return True, "✓ VLC was used (configuration detected)", 0.6
    
    return False, "? Could not confirm VLC was used to open the video", 0.3


def verify_fix_aspect_ratio(traj, env_info, task_info):
    """
    Main verification function for fix_aspect_ratio task.
    
    Args:
        traj: Trajectory (not used in this verifier)
        env_info: Environment info containing copy_from_env function
        task_info: Task info (not used in this verifier)
        
    Returns:
        Dictionary with verification results
    """
    logger.info("Verifying fix_aspect_ratio task")
    
    # Initialize result
    result = {
        'passed': False,
        'score': 0,
        'feedback': [],
        'details': {}
    }
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        result['feedback'].append("✗ Copy function not available")
        logger.error("copy_from_env function not available")
        return result
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy VLC configuration file
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        logger.info("Copying VLC config from container")
        copy_from_env("/tmp/vlc_aspect_config.txt", temp_config.name)
        
        # Check if file indicates config was not found
        with open(temp_config.name, 'r') as f:
            first_line = f.readline().strip()
            if first_line == 'not_found':
                result['feedback'].append("✗ VLC configuration file not found")
                result['feedback'].append("  Make sure you opened VLC and changed the aspect ratio setting")
                logger.error("VLC config not found in container")
                os.unlink(temp_config.name)
                return result
        
        criteria_met += 1
        feedback_parts.append("✓ VLC config accessible")
        
    except Exception as e:
        result['feedback'].append(f"✗ Could not access VLC configuration: {str(e)}")
        logger.error(f"Error copying VLC config: {e}")
        try:
            os.unlink(temp_config.name)
        except:
            pass
        return result
    
    # Parse VLC configuration
    logger.info(f"Parsing VLC config from: {temp_config.name}")
    config = parse_vlc_config(temp_config.name)
    
    if not config:
        feedback_parts.append("✗ Could not parse VLC configuration")
        logger.error("Failed to parse VLC config")
        result['feedback'] = feedback_parts
        os.unlink(temp_config.name)
        return result
    
    result['details']['config_keys_count'] = len(config)
    logger.info(f"Found {len(config)} configuration entries")
    
    # Check if VLC was actually used
    # First, try to get export_dir from env (for recent check file)
    # Since we don't have direct access, we'll copy it separately
    temp_recent = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_recent_check.txt", temp_recent.name)
        # Create a minimal "export dir" for the check
        temp_dir = tempfile.mkdtemp()
        recent_path = Path(temp_dir) / "vlc_recent_check.txt"
        with open(temp_recent.name, 'r') as src, open(recent_path, 'w') as dst:
            dst.write(src.read())
        
        vlc_used, vlc_msg, vlc_conf = check_vlc_usage(config, temp_dir)
        
        # Cleanup temp dir
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)
        os.unlink(temp_recent.name)
    except Exception as e:
        logger.warning(f"Could not check recent files: {e}")
        vlc_used, vlc_msg, vlc_conf = check_vlc_usage(config, "")
    
    feedback_parts.append(vlc_msg)
    result['details']['vlc_used'] = vlc_used
    
    if vlc_used:
        criteria_met += 1
    
    # Check aspect ratio setting (most important criterion)
    aspect_correct, aspect_msg, aspect_conf = check_aspect_ratio_setting(config)
    feedback_parts.append(aspect_msg)
    result['details']['aspect_ratio'] = config.get('aspect-ratio', 'not_set')
    result['details']['aspect_ratio_correct'] = aspect_correct
    
    if aspect_correct:
        criteria_met += 1
    
    # Calculate final score
    # Aspect ratio correctness is weighted more heavily
    if aspect_correct and vlc_used:
        result['success'] = True
        result['score'] = int(min(aspect_conf * vlc_conf * 100, 100))
        feedback_parts.append("\n✓ Task completed successfully!")
        feedback_parts.append("  The aspect ratio has been correctly set to 4:3")
    elif aspect_correct and not vlc_used:
        result['success'] = True
        result['score'] = int(aspect_conf * 75)  # Reduced score if VLC usage unclear
        feedback_parts.append("\n✓ Aspect ratio is correct")
        feedback_parts.append("  (VLC usage could not be fully confirmed)")
    elif not aspect_correct and vlc_used:
        result['score'] = 30  # Partial credit for using VLC
        feedback_parts.append("\n✗ Task incomplete: aspect ratio is not correctly set")
        feedback_parts.append("  Hint: In VLC, go to Video → Aspect Ratio → 4:3")
        feedback_parts.append("  Or press 'A' key to cycle through aspect ratios")
    else:
        result['score'] = 0
        feedback_parts.append("\n✗ Task not completed")
        feedback_parts.append("  Please open VLC, play the video, and set aspect ratio to 4:3")
    
    # Set passed based on score
    result['passed'] = result['score'] >= 70
    
    # Add diagnostic info
    feedback_parts.append(f"\nDiagnostic info:")
    feedback_parts.append(f"  - Aspect ratio setting: {config.get('aspect-ratio', 'not set')}")
    feedback_parts.append(f"  - Config entries: {len(config)}")
    feedback_parts.append(f"  - Criteria met: {criteria_met}/{total_criteria}")
    
    result['feedback'] = "\n".join(feedback_parts)
    
    # Cleanup
    os.unlink(temp_config.name)
    
    logger.info(f"Verification complete. Success: {result['passed']}, Score: {result['score']}")
    
    return result


# Entry point for gym-anything framework
def verify(traj, env_info, task_info):
    """
    Entry point called by gym-anything framework.
    """
    return verify_fix_aspect_ratio(traj, env_info, task_info)
