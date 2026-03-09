#!/usr/bin/env python3
"""
Verifier for Optimize Battery Playback task

Checks that VLC has been configured for power-efficient playback:
- Hardware acceleration enabled
- CPU-intensive features disabled
- Optimizations applied and persisted
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_hardware_acceleration(config: dict) -> tuple[bool, str, dict]:
    """
    Verify VLC configuration has battery optimization settings enabled.
    
    Args:
        config: Parsed VLC configuration dictionary
        
    Returns:
        Tuple of (success, feedback_message, details_dict)
    """
    issues = []
    successes = []
    details = {}
    
    # Check 1: Hardware acceleration enabled (CRITICAL)
    hw_decode = config.get('avcodec-hw', 'none').lower().strip()
    details['hardware_acceleration'] = hw_decode
    
    # Valid hardware acceleration values (anything except 'none' or empty)
    # Common values: 'auto', 'automatic', 'any', 'vaapi', 'vdpau', 'dxva2', 'videotoolbox', 'nvdec', 'd3d11va'
    hw_enabled = hw_decode not in ['none', '', 'disabled', 'disable']
    
    if not hw_enabled:
        issues.append("❌ Hardware acceleration NOT enabled (still using software decoding - high CPU usage)")
        logger.warning(f"Hardware acceleration disabled: avcodec-hw={hw_decode}")
    else:
        successes.append(f"✅ Hardware acceleration ENABLED: {hw_decode}")
        logger.info(f"Hardware acceleration enabled: {hw_decode}")
    
    # Check 2: H.264 deblocking filter optimization (reduces CPU on H264 content)
    skip_filter = config.get('avcodec-skiploopfilter', '0').strip()
    details['skip_loop_filter'] = skip_filter
    
    # Values: 0=none, 1=nonref, 2=bidir, 3=nonkey, 4=all
    # Higher values = more skipping = less CPU usage
    if skip_filter in ['0', '']:
        issues.append("⚠️  H.264 loop filter not optimized (minor - consider setting to skip for more battery savings)")
    else:
        successes.append(f"✅ H.264 loop filter optimized: level {skip_filter}")
        logger.info(f"Loop filter optimization: {skip_filter}")
    
    # Check 3: Video filters disabled (any active filter uses CPU)
    video_filter = config.get('video-filter', '').strip()
    vout_filter = config.get('vout-filter', '').strip()
    details['video_filter'] = video_filter if video_filter else 'none'
    details['vout_filter'] = vout_filter if vout_filter else 'none'
    
    if video_filter or vout_filter:
        issues.append(f"⚠️  Video filters active (consumes CPU): video-filter='{video_filter}', vout-filter='{vout_filter}'")
        logger.warning(f"Active filters detected: video={video_filter}, vout={vout_filter}")
    else:
        successes.append("✅ Video filters disabled (no unnecessary processing)")
        logger.info("No active video filters")
    
    # Check 4: Deinterlacing configuration
    deinterlace = config.get('deinterlace', '0').strip()
    deinterlace_mode = config.get('deinterlace-mode', 'auto').strip().lower()
    details['deinterlace'] = deinterlace
    details['deinterlace_mode'] = deinterlace_mode
    
    # Deinterlacing on with complex modes can use CPU
    if deinterlace == '1' and deinterlace_mode not in ['auto', 'none', '']:
        issues.append(f"⚠️  Active deinterlacing may consume CPU: mode={deinterlace_mode}")
    else:
        successes.append("✅ Deinterlacing configured efficiently")
        logger.info(f"Deinterlacing: {deinterlace}, mode: {deinterlace_mode}")
    
    # Calculate success
    # CRITICAL: Hardware acceleration must be enabled
    critical_check_passed = hw_enabled
    
    # Calculate optimization score (percentage of non-critical checks passed)
    total_checks = len(successes) + len(issues)
    optimization_score = len(successes) / total_checks if total_checks > 0 else 0
    
    # Decision: Pass if hardware acceleration enabled AND at least 50% of other optimizations
    success = critical_check_passed and optimization_score >= 0.5
    
    # Build detailed feedback message
    feedback_lines = [
        "=" * 60,
        "🔋 VLC BATTERY OPTIMIZATION VERIFICATION",
        "=" * 60,
        ""
    ]
    
    if successes:
        feedback_lines.extend(successes)
    
    if issues:
        feedback_lines.append("")
        feedback_lines.extend(issues)
    
    feedback_lines.extend([
        "",
        f"📊 Optimization Score: {optimization_score:.0%}",
        f"🎯 Result: {'✅ PASS' if success else '❌ FAIL'}",
        ""
    ])
    
    if critical_check_passed:
        feedback_lines.append("✅ CRITICAL: Hardware acceleration is enabled")
    else:
        feedback_lines.append("❌ CRITICAL: Hardware acceleration is NOT enabled (main requirement)")
    
    feedback_lines.extend([
        "",
        "Configuration Details:",
    ])
    
    for key, value in details.items():
        feedback_lines.append(f"  • {key}: {value}")
    
    if not success:
        feedback_lines.extend([
            "",
            "💡 To pass this task:",
            "  1. Open VLC Preferences (Tools → Preferences or Ctrl+P)",
            "  2. Switch to 'All' settings (bottom-left radio button)",
            "  3. Navigate to Input / Codecs",
            "  4. Set 'Hardware-accelerated decoding' to 'Automatic' or 'VA-API'",
            "  5. Click 'Save' button",
            "  6. Restart VLC if prompted",
            "",
            "🔑 Hardware acceleration is the MOST IMPORTANT setting for battery life!"
        ])
    
    feedback = "\n".join(feedback_lines)
    
    return success, feedback, details


def verify_optimize_battery_playback(traj, env_info, task_info):
    """
    Main verification function called by gym-anything.
    
    Args:
        traj: Trajectory information (not used in this static verification)
        env_info: Environment info with copy_from_env function
        task_info: Task information (not used)
        
    Returns:
        dict with 'passed' (bool), 'score' (int), and 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            'passed': False,
            'score': 0,
            'feedback': "❌ Copy function not available - cannot verify task"
        }
    
    # Create temp file for VLC config
    temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.vlcrc', mode='w+')
    temp_vlcrc.close()
    
    try:
        # Copy VLC configuration from container
        try:
            copy_from_env("/tmp/vlc_battery_config.vlcrc", temp_vlcrc.name)
            logger.info(f"Successfully copied config to {temp_vlcrc.name}")
        except Exception as e:
            logger.error(f"Failed to copy config file: {e}")
            os.unlink(temp_vlcrc.name)
            return {
                'passed': False,
                'score': 0,
                'feedback': (
                    "❌ VLC configuration file not found or not exported.\n"
                    "Expected: vlcrc file exported to /tmp/vlc_battery_config.vlcrc\n\n"
                    "Did you:\n"
                    "  1. Open VLC Preferences?\n"
                    "  2. Make changes to settings?\n"
                    "  3. Click 'Save' to persist changes?\n\n"
                    f"Error: {str(e)}"
                )
            }
        
        # Check if file is empty
        if os.path.getsize(temp_vlcrc.name) == 0:
            os.unlink(temp_vlcrc.name)
            return {
                'passed': False,
                'score': 0,
                'feedback': (
                    "❌ VLC configuration file is empty.\n"
                    "The vlcrc file exists but contains no settings.\n\n"
                    "This usually means settings were not saved properly.\n"
                    "Make sure to click 'Save' after changing preferences."
                )
            }
        
        # Parse VLC config
        config = parse_vlc_config(temp_vlcrc.name)
        
        if not config or len(config) == 0:
            os.unlink(temp_vlcrc.name)
            return {
                'passed': False,
                'score': 0,
                'feedback': (
                    "❌ Could not parse VLC configuration file.\n"
                    "The vlcrc file may be corrupted or in an unexpected format.\n\n"
                    "Try resetting VLC preferences and starting the task again."
                )
            }
        
        logger.info(f"Parsed {len(config)} configuration entries")
        
        # Verify battery optimization settings
        success, feedback, details = verify_hardware_acceleration(config)
        
        # Calculate score (0-100)
        # Full score if all criteria met, partial score otherwise
        if success:
            # Passed - give 85-100 based on how many optimizations
            optimization_level = len([v for v in details.values() if v not in ['none', '0', '']])
            score = min(100, 85 + (optimization_level * 3))
        else:
            # Failed - give partial credit if some things were done
            hw_enabled = details.get('hardware_acceleration', 'none') not in ['none', '', 'disabled']
            if hw_enabled:
                score = 60  # Hardware acceleration enabled but other issues
            else:
                score = max(10, len([k for k, v in details.items() if v not in ['none', '0', '']]) * 10)
        
        # Log results for debugging
        logger.info(f"Verification result: {'PASS' if success else 'FAIL'}")
        logger.info(f"Score: {score}")
        logger.info(f"Details: {details}")
        
        # Clean up temp file
        os.unlink(temp_vlcrc.name)
        
        return {
            'passed': success,
            'score': score,
            'feedback': feedback
        }
        
    except Exception as e:
        # Clean up temp file on error
        if os.path.exists(temp_vlcrc.name):
            os.unlink(temp_vlcrc.name)
        
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            'passed': False,
            'score': 0,
            'feedback': f"❌ Verification error: {str(e)}\n\nPlease report this issue."
        }
