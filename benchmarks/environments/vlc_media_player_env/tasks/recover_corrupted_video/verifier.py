#!/usr/bin/env python3
"""
Verifier for Recover Corrupted Video task
"""

import sys
import os
import logging
import tempfile
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_vlc_error_recovery_settings(config):
    """
    Check if VLC config has error recovery settings enabled.
    
    Returns dict of checks and count of settings changed.
    """
    checks = {}
    
    # Check AVI repair setting (0=never, 1=ask, 2=fix if broken, 3=always fix)
    avi_index = config.get('avi-index', '0')
    try:
        avi_index_int = int(avi_index)
    except (ValueError, TypeError):
        avi_index_int = 0
    checks['avi_repair'] = avi_index_int >= 2
    
    # Check file caching (default ~300, we want >= 1000)
    file_caching = config.get('file-caching', '300')
    try:
        file_caching_int = int(file_caching)
    except (ValueError, TypeError):
        file_caching_int = 300
    checks['caching_increased'] = file_caching_int >= 1000
    checks['caching_value'] = file_caching_int
    
    # Check skip frames setting
    skip_frame = config.get('avcodec-skip-frame', '0')
    checks['skip_frames'] = skip_frame != '0' and skip_frame != ''
    
    # Check skiploopfilter (can help with corrupted video)
    skiploopfilter = config.get('avcodec-skiploopfilter', '0')
    checks['skip_loopfilter'] = skiploopfilter != '0' and skiploopfilter != ''
    
    # Check if avcodec-fast is enabled (helps with damaged streams)
    avcodec_fast = config.get('avcodec-fast', '0')
    checks['fast_decode'] = avcodec_fast == '1' or avcodec_fast == 'true'
    
    # Hardware acceleration status (sometimes disabling helps)
    hw_accel = config.get('avcodec-hw', '')
    checks['hw_status'] = hw_accel
    
    # Count how many beneficial settings were changed
    settings_changed = sum([
        checks['avi_repair'],
        checks['caching_increased'],
        checks['skip_frames'],
        checks['skip_loopfilter'],
        checks['fast_decode']
    ])
    
    checks['multiple_settings'] = settings_changed >= 3
    checks['settings_count'] = settings_changed
    
    return checks


def analyze_playback_logs(log_content):
    """
    Analyze VLC logs to determine if playback had issues and if they were handled.
    
    Returns dict with analysis results.
    """
    analysis = {
        'errors_found': False,
        'recovery_attempts': False,
        'eof_reached': False,
        'playback_time': 0,
        'error_count': 0,
        'recovery_patterns': []
    }
    
    # Look for error patterns (case insensitive)
    error_patterns = [
        r'error',
        r'corrupt',
        r'damaged',
        r'invalid',
        r'failed to',
        r'cannot read',
        r'broken'
    ]
    
    # Look for recovery patterns
    recovery_patterns = [
        r'trying to fix',
        r'repair',
        r'skip',
        r'buffering',
        r'recovering',
        r'fixing',
        r'rebuilding index',
        r'damaged.*fix'
    ]
    
    # Look for completion patterns
    completion_patterns = [
        r'end of file',
        r'\beof\b',
        r'finished',
        r'playback.*complet'
    ]
    
    lines = log_content.lower().split('\n')
    
    for line in lines:
        # Check for errors
        for pattern in error_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                analysis['errors_found'] = True
                analysis['error_count'] += 1
                break
        
        # Check for recovery attempts
        for pattern in recovery_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                analysis['recovery_attempts'] = True
                if len(analysis['recovery_patterns']) < 3:  # Keep first 3
                    analysis['recovery_patterns'].append(line.strip()[:100])
                break
        
        # Check for EOF
        for pattern in completion_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                analysis['eof_reached'] = True
                break
        
        # Try to extract playback time/position
        time_match = re.search(r'(\d+):(\d+):(\d+)', line)
        if time_match:
            h, m, s = map(int, time_match.groups())
            time_seconds = h * 3600 + m * 60 + s
            if time_seconds > analysis['playback_time'] and time_seconds < 1000:  # Sanity check
                analysis['playback_time'] = time_seconds
    
    # If we have significant playback time (>20 seconds for 30s video) consider it progress
    analysis['significant_playback'] = analysis['playback_time'] >= 20
    
    return analysis


