#!/usr/bin/env python3
"""
Verifier for Switch Audio Output Device task

This verifier checks if VLC successfully switched its audio output device
to Reference_Headphones while maintaining playback continuity.
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_switch_audio_output_device(traj, env_info, task_info):
    """
    Verify switch audio output device task completion.
    
    Checks:
    1. VLC was running (indicates task executed)
    2. Target sink (Reference_Headphones) exists in system
    3. VLC's audio stream is routed to Reference_Headphones (PRIMARY - 50%)
    4. VLC config persists the device setting (25%)
    5. VLC uptime indicates no restart occurred (15%)
    6. Completion marker exists (10%)
    
    Pass threshold: 75% (must include audio routing check)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Weighted criteria (total = 100)
    criteria = {
        'vlc_running': {'met': False, 'weight': 10, 'feedback': ''},
        'sink_exists': {'met': False, 'weight': 5, 'feedback': ''},
        'audio_routing': {'met': False, 'weight': 50, 'feedback': ''},  # PRIMARY
        'config_persisted': {'met': False, 'weight': 25, 'feedback': ''},
        'no_restart': {'met': False, 'weight': 10, 'feedback': ''},
    }
    
    feedback_parts = []
    feedback_parts.append("=" * 60)
    feedback_parts.append("VLC Audio Output Device Switch Verification")
    feedback_parts.append("=" * 60)
    
    # Copy and parse result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_audio_output_result.json", temp_result.name)
    except Exception as e:
        logger.error(f"Error copying result file: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Result file not found: {str(e)}"
        }
    
    try:
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Error parsing result JSON: {e}", exc_info=True)
        os.unlink(temp_result.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Invalid result format: {str(e)}"
        }
    
    # Extract data from result
    vlc_running = result.get('vlc_running', False)
    vlc_uptime = result.get('vlc_uptime_seconds', 0)
    audio_sink = result.get('audio_sink', '')
    sink_correct = result.get('sink_correct', False)
    config_device = result.get('config_device', '')
    runtime_captured = result.get('runtime_captured', False)
    available_sinks = result.get('available_sinks', '')
    
    feedback_parts.append("\n1. VLC Running Check:")
    if vlc_running or vlc_uptime > 0:
        criteria['vlc_running']['met'] = True
        criteria['vlc_running']['feedback'] = f"✅ VLC was running (uptime: {vlc_uptime}s)"
        feedback_parts.append(f"   ✅ VLC was running (uptime: {vlc_uptime}s)")
    else:
        criteria['vlc_running']['feedback'] = "❌ VLC was not running"
        feedback_parts.append("   ❌ VLC was not running")
    
    # Check 2: Target sink exists
    feedback_parts.append("\n2. Target Sink Check:")
    if 'reference_headphones' in available_sinks.lower() or 'headphones' in available_sinks.lower():
        criteria['sink_exists']['met'] = True
        criteria['sink_exists']['feedback'] = "✅ Reference_Headphones sink exists"
        feedback_parts.append("   ✅ Reference_Headphones sink exists")
    else:
        criteria['sink_exists']['feedback'] = "⚠️ Target sink not found in system"
        feedback_parts.append("   ⚠️ Warning: Target sink not found (setup issue?)")
    
    # Check 3: Audio routing (PRIMARY CHECK - 50%)
    feedback_parts.append("\n3. Audio Routing Check (PRIMARY):")
    if sink_correct and runtime_captured:
        criteria['audio_routing']['met'] = True
        criteria['audio_routing']['feedback'] = f"✅ Audio routed to: {audio_sink}"
        feedback_parts.append(f"   ✅ VLC audio correctly routed to: {audio_sink}")
    elif audio_sink and 'headphones' in audio_sink.lower():
        # Partial credit if sink name contains headphones
        criteria['audio_routing']['met'] = True
        criteria['audio_routing']['feedback'] = f"✅ Audio routed to: {audio_sink}"
        feedback_parts.append(f"   ✅ VLC audio routed to headphones sink: {audio_sink}")
    elif audio_sink:
        criteria['audio_routing']['feedback'] = f"❌ Audio routed to wrong sink: {audio_sink}"
        feedback_parts.append(f"   ❌ VLC audio routed to: {audio_sink}")
        feedback_parts.append(f"      Expected: reference_headphones or similar")
    else:
        criteria['audio_routing']['feedback'] = "❌ Could not determine audio routing"
        feedback_parts.append("   ❌ Could not determine VLC audio routing")
    
    # Check 4: Config persistence (25%)
    feedback_parts.append("\n4. Configuration Persistence Check:")
    config_has_device = bool(config_device and config_device.strip())
    config_mentions_headphones = 'headphones' in config_device.lower() if config_device else False
    
    if config_mentions_headphones:
        criteria['config_persisted']['met'] = True
        criteria['config_persisted']['feedback'] = f"✅ Config saved: {config_device}"
        feedback_parts.append(f"   ✅ VLC config persisted device: {config_device}")
    elif sink_correct and runtime_captured:
        # If runtime routing is correct but config isn't explicit, give partial credit
        # PulseAudio might remember the association
        criteria['config_persisted']['met'] = True
        criteria['config_persisted']['feedback'] = "✅ Device change applied (implicit config)"
        feedback_parts.append("   ✅ Device change applied (may be implicit)")
    elif config_has_device:
        criteria['config_persisted']['feedback'] = f"⚠️ Config has device but not headphones: {config_device}"
        feedback_parts.append(f"   ⚠️ Config shows: {config_device}")
    else:
        criteria['config_persisted']['feedback'] = "❌ Device not persisted in config"
        feedback_parts.append("   ❌ No explicit device setting in VLC config")
    
    # Check 5: No restart (10%)
    feedback_parts.append("\n5. Playback Continuity Check:")
    # Task should take at least 10 seconds (launch, navigate, change)
    # But less than 90 seconds (timeout)
    if vlc_uptime >= 8 and vlc_uptime <= 95:
        criteria['no_restart']['met'] = True
        criteria['no_restart']['feedback'] = f"✅ VLC uptime reasonable ({vlc_uptime}s)"
        feedback_parts.append(f"   ✅ VLC uptime: {vlc_uptime}s (no restart detected)")
    elif vlc_uptime > 0 and vlc_uptime < 8:
        criteria['no_restart']['feedback'] = f"❌ VLC uptime too short ({vlc_uptime}s)"
        feedback_parts.append(f"   ❌ VLC uptime too short ({vlc_uptime}s) - likely restarted")
    elif vlc_uptime > 95:
        criteria['no_restart']['feedback'] = f"⚠️ VLC uptime very long ({vlc_uptime}s)"
        feedback_parts.append(f"   ⚠️ VLC uptime unusually long ({vlc_uptime}s)")
    else:
        criteria['no_restart']['feedback'] = "❌ Could not verify uptime"
        feedback_parts.append("   ❌ Could not verify VLC uptime")
    
    # Check completion marker (not weighted, but good to have)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_audio_output_completed.txt", temp_marker.name)
        feedback_parts.append("\n6. Task Completion Marker: ✅")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("\n6. Task Completion Marker: ⚠️ Not found")
    
    # Calculate weighted score
    total_score = 0
    for criterion, data in criteria.items():
        if data['met']:
            total_score += data['weight']
    
    # Determine pass/fail
    passed = total_score >= 75
    
    # Build final feedback
    feedback_parts.append("\n" + "=" * 60)
    feedback_parts.append(f"Score: {total_score}/100")
    
    if passed:
        feedback_parts.append("✅ TASK SUCCESSFUL")
        feedback_parts.append("\nVLC successfully switched audio output to Reference_Headphones!")
    else:
        feedback_parts.append("❌ TASK FAILED")
        feedback_parts.append("\nTroubleshooting:")
        
        if not criteria['audio_routing']['met']:
            feedback_parts.append("  • Audio was not routed to Reference_Headphones")
            feedback_parts.append("  • Try: Audio menu → Audio Device → Reference_Headphones")
            feedback_parts.append("  • Or: Tools → Preferences → Show All → Audio → Output modules → PulseAudio")
        
        if not criteria['config_persisted']['met']:
            feedback_parts.append("  • Device change didn't persist in configuration")
            feedback_parts.append("  • Make sure to click 'Save' in Preferences")
        
        if not criteria['no_restart']['met']:
            feedback_parts.append("  • VLC may have been restarted during task")
            feedback_parts.append("  • Device should be changed while VLC is playing")
    
    feedback_parts.append("\nCriteria breakdown:")
    for criterion, data in criteria.items():
        status = "✅" if data['met'] else "❌"
        feedback_parts.append(f"  {status} {criterion}: {data['feedback']} ({data['weight']}pts)")
    
    feedback = "\n".join(feedback_parts)
    
    # Cleanup
    os.unlink(temp_result.name)
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback,
        "criteria": {k: v['met'] for k, v in criteria.items()}
    }
