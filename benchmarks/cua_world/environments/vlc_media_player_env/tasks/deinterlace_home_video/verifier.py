#!/usr/bin/env python3
"""
Verifier for Deinterlace Home Video task

Checks if VLC deinterlacing is properly enabled for home video playback.
"""

import sys
import os
import logging
import tempfile
import json
from pathlib import Path
from typing import Tuple, Dict, Any, Optional

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    parse_vlc_config,
    get_video_info,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


def parse_qt_config(filepath: str) -> Dict[str, str]:
    """
    Parse VLC Qt interface config file.
    
    Format is similar to INI with [sections] and key=value pairs.
    """
    config = {}
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            current_section = None
            for line in f:
                line = line.strip()
                
                # Skip empty lines and comments
                if not line or line.startswith('#') or line.startswith(';'):
                    continue
                
                # Section header
                if line.startswith('[') and line.endswith(']'):
                    current_section = line[1:-1]
                    continue
                
                # Key-value pair
                if '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()
                    
                    # Store with section prefix if in a section
                    if current_section:
                        full_key = f"{current_section}.{key}"
                    else:
                        full_key = key
                    
                    config[full_key] = value
        
        return config
    except Exception as e:
        logger.error(f"Error parsing Qt config: {e}")
        return {}


def check_deinterlacing_config(export_dir: str) -> Tuple[bool, str, Dict[str, Any]]:
    """
    Check if deinterlacing is properly configured in VLC.
    
    VLC stores deinterlacing settings in multiple locations:
    1. vlcrc: deinterlace=<value>, deinterlace-mode=<mode>
       - deinterlace: -1 (auto), 0 (off), 1 (on), 2 (on)
       - mode: discard, blend, mean, bob, linear, x, yadif, yadif2x, phosphor, ivtc
    2. Qt interface config: may have video-related settings
    3. Runtime state: captured during export
    
    Returns:
        Tuple of (success, feedback, info_dict)
    """
    export_path = Path(export_dir)
    
    info = {
        'deinterlace_enabled': False,
        'deinterlace_value': None,
        'deinterlace_mode': None,
        'config_source': None,
        'vlc_was_running': False,
        'video_loaded': False,
        'runtime_state': {}
    }
    
    # Valid deinterlacing modes
    VALID_MODES = [
        'discard', 'blend', 'mean', 'bob', 'linear', 
        'x', 'yadif', 'yadif2x', 'phosphor', 'ivtc'
    ]
    RECOMMENDED_MODES = ['yadif', 'yadif2x', 'linear', 'bob']
    
    # Check if VLC was running
    process_file = export_path / 'vlc_process.txt'
    if process_file.exists():
        content = process_file.read_text()
        if 'vlc' in content.lower() and 'not running' not in content.lower():
            info['vlc_was_running'] = True
            logger.info("✓ VLC process was running")
    
    # Check if video was loaded
    video_loaded_file = export_path / 'video_loaded.txt'
    if video_loaded_file.exists():
        content = video_loaded_file.read_text().strip().lower()
        info['video_loaded'] = (content == 'true')
        if info['video_loaded']:
            logger.info("✓ Home video was loaded in VLC")
    
    # Check runtime state (captured during export)
    runtime_state_file = export_path / 'runtime_state.json'
    if runtime_state_file.exists():
        try:
            with open(runtime_state_file, 'r') as f:
                runtime_state = json.load(f)
            
            info['runtime_state'] = runtime_state
            
            if runtime_state.get('runtime_captured') and runtime_state.get('deinterlace_enabled'):
                info['deinterlace_enabled'] = True
                info['config_source'] = 'runtime'
                if runtime_state.get('deinterlace_mode'):
                    info['deinterlace_mode'] = runtime_state['deinterlace_mode']
                logger.info(f"✓ Runtime state shows deinterlacing enabled: {info['deinterlace_mode']}")
        except Exception as e:
            logger.warning(f"Could not parse runtime state: {e}")
    
    # Check main VLC config (vlcrc)
    vlcrc_file = export_path / 'vlcrc'
    if vlcrc_file.exists():
        vlc_config = parse_vlc_config(str(vlcrc_file))
        
        # Check deinterlace setting
        deinterlace_setting = vlc_config.get('deinterlace', '0')
        deinterlace_mode = vlc_config.get('deinterlace-mode', '').lower()
        
        logger.info(f"vlcrc - deinterlace: {deinterlace_setting}, mode: {deinterlace_mode}")
        
        # deinterlace values: -1 (auto), 0 (off), 1 (on), 2 (on)
        if deinterlace_setting in ['1', '2', '-1']:
            info['deinterlace_enabled'] = True
            info['deinterlace_value'] = deinterlace_setting
            if not info['config_source']:
                info['config_source'] = 'vlcrc'
        
        # Check mode
        if deinterlace_mode and deinterlace_mode in VALID_MODES:
            info['deinterlace_mode'] = deinterlace_mode
            # If mode is set to valid value but enabled is not, still count as enabled
            if not info['deinterlace_enabled'] and deinterlace_mode != 'disabled':
                info['deinterlace_enabled'] = True
                info['config_source'] = 'vlcrc'
        
        # Also check sout-deinterlace-mode (streaming output deinterlace)
        sout_mode = vlc_config.get('sout-deinterlace-mode', '').lower()
        if sout_mode and sout_mode in VALID_MODES:
            logger.info(f"Found sout deinterlace mode: {sout_mode}")
    else:
        logger.warning("vlcrc file not found")
    
    # Check Qt interface config
    qt_config_file = export_path / 'vlc-qt-interface.conf'
    if qt_config_file.exists():
        qt_config = parse_qt_config(str(qt_config_file))
        
        # Look for deinterlace-related keys
        for key, value in qt_config.items():
            key_lower = key.lower()
            value_lower = value.lower().strip('"\'')
            
            if 'deinterlace' in key_lower:
                logger.info(f"Qt config - {key}: {value}")
                
                if 'mode' in key_lower:
                    if value_lower in VALID_MODES:
                        if not info['deinterlace_mode']:
                            info['deinterlace_mode'] = value_lower
                        info['deinterlace_enabled'] = True
                        if not info['config_source']:
                            info['config_source'] = 'qt-config'
                
                elif key_lower.endswith('deinterlace'):
                    if value_lower in ['1', '2', '-1', 'true', 'on']:
                        info['deinterlace_enabled'] = True
                        info['deinterlace_value'] = value
                        if not info['config_source']:
                            info['config_source'] = 'qt-config'
    
    # Determine success and create feedback
    success = False
    feedback = ""
    
    # Check if deinterlacing is enabled
    if not info['deinterlace_enabled']:
        feedback = "❌ Deinterlacing is NOT enabled.\n\n"
        feedback += "The old home video still has combing artifacts!\n\n"
        feedback += "To fix interlaced video:\n"
        feedback += "1. Open the video in VLC (/home/ga/Videos/family_vacation_1998.avi)\n"
        feedback += "2. Go to Video menu → Deinterlace → Select a mode\n"
        feedback += "   Recommended: Yadif (best quality)\n"
        feedback += "   Alternative: Press 'D' key to cycle through modes\n"
        feedback += "3. Watch for the scan line 'combing' artifacts to disappear\n"
        feedback += "4. The setting should persist in VLC's configuration\n"
        return False, feedback, info
    
    # Check if a valid mode is set
    if info['deinterlace_enabled'] and not info['deinterlace_mode']:
        feedback = "⚠️ Deinterlacing is enabled but no specific mode detected.\n\n"
        feedback += "This configuration might work, but it's better to explicitly set a mode.\n\n"
        feedback += "Recommended: Video → Deinterlace → Yadif\n"
        return False, feedback, info
    
    # Check mode validity
    if info['deinterlace_mode'] and info['deinterlace_mode'] not in VALID_MODES:
        feedback = f"❌ Invalid deinterlace mode: '{info['deinterlace_mode']}'\n\n"
        feedback += f"Valid modes: {', '.join(VALID_MODES)}\n"
        feedback += f"Recommended: {', '.join(RECOMMENDED_MODES)}"
        return False, feedback, info
    
    # Success!
    if info['deinterlace_enabled'] and info['deinterlace_mode']:
        success = True
        feedback = "✅ Deinterlacing successfully configured!\n\n"
        feedback += f"   Mode: {info['deinterlace_mode']}"
        
        if info['deinterlace_mode'] in RECOMMENDED_MODES:
            feedback += " ⭐ (excellent choice - high quality)"
        
        feedback += f"\n   Source: {info['config_source']}"
        
        if info['deinterlace_value']:
            feedback += f"\n   Setting value: {info['deinterlace_value']}"
        
        feedback += "\n\n"
        feedback += "The old home video should now play smoothly without combing artifacts.\n"
        feedback += "This setting will persist for future interlaced videos."
        
        if info['deinterlace_mode'] == 'yadif':
            feedback += "\n\n💡 Excellent! Yadif is one of the best deinterlacers for preserving video quality."
        elif info['deinterlace_mode'] == 'bob':
            feedback += "\n\n💡 Good choice! Bob mode doubles the framerate for smooth motion."
        elif info['deinterlace_mode'] == 'linear':
            feedback += "\n\n💡 Nice! Linear mode offers a good balance of quality and performance."
    
    return success, feedback, info