def verify_recover_corrupted_video(traj, env_info, task_info):
    """
    Verify corrupted video recovery task completion.
    
    Checks:
    1. VLC config was modified with error-handling settings
    2. Multiple settings were changed (at least 3)
    3. Logs show recovery attempts or successful playback
    4. Video played through despite corruption (or at least significant progress)
    5. Critical settings like AVI repair and caching were enabled
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Copy and parse VLC config
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/vlc_recovery_config.txt", temp_config.name)
        
        # Parse config
        with open(temp_config.name, 'r') as f:
            config_content = f.read()
        
        if not config_content or len(config_content) < 10:
            os.unlink(temp_config.name)
            return {"passed": False, "score": 0, "feedback": "VLC config not accessible or empty"}
        
        # Parse as vlcrc format using utility function
        config = parse_vlc_config(temp_config.name)
        
        if not config:
            # Fallback manual parsing
            config = {}
            for line in config_content.split('\n'):
                line = line.strip()
                if '=' in line and not line.startswith('#') and not line.startswith('['):
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip()
        
        criteria_met += 1
        feedback_parts.append("✅ Config accessible")
        
        # Check error recovery settings
        settings_check = verify_vlc_error_recovery_settings(config)
        
        settings_changed = settings_check['settings_count']
        feedback_parts.append(f"Settings changed: {settings_changed}")
        
        # Criterion 2: Check critical settings (AVI repair and caching)
        critical_settings_ok = 0
        if settings_check['avi_repair']:
            critical_settings_ok += 1
            feedback_parts.append("✅ AVI repair enabled")
        else:
            feedback_parts.append("⚠️ AVI repair not enabled")
        
        if settings_check['caching_increased']:
            critical_settings_ok += 1
            feedback_parts.append(f"✅ Caching increased ({settings_check['caching_value']}ms)")
        else:
            feedback_parts.append(f"⚠️ Caching not increased ({settings_check['caching_value']}ms)")
        
        if critical_settings_ok >= 2:
            criteria_met += 1
        elif critical_settings_ok >= 1:
            criteria_met += 0.5
        
        # Criterion 3: Multiple settings changed
        if settings_check['multiple_settings']:
            criteria_met += 1
            feedback_parts.append(f"✅ Multiple error-handling settings enabled ({settings_changed})")
        elif settings_changed >= 2:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Some settings changed ({settings_changed})")
        else:
            feedback_parts.append(f"❌ Insufficient settings ({settings_changed} < 3)")
        
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.error(f"Error reading config: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading config: {str(e)}"}
    
    # Criterion 4: Analyze playback logs
    temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.log')
    
    try:
        copy_from_env("/tmp/vlc_recovery_playback.log", temp_log.name)
        
        with open(temp_log.name, 'r', errors='ignore') as f:
            log_content = f.read()
        
        if log_content and len(log_content) > 50:
            log_analysis = analyze_playback_logs(log_content)
            
            # Check if recovery was attempted or playback succeeded
            if log_analysis['recovery_attempts']:
                criteria_met += 1
                feedback_parts.append("✅ Recovery attempts in logs")
            elif log_analysis['significant_playback']:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Playback reached {log_analysis['playback_time']}s")
            else:
                feedback_parts.append("⚠️ Limited recovery evidence")
            
            # Criterion 5: Check playback completion/progress
            if log_analysis['eof_reached'] or log_analysis['playback_time'] >= 25:
                criteria_met += 1
                feedback_parts.append(f"✅ Video played through (≥{log_analysis['playback_time']}s)")
            elif log_analysis['playback_time'] >= 15:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Partial playback ({log_analysis['playback_time']}s)")
            else:
                # Still give some credit if settings were changed properly
                if settings_changed >= 3:
                    criteria_met += 0.3
                feedback_parts.append("⚠️ Limited playback progress")
        else:
            feedback_parts.append("⚠️ Logs unavailable or empty")
            # Give partial credit if settings were properly changed
            if settings_changed >= 3:
                criteria_met += 0.5
        
        os.unlink(temp_log.name)
        
    except Exception as e:
        logger.warning(f"Could not analyze logs: {e}")
        feedback_parts.append("⚠️ Logs not available")
        # Give partial credit if settings were properly changed
        if settings_changed >= 3:
            criteria_met += 0.5
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_recovery_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }