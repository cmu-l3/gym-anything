#!/usr/bin/env python3
"""
Verifier for Remove Vocals for Karaoke task
"""

import sys
import os
import logging
import tempfile
import json

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vlcrc_to_dict(vlcrc_content: str) -> dict:
    """
    Parse VLC config file content to dictionary.
    
    Args:
        vlcrc_content: Content of vlcrc file
        
    Returns:
        Dict of config key-value pairs
    """
    config = {}
    
    for line in vlcrc_content.split('\n'):
        line = line.strip()
        
        # Skip comments, empty lines, and section headers
        if not line or line.startswith('#') or line.startswith('['):
            continue
        
        # Parse key=value
        if '=' in line:
            key, value = line.split('=', 1)
            config[key.strip()] = value.strip()
    
    return config


def verify_remove_vocals_karaoke(traj, env_info, task_info):
    """
    Verify remove vocals for karaoke task completion.
    
    Checks:
    1. VLC config file is accessible
    2. Appropriate audio filter is enabled
    3. Filter configuration is suitable for vocal removal
    
    Scoring:
    - Karaoke/vocal removal filter: 1.0 (perfect)
    - Stereo widener (center < -0.3): 0.90 (excellent)
    - Spatializer: 0.85 (very good)
    - Equalizer (mid-freq < -4dB): 0.75 (good)
    - Partially correct: 0.1-0.3
    - No filters: 0.0
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy JSON result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_karaoke_result.json", temp_result.name)
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        config_found = result.get('config_found', False)
        
        if not config_found:
            os.unlink(temp_result.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ VLC config file not found. Task may not have run or VLC didn't save config."
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Config accessible")
        
        # Get audio filter settings
        audio_filter = result.get('audio_filter', '').lower()
        
        if not audio_filter or audio_filter == '':
            os.unlink(temp_result.name)
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": "❌ No audio filters enabled. Need to enable vocal removal filter via Tools → Effects and Filters → Audio Effects."
            }
        
        criteria_met += 1
        feedback_parts.append(f"✅ Audio filter enabled: '{audio_filter}'")
        
        # Check filter type and configuration for vocal removal suitability
        score_multiplier = 0.0
        config_feedback = ""
        
        # OPTION A: Dedicated karaoke/vocal-removal filter (best)
        karaoke_keywords = ['karaoke', 'vocal-remove', 'voice-removal', 'center-channel']
        if any(keyword in audio_filter for keyword in karaoke_keywords):
            score_multiplier = 1.0
            config_feedback = f"✅ Karaoke/vocal removal filter enabled (score: 1.0)"
            criteria_met += 1
        
        # OPTION B: Spatializer effect (good alternative)
        elif 'spatializer' in audio_filter:
            score_multiplier = 0.85
            config_feedback = "✅ Spatializer audio effect enabled (reduces center-channel vocals) (score: 0.85)"
            criteria_met += 1
        
        # OPTION C: Stereo widener with center reduction
        elif 'stereo' in audio_filter or 'widener' in audio_filter:
            widener_mix = result.get('stereo_widener_mix', '0')
            
            try:
                mix_value = float(widener_mix)
                
                if mix_value < -0.3:  # Significant center reduction
                    score_multiplier = 0.90
                    config_feedback = f"✅ Stereo widener configured for center-channel reduction (mix={mix_value:.2f}) (score: 0.90)"
                    criteria_met += 1
                else:
                    score_multiplier = 0.3
                    config_feedback = f"⚠️ Stereo widener enabled but not configured for vocal removal. Current mix={mix_value:.2f}, need mix < -0.3 to reduce center channel."
            except (ValueError, TypeError):
                score_multiplier = 0.2
                config_feedback = f"⚠️ Stereo widener enabled but mix parameter is invalid: '{widener_mix}'"
        
        # OPTION D: Equalizer with mid-frequency reduction
        elif 'equalizer' in audio_filter or 'param-eq' in audio_filter:
            eq_bands = result.get('equalizer_bands', '')
            
            if eq_bands:
                try:
                    # Parse equalizer bands (typically 10 bands)
                    bands = [float(b) for b in eq_bands.split()]
                    
                    if len(bands) >= 7:
                        # Check mid-frequencies (bands 2-6, roughly 200Hz-5kHz where vocals sit)
                        mid_freq_avg = sum(bands[2:7]) / 5
                        
                        if mid_freq_avg < -4.0:  # Significant reduction (at least -4dB)
                            score_multiplier = 0.75
                            config_feedback = f"✅ Equalizer configured with mid-frequency reduction for vocal suppression (avg={mid_freq_avg:.1f}dB) (score: 0.75)"
                            criteria_met += 1
                        else:
                            score_multiplier = 0.25
                            config_feedback = f"⚠️ Equalizer enabled but insufficient vocal frequency reduction. Mid-freq avg={mid_freq_avg:.1f}dB (need < -4dB)."
                    else:
                        score_multiplier = 0.15
                        config_feedback = f"⚠️ Equalizer enabled but not enough bands configured ({len(bands)} bands)"
                
                except (ValueError, IndexError) as e:
                    score_multiplier = 0.15
                    config_feedback = f"⚠️ Equalizer enabled but bands are improperly configured: {e}"
            else:
                score_multiplier = 0.1
                config_feedback = "⚠️ Equalizer enabled but no custom bands configured for vocal removal."
        
        # Other audio filter (not appropriate for vocal removal)
        else:
            score_multiplier = 0.1
            config_feedback = f"⚠️ Audio filter enabled ('{audio_filter}') but it's not configured for vocal removal. Try Spatializer, Stereo Widener, or Equalizer."
        
        feedback_parts.append(config_feedback)
        
        os.unlink(temp_result.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Error reading karaoke result: {str(e)}"
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_karaoke_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate final score based on criteria met and score multiplier
    # Base score from criteria (0-100), then apply multiplier for filter quality
    base_score = int((criteria_met / total_criteria) * 100)
    final_score = int(base_score * score_multiplier)
    
    # Ensure minimum score if any filter is enabled
    if criteria_met >= 2 and final_score < 10:
        final_score = 10
    
    passed = final_score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": feedback
    }