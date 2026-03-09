#!/usr/bin/env python3
"""
Verifier for Surround Sound Test task (test_surround_sound_setup@1)
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


def verify_test_surround_sound_setup(traj, env_info, task_info):
    """
    Verify surround sound test task completion.
    
    Verification criteria with weighted scoring:
    1. Multi-channel configuration (25%): VLC configured for 6+ channels
    2. Output module configured (20%): Explicit audio output module set
    3. Test file played (15%): Evidence of test file playback
    4. Report exists (25%): Configuration report file created
    5. Report complete (15%): Report contains detailed information
    
    Pass threshold: 60%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_scores = {}
    feedback_parts = []
    
    # Criterion 1: Multi-channel configuration (25%)
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    config_parsed = False
    
    try:
        copy_from_env("/tmp/vlc_surround_config.txt", temp_config.name)
        
        config = parse_vlc_config(temp_config.name)
        config_parsed = True
        
        # Check for multi-channel indicators
        multi_channel = False
        audio_channels = config.get('audio-channels', '')
        aout = config.get('aout', '')
        
        # Check if channels >= 6
        if audio_channels:
            try:
                channels = int(audio_channels)
                if channels >= 6:
                    multi_channel = True
                    feedback_parts.append(f"✅ Multi-channel: {channels} channels configured")
                else:
                    feedback_parts.append(f"⚠️ Channels={channels} (need 6+ for 5.1)")
            except ValueError:
                # Non-numeric value, check if it's a surround descriptor
                if '5.1' in audio_channels or 'surround' in audio_channels.lower():
                    multi_channel = True
                    feedback_parts.append(f"✅ Multi-channel: {audio_channels}")
        
        # Check for surround-related settings in config keys
        surround_keys = [k for k in config.keys() if 'surround' in k.lower() or '5' in k.lower() or '6' in k.lower()]
        if surround_keys and not multi_channel:
            multi_channel = True
            feedback_parts.append(f"✅ Surround settings: {', '.join(surround_keys[:2])}")
        
        # Check device-specific surround settings
        for key in ['alsa-audio-device', 'pulse-sink']:
            if key in config:
                value = config[key]
                if 'surround' in value.lower() or '5.1' in value or '51' in value:
                    multi_channel = True
                    feedback_parts.append(f"✅ Surround device: {value}")
                    break
        
        if not multi_channel:
            feedback_parts.append("❌ No multi-channel (6ch/5.1) configuration found")
        
        criteria_scores['multi_channel'] = 0.25 if multi_channel else 0.0
        
        # Criterion 2: Output module configured (20%)
        output_configured = False
        
        if aout and aout not in ['auto', 'default', '', 'any']:
            output_configured = True
            feedback_parts.append(f"✅ Audio output: {aout}")
        else:
            # Check for module-specific sections
            module_indicators = ['alsa', 'pulse', 'oss', 'jack', 'wasapi']
            found_modules = [m for m in module_indicators if any(m in k.lower() for k in config.keys())]
            
            if found_modules:
                output_configured = True
                feedback_parts.append(f"✅ Audio module detected: {found_modules[0]}")
            else:
                if aout:
                    feedback_parts.append(f"⚠️ Audio output: {aout} (generic)")
                else:
                    feedback_parts.append("❌ No explicit audio output module")
        
        criteria_scores['output_module'] = 0.20 if output_configured else 0.0
        
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.error(f"Error reading VLC config: {e}")
        feedback_parts.append("❌ Could not read VLC config")
        criteria_scores['multi_channel'] = 0.0
        criteria_scores['output_module'] = 0.0
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)
    
    # Criterion 3: Test file was played (15%)
    test_file_played = False
    
    # Check recent items / media library
    temp_recent = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env("/tmp/vlc_recent_items.xml", temp_recent.name)
        
        with open(temp_recent.name, 'r') as f:
            recent_content = f.read()
        
        if 'surround_test' in recent_content.lower() or '5.1.wav' in recent_content or '5_1.wav' in recent_content:
            test_file_played = True
            feedback_parts.append("✅ Test file in recent items")
        
        os.unlink(temp_recent.name)
    except Exception:
        pass
    
    # Check logs as fallback
    if not test_file_played:
        temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.log')
        try:
            copy_from_env("/tmp/vlc_surround_result.log", temp_log.name)
            
            with open(temp_log.name, 'r') as f:
                log_content = f.read()
            
            if 'surround_test' in log_content.lower() or '5.1.wav' in log_content or '5_1' in log_content:
                test_file_played = True
                feedback_parts.append("✅ Test file in logs")
            
            os.unlink(temp_log.name)
        except Exception:
            pass
    
    if not test_file_played:
        feedback_parts.append("⚠️ No evidence of test file playback")
    
    criteria_scores['test_played'] = 0.15 if test_file_played else 0.0
    
    # Criterion 4 & 5: Report exists and is complete (25% + 15%)
    report_exists = False
    report_complete = False
    
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/audio_config_report.txt", temp_report.name)
        
        # Check if file has content
        if os.path.getsize(temp_report.name) > 10:
            report_exists = True
            feedback_parts.append("✅ Report file exists")
            
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()
            
            # Check for channel-related keywords
            channel_keywords = [
                'front left', 'fl', 
                'front right', 'fr',
                'center', 'centre', 'c',
                'lfe', 'subwoofer', 'sub',
                'rear left', 'rl', 'surround left',
                'rear right', 'rr', 'surround right',
                '5.1', '5 1', 'surround', '6 channel', 'six channel'
            ]
            
            report_lower = report_content.lower()
            
            # Count channel mentions
            channels_mentioned = sum(1 for kw in channel_keywords if kw in report_lower)
            
            # Check for configuration details
            config_keywords = ['output', 'module', 'channel', 'configuration', 'config', 'audio', 'test', 'alsa', 'pulse']
            config_details = sum(1 for kw in config_keywords if kw in report_lower)
            
            # Assess completeness
            if channels_mentioned >= 4 and config_details >= 3:
                report_complete = True
                feedback_parts.append(f"✅ Report complete (channels: {channels_mentioned}, details: {config_details})")
            elif channels_mentioned >= 2 or config_details >= 2:
                feedback_parts.append(f"⚠️ Report partial (channels: {channels_mentioned}, details: {config_details})")
            else:
                feedback_parts.append("⚠️ Report lacks detail")
            
            # Check report length
            report_size = len(report_content.strip())
            if report_size < 50:
                feedback_parts.append(f"⚠️ Report very brief ({report_size} chars)")
            elif report_size > 100:
                feedback_parts.append(f"Report: {report_size} chars")
        else:
            feedback_parts.append("❌ Report file empty")
        
        os.unlink(temp_report.name)
        
    except Exception as e:
        feedback_parts.append("❌ Report not found")
        logger.debug(f"Report not found: {e}")
    
    criteria_scores['report_exists'] = 0.25 if report_exists else 0.0
    criteria_scores['report_complete'] = 0.15 if report_complete else 0.0
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_surround_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed marker found")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker missing")
    
    # Calculate total score
    total_score = sum(criteria_scores.values())
    score = int(total_score * 100)
    passed = total_score >= 0.60  # 60% threshold
    
    feedback = " | ".join(feedback_parts)
    
    # Add detailed scoring breakdown
    breakdown = (f"Scores: multi_ch={criteria_scores.get('multi_channel', 0):.2f}, "
                f"output={criteria_scores.get('output_module', 0):.2f}, "
                f"played={criteria_scores.get('test_played', 0):.2f}, "
                f"report={criteria_scores.get('report_exists', 0):.2f}, "
                f"complete={criteria_scores.get('report_complete', 0):.2f} "
                f"=> Total={total_score:.2f}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": f"{feedback} || {breakdown}"
    }