def verify_deinterlace_home_video(traj, env_info, task_info) -> Tuple[float, str]:
    """
    Main verification function for deinterlacing task.
    
    Args:
        traj: Trajectory data (not used in this verifier)
        env_info: Environment info dict with 'copy_from_env' function
        task_info: Task info dict (not used in this verifier)
    
    Returns:
        Tuple of (reward, feedback_message)
        reward: 1.0 for success, 0.0 for failure
        feedback: Detailed feedback string
    """
    try:
        logger.info("=" * 60)
        logger.info("Starting deinterlacing configuration verification...")
        logger.info("=" * 60)
        
        copy_from_env = env_info.get('copy_from_env')
        if not copy_from_env:
            return 0.0, "❌ Error: Copy function not available for verification"
        
        # Create temporary directory for exported files
        temp_export_dir = tempfile.mkdtemp(prefix='vlc_deinterlace_verify_')
        logger.info(f"Created temp directory: {temp_export_dir}")
        
        try:
            # Copy all exported files from container
            export_source = '/tmp/task_export'
            
            # Try to copy the entire export directory
            # Since we can't copy directories directly, copy known files
            export_files = [
                'vlcrc',
                'vlc-qt-interface.conf',
                'vlc_process.txt',
                'video_loaded.txt',
                'runtime_state.json'
            ]
            
            files_copied = 0
            for filename in export_files:
                source_path = f"{export_source}/{filename}"
                dest_path = os.path.join(temp_export_dir, filename)
                
                try:
                    copy_from_env(source_path, dest_path)
                    if os.path.exists(dest_path):
                        files_copied += 1
                        logger.info(f"✓ Copied {filename}")
                except Exception as e:
                    logger.debug(f"Could not copy {filename}: {e}")
            
            if files_copied == 0:
                return 0.0, "❌ Error: Could not copy any configuration files from container"
            
            logger.info(f"Successfully copied {files_copied} configuration files")
            
            # Verify the video file exists and is interlaced (optional check)
            try:
                video_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.avi')
                copy_from_env('/home/ga/Videos/family_vacation_1998.avi', video_temp.name)
                
                if os.path.exists(video_temp.name) and os.path.getsize(video_temp.name) > 1000:
                    video_info = get_video_info(video_temp.name)
                    logger.info(f"Video info: {video_info.get('width', 'N/A')}x{video_info.get('height', 'N/A')}, "
                              f"codec={video_info.get('codec', 'N/A')}, "
                              f"duration={video_info.get('duration', 'N/A')}s")
                
                os.unlink(video_temp.name)
            except Exception as e:
                logger.warning(f"Could not verify video file (non-critical): {e}")
            
            # Check deinterlacing configuration
            success, feedback, info = check_deinterlacing_config(temp_export_dir)
            
            # Log detailed info
            logger.info("=" * 60)
            logger.info("Verification Results:")
            logger.info(f"  Deinterlacing enabled: {info['deinterlace_enabled']}")
            logger.info(f"  Deinterlacing mode: {info['deinterlace_mode']}")
            logger.info(f"  Config source: {info['config_source']}")
            logger.info(f"  VLC was running: {info['vlc_was_running']}")
            logger.info(f"  Video was loaded: {info['video_loaded']}")
            logger.info("=" * 60)
            
            if success:
                logger.info("✅ TASK COMPLETED SUCCESSFULLY!")
                reward = 1.0
            else:
                logger.info("❌ Task not completed - deinterlacing not properly configured")
                reward = 0.0
            
            return reward, feedback
        
        finally:
            # Cleanup temp directory
            cleanup_verification_environment(temp_export_dir)
            logger.info("Cleaned up temporary files")
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return 0.0, f"❌ Verification failed with error: {str(e)}"
