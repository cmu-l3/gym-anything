#!/usr/bin/env python3
"""
Verifier for setup_exhibition_loop@1

Verifies that VLC is properly configured for unattended exhibition looping
by parsing the VLC configuration file (vlcrc).
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_setup_exhibition_loop(traj, env_info, task_info):
    """
    Verify that VLC is configured for professional exhibition looping.
    
    Checks:
    1. Loop/Repeat enabled (CRITICAL - 2.0 points)
    2. Fullscreen mode (CRITICAL - 1.5 points)
    3. Minimal interface (IMPORTANT - 1.0 point)
    4. Video title disabled (NICE TO HAVE - 0.3 points)
    5. Notifications disabled (NICE TO HAVE - 0.2 points)
    
    Total: 5.0 points, normalized to 0-1 scale
    Success requires: loop/repeat AND fullscreen AND score >= 0.7
    
    Returns:
        Dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "❌ Copy function not available - cannot verify configuration"
        }
    
    criteria_met = 0.0
    max_score = 5.0
    feedback_parts = []
    issues = []
    
    try:
        # Load expected state for reference
        expected_state = None
        try:
            with open('/tmp/task_state/exhibition_loop_expected.json', 'r') as f:
                expected_state = json.load(f)
            logger.info("✓ Loaded expected state")
        except Exception as e:
            logger.warning(f"Could not load expected state: {e}")
        
        # Step 1: Copy VLC config from container
        temp_config = tempfile.NamedTemporaryFile(mode='w+', delete=False, suffix='_vlcrc.txt')
        temp_config_path = temp_config.name
        temp_config.close()
        
        try:
            copy_from_env("/tmp/vlc_exhibition_config.txt", temp_config_path)
        except Exception as e:
            logger.error(f"Failed to copy VLC config: {e}")
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Failed to access VLC configuration file: {str(e)}\n"
                           "VLC may not have been launched or configured."
            }
        
        # Check if config file exists and is valid
        if not os.path.exists(temp_config_path):
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ VLC configuration file not found - VLC may not have been configured"
            }
        
        with open(temp_config_path, 'r') as f:
            content = f.read().strip()
        
        if not content or content == "error: config_not_found":
            os.unlink(temp_config_path)
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ VLC configuration file not found or empty\n"
                           "You need to launch VLC and configure it through Tools → Preferences"
            }
        
        logger.info(f"✓ VLC config file exists ({len(content)} bytes)")
        
        # Step 2: Parse VLC configuration
        config = parse_vlc_config(temp_config_path)
        
        if not config:
            os.unlink(temp_config_path)
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Could not parse VLC configuration file\n"
                           "The configuration file may be corrupted or invalid"
            }
        
        logger.info(f"✓ VLC config parsed successfully ({len(config)} settings found)")
        
        # Step 3: Check exhibition-specific settings
        
        # Criterion 1: Loop/Repeat enabled (CRITICAL - 2.0 points)
        loop_enabled = config.get('loop', '0') == '1'
        repeat_enabled = config.get('repeat', '0') == '1'
        
        if loop_enabled or repeat_enabled:
            criteria_met += 2.0
            loop_type = 'loop' if loop_enabled else 'repeat'
            feedback_parts.append(f"✅ Continuous looping enabled ({loop_type})")
            logger.info(f"✓ Loop/Repeat enabled: {loop_type}={config.get(loop_type, '0')}")
        else:
            issues.append("Video will not loop continuously (neither 'loop' nor 'repeat' enabled)")
            feedback_parts.append("❌ Looping NOT enabled - video will play once and stop")
            logger.warning("✗ Loop/Repeat not enabled")
        
        # Criterion 2: Fullscreen mode (CRITICAL - 1.5 points)
        fullscreen = config.get('fullscreen', '0') == '1'
        
        if fullscreen:
            criteria_met += 1.5
            feedback_parts.append("✅ Fullscreen mode enabled")
            logger.info("✓ Fullscreen enabled")
        else:
            issues.append("Video will show window borders (fullscreen not enabled)")
            feedback_parts.append("❌ Fullscreen NOT enabled - window borders will be visible")
            logger.warning("✗ Fullscreen not enabled")
        
        # Criterion 3: Minimal interface (IMPORTANT - 1.0 point)
        # Check multiple settings that indicate minimal interface
        qt_minimal_view = config.get('qt-minimal-view', '0') == '1'
        qt_fs_controller = config.get('qt-fs-controller', '1') == '0'  # 0 means disabled/hidden
        no_qt_fs_controller = config.get('no-qt-fs-controller', '0') == '1'
        qt_fullscreen_screennumber = config.get('qt-fullscreen-screennumber', '') != ''
        
        minimal_interface = qt_minimal_view or no_qt_fs_controller or (qt_fs_controller and qt_fullscreen_screennumber)
        
        if minimal_interface:
            criteria_met += 1.0
            reasons = []
            if qt_minimal_view:
                reasons.append("minimal-view")
            if no_qt_fs_controller:
                reasons.append("no-fs-controller")
            if qt_fs_controller:
                reasons.append("fs-controller-disabled")
            
            feedback_parts.append(f"✅ Minimal interface configured ({', '.join(reasons)})")
            logger.info(f"✓ Minimal interface: {reasons}")
        else:
            issues.append("Player controls may be visible (minimal interface not configured)")
            feedback_parts.append("⚠️ Minimal interface not fully configured - controls may be visible")
            logger.info("○ Minimal interface not fully configured")
        
        # Criterion 4: Video title overlay disabled (NICE TO HAVE - 0.3 points)
        video_title_show = config.get('video-title-show', '1')
        video_title_disabled = video_title_show == '0' or video_title_show == 'false'
        
        if video_title_disabled:
            criteria_met += 0.3
            feedback_parts.append("✅ Video title overlay disabled")
            logger.info("✓ Video title overlay disabled")
        else:
            logger.info("○ Video title overlay not explicitly disabled (minor cosmetic issue)")
        
        # Criterion 5: Notifications disabled (NICE TO HAVE - 0.2 points)
        qt_notification = config.get('qt-notification', '1')
        notifications_disabled = qt_notification == '0' or qt_notification == 'false'
        
        if notifications_disabled:
            criteria_met += 0.2
            feedback_parts.append("✅ Notifications disabled")
            logger.info("✓ Notifications disabled")
        else:
            logger.info("○ Notifications not explicitly disabled (minor issue)")
        
        # Clean up temp file
        os.unlink(temp_config_path)
        
        # Step 4: Calculate final score
        normalized_score = criteria_met / max_score
        
        # Must have BOTH loop AND fullscreen at minimum for success
        critical_requirements_met = (loop_enabled or repeat_enabled) and fullscreen
        success = critical_requirements_met and normalized_score >= 0.7
        
        # Step 5: Generate detailed feedback
        if success:
            feedback = "✅ Exhibition loop configured successfully!\n"
            feedback += f"Score: {criteria_met:.1f}/{max_score:.1f} ({normalized_score*100:.0f}%)\n\n"
            feedback += "Configuration verified:\n"
            feedback += f"  • {'✅' if (loop_enabled or repeat_enabled) else '❌'} Video will loop continuously\n"
            feedback += f"  • {'✅' if fullscreen else '❌'} Fullscreen mode enabled\n"
            feedback += f"  • {'✅' if minimal_interface else '⚠️'} Minimal interface configured\n"
            feedback += f"  • {'✅' if video_title_disabled else '○'} Video title overlay handled\n"
            feedback += f"  • {'✅' if notifications_disabled else '○'} Notifications handled\n\n"
            feedback += "This configuration is suitable for unattended exhibition display.\n"
            feedback += "The video will play continuously in fullscreen without visible controls."
        else:
            feedback = "❌ Exhibition loop configuration incomplete\n"
            feedback += f"Score: {criteria_met:.1f}/{max_score:.1f} ({normalized_score*100:.0f}%)\n\n"
            
            if issues:
                feedback += "Critical issues found:\n"
                for i, issue in enumerate(issues, 1):
                    feedback += f"  {i}. {issue}\n"
                feedback += "\n"
            
            feedback += "Required for professional exhibition display:\n"
            feedback += "  1. ✓ MUST enable Loop or Repeat mode\n"
            feedback += "     → Tools → Preferences → Show settings: All\n"
            feedback += "     → Playlist → Check 'Repeat all' or 'Loop'\n\n"
            feedback += "  2. ✓ MUST enable Fullscreen mode\n"
            feedback += "     → Tools → Preferences → Video\n"
            feedback += "     → Check 'Fullscreen' checkbox\n\n"
            feedback += "  3. ✓ SHOULD configure minimal interface\n"
            feedback += "     → Tools → Preferences → Interface\n"
            feedback += "     → Configure Qt interface for minimal view\n\n"
            
            if not critical_requirements_met:
                feedback += "⚠️ CRITICAL: Missing loop/repeat and/or fullscreen!\n"
                feedback += "These are mandatory for exhibition display.\n"
        
        logger.info(f"Final score: {criteria_met:.1f}/{max_score:.1f} = {normalized_score:.2f}")
        logger.info(f"Success: {success}")
        
        return {
            "passed": success,
            "score": normalized_score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}\n"
                       "This is likely a system error, not a configuration issue."
        }
