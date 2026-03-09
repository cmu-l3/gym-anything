#!/usr/bin/env python3
"""
Verifier for Isolate Bass Frequencies task

This verifier checks that the VLC equalizer has been configured to isolate
bass frequencies by boosting low frequencies and reducing mid frequencies.
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_equalizer_bands(bands_str):
    """
    Parse VLC equalizer bands string into list of float values.
    
    VLC format: "10.000000 8.000000 4.000000 -4.000000 -5.000000 -4.000000 0.000000 0.000000 0.000000 0.000000"
    
    Returns list of 10 floats representing dB values for each frequency band.
    Bands correspond to: [60Hz, 170Hz, 310Hz, 600Hz, 1kHz, 3kHz, 6kHz, 12kHz, 14kHz, 16kHz]
    """
    try:
        # Handle both space-separated and other formats
        bands_str = bands_str.strip().strip('"').strip("'")
        parts = bands_str.split()
        
        # Convert to floats
        bands = [float(x) for x in parts]
        
        if len(bands) != 10:
            logger.warning(f"Expected 10 equalizer bands, got {len(bands)}")
            # Pad or truncate to 10 bands
            if len(bands) < 10:
                bands.extend([0.0] * (10 - len(bands)))
            else:
                bands = bands[:10]
        
        return bands
    except Exception as e:
        logger.error(f"Error parsing equalizer bands: {e}")
        return [0.0] * 10


def verify_bass_isolation_pattern(bands):
    """
    Verify that the equalizer bands show a bass isolation pattern.
    
    Args:
        bands: List of 10 float values (dB) for each frequency band
        
    Returns:
        dict with score components and feedback
    """
    result = {
        'bass_boost_score': 0,
        'mid_reduction_score': 0,
        'pattern_score': 0,
        'feedback_parts': []
    }
    
    # Extract bass bands (0-2: 60Hz, 170Hz, 310Hz)
    bass_bands = bands[0:3]
    
    # Extract mid bands (3-5: 600Hz, 1kHz, 3kHz)
    mid_bands = bands[3:6]
    
    # Criterion 1: Bass Boost
    # Check if bass frequencies are boosted significantly
    bass_boost_count = sum(1 for b in bass_bands if b >= 6.0)
    avg_bass = sum(bass_bands) / len(bass_bands)
    
    if bass_boost_count == 3 and avg_bass >= 8.0:
        result['bass_boost_score'] = 50  # Excellent bass boost
        result['feedback_parts'].append(f"✅ Excellent bass boost (avg: {avg_bass:.1f} dB)")
    elif bass_boost_count >= 2 and avg_bass >= 6.0:
        result['bass_boost_score'] = 40  # Good bass boost
        result['feedback_parts'].append(f"✅ Good bass boost (avg: {avg_bass:.1f} dB)")
    elif bass_boost_count >= 2 and avg_bass >= 4.0:
        result['bass_boost_score'] = 30  # Moderate bass boost
        result['feedback_parts'].append(f"⚠️ Moderate bass boost (avg: {avg_bass:.1f} dB)")
    elif any(b >= 3.0 for b in bass_bands):
        result['bass_boost_score'] = 20  # Minimal bass boost
        result['feedback_parts'].append(f"⚠️ Minimal bass boost (avg: {avg_bass:.1f} dB)")
    else:
        result['feedback_parts'].append(f"❌ Bass not boosted (avg: {avg_bass:.1f} dB)")
    
    # Criterion 2: Mid Reduction
    # Check if mid frequencies are reduced
    mid_reduction_count = sum(1 for m in mid_bands if m < 0)
    avg_mid = sum(mid_bands) / len(mid_bands)
    
    if mid_reduction_count >= 3 and avg_mid <= -3.0:
        result['mid_reduction_score'] = 30  # Excellent mid reduction
        result['feedback_parts'].append(f"✅ Excellent mid reduction (avg: {avg_mid:.1f} dB)")
    elif mid_reduction_count >= 2 and avg_mid <= -2.0:
        result['mid_reduction_score'] = 25  # Good mid reduction
        result['feedback_parts'].append(f"✅ Good mid reduction (avg: {avg_mid:.1f} dB)")
    elif mid_reduction_count >= 2 and avg_mid <= -1.0:
        result['mid_reduction_score'] = 20  # Moderate mid reduction
        result['feedback_parts'].append(f"⚠️ Moderate mid reduction (avg: {avg_mid:.1f} dB)")
    elif mid_reduction_count >= 1:
        result['mid_reduction_score'] = 10  # Minimal mid reduction
        result['feedback_parts'].append(f"⚠️ Minimal mid reduction (avg: {avg_mid:.1f} dB)")
    else:
        result['feedback_parts'].append(f"❌ Mids not reduced (avg: {avg_mid:.1f} dB)")
    
    # Criterion 3: Overall Pattern
    # Check that bass is significantly higher than mids (separation)
    separation = avg_bass - avg_mid
    
    if separation >= 12.0:
        result['pattern_score'] = 20  # Excellent separation
        result['feedback_parts'].append(f"✅ Excellent bass/mid separation ({separation:.1f} dB)")
    elif separation >= 8.0:
        result['pattern_score'] = 15  # Good separation
        result['feedback_parts'].append(f"✅ Good bass/mid separation ({separation:.1f} dB)")
    elif separation >= 4.0:
        result['pattern_score'] = 10  # Moderate separation
        result['feedback_parts'].append(f"⚠️ Moderate bass/mid separation ({separation:.1f} dB)")
    elif separation >= 2.0:
        result['pattern_score'] = 5  # Minimal separation
        result['feedback_parts'].append(f"⚠️ Minimal bass/mid separation ({separation:.1f} dB)")
    else:
        result['feedback_parts'].append(f"❌ Insufficient separation ({separation:.1f} dB)")
    
    return result


def verify_isolate_bass_frequencies(traj, env_info, task_info):
    """
    Verify isolate bass frequencies task completion.
    
    Checks:
    1. Equalizer is enabled (config file contains equalizer-preamp)
    2. Bass frequencies (60Hz, 170Hz, 310Hz) are boosted (≥+6 dB)
    3. Mid frequencies (600Hz, 1kHz, 3kHz) are reduced (negative dB)
    4. Overall pattern shows bass isolation (bass >> mids)
    
    Scoring:
    - Equalizer enabled: 10 points (baseline)
    - Bass boost quality: 0-50 points
    - Mid reduction quality: 0-30 points
    - Pattern/separation: 0-20 points
    Total: 110 points possible, normalized to 100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    total_score = 0
    feedback_parts = []
    
    # Copy equalizer result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_bass_eq_result.json", temp_result.name)
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        eq_enabled = result.get('eq_enabled', False)
        eq_bands_str = result.get('eq_bands', 'not_set')
        eq_preamp = result.get('eq_preamp', 'not_set')
        
        # Criterion 1: Equalizer must be enabled
        if not eq_enabled or eq_bands_str == 'not_set':
            os.unlink(temp_result.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Equalizer not enabled or not configured"
            }
        
        total_score += 10  # Base score for enabling equalizer
        feedback_parts.append("✅ Equalizer enabled")
        
        # Parse equalizer bands
        bands = parse_equalizer_bands(eq_bands_str)
        
        # Log the bands for debugging
        logger.info(f"Equalizer bands: {bands}")
        feedback_parts.append(f"Bands: [{', '.join(f'{b:.1f}' for b in bands[:6])}...]")
        
        # Verify bass isolation pattern
        pattern_result = verify_bass_isolation_pattern(bands)
        
        total_score += pattern_result['bass_boost_score']
        total_score += pattern_result['mid_reduction_score']
        total_score += pattern_result['pattern_score']
        
        feedback_parts.extend(pattern_result['feedback_parts'])
        
        os.unlink(temp_result.name)
        
    except FileNotFoundError:
        logger.error("Equalizer result file not found")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Equalizer result file not found - task may not have run"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Error reading equalizer result: {str(e)}"
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_bass_eq_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Normalize score to 0-100 range (from 0-110)
    normalized_score = min(100, int((total_score / 110.0) * 100))
    
    # Determine pass/fail (70% threshold)
    passed = normalized_score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": normalized_score,
        "feedback": feedback,
        "details": {
            "total_raw_score": total_score,
            "max_possible": 110
        }
    }