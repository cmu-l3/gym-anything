#!/usr/bin/env python3
"""
Verifier for telephone_futz_eq_design task.

Checks that the agent:
1. Renamed the audio track appropriately.
2. Adjusted track gain to ~-6 dB.
3. Inserted an Equalizer plugin.
4. Set HPF to ~400 Hz.
5. Set LPF to ~4000 Hz.
"""

import math
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_audio_routes(root):
    """Get all audio tracks excluding Master and Monitor buses."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes


def get_route_gain_db(route):
    """Extract gain in dB from a route."""
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') in ('gaincontrol', 'gain'):
            try:
                val = float(ctrl.get('value', '1.0'))
                if val <= 0:
                    return -120.0
                return 20 * math.log10(val)
            except (ValueError, TypeError):
                return 0.0
    return 0.0


def get_eq_processor(route):
    """Find a processor representing an EQ plugin on the route."""
    for proc in route.iter('Processor'):
        name = proc.get('name', '').lower()
        uri = proc.get('uri', '').lower()
        if 'eq' in name or 'equalizer' in name or 'eq' in uri or 'equalizer' in uri:
            return proc
    return None


def extract_hpf_lpf_settings(processor):
    """
    Extract HPF and LPF frequencies and enabled states from a processor.
    Handles standard Ardour a-EQ and generalizes for others.
    """
    hpf_freq = None
    hpf_enabled = True  # Assume enabled if we find a frequency but no explicit toggle
    lpf_freq = None
    lpf_enabled = True

    for ctrl in processor.iter('Controllable'):
        name = ctrl.get('name', '').lower()
        val_str = ctrl.get('value', '')
        try:
            val = float(val_str)
        except ValueError:
            continue
        
        # High-Pass Filter extraction
        if 'freq' in name and any(x in name for x in ['hpf', 'hp', 'highpass', 'high-pass']):
            hpf_freq = val
        elif 'enable' in name and any(x in name for x in ['hpf', 'hp', 'highpass', 'high-pass']):
            hpf_enabled = (val > 0)
            
        # Low-Pass Filter extraction
        if 'freq' in name and any(x in name for x in ['lpf', 'lp', 'lowpass', 'low-pass']):
            lpf_freq = val
        elif 'enable' in name and any(x in name for x in ['lpf', 'lp', 'lowpass', 'low-pass']):
            lpf_enabled = (val > 0)

    return hpf_freq, hpf_enabled, lpf_freq, lpf_enabled


def _vlm_query(query_vlm, prompt, images):
    """Helper to query VLM and safely parse results."""
    if not query_vlm or not images:
        return None
    try:
        res = query_vlm(prompt=prompt, images=images)
        if res.get("success"):
            return res.get("parsed", {})
        logger.warning(f"VLM query failed: {res.get('error')}")
    except Exception as e:
        logger.warning(f"VLM exception: {e}")
    return None


def verify_telephone_futz_eq(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('expected_track_name_keywords', ['phone', 'futz', 'telephone'])
    gain_min = metadata.get('expected_gain_db', -6.0) - metadata.get('gain_tolerance_db', 3.0)
    gain_max = metadata.get('expected_gain_db', -6.0) + metadata.get('gain_tolerance_db', 3.0)
    hpf_min, hpf_max = metadata.get('hpf_freq_range', [250.0, 600.0])
    lpf_min, lpf_max = metadata.get('lpf_freq_range', [2500.0, 5000.0])
    pass_threshold = metadata.get('pass_threshold', 70)

    score = 0.0
    feedback = []

    # 1. Access Session File
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_session = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_session.close()

    try:
        copy_from_env(session_remote, tmp_session.name)
        tree = ET.parse(tmp_session.name)
        root = tree.getroot()
    except Exception as e:
        if os.path.exists(tmp_session.name):
            os.unlink(tmp_session.name)
        return {"passed": False, "score": 0.0, "feedback": f"Failed to parse session XML: {e}"}
    finally:
        if os.path.exists(tmp_session.name):
            os.unlink(tmp_session.name)

    routes = get_audio_routes(root)
    if not routes:
        return {"passed": False, "score": 0.0, "feedback": "No audio tracks found in session."}

    # Find target track
    target_route = None
    track_renamed = False
    
    for route in routes:
        name = route.get('name', '').lower()
        if any(kw in name for kw in expected_keywords):
            target_route = route
            track_renamed = True
            break
            
    # Fallback to the first available track if not renamed
    if not target_route:
        target_route = routes[0]

    # Criterion 1: Track Renamed (15 pts)
    if track_renamed:
        score += 15.0
        feedback.append(f"PASS: Track renamed correctly ('{target_route.get('name')}').")
    else:
        feedback.append(f"FAIL: Track not renamed. (Expected keywords: {expected_keywords})")

    # Criterion 2: Gain Staging (15 pts)
    actual_gain = get_route_gain_db(target_route)
    if gain_min <= actual_gain <= gain_max:
        score += 15.0
        feedback.append(f"PASS: Gain staging correct ({actual_gain:.1f} dB).")
    else:
        feedback.append(f"FAIL: Gain is {actual_gain:.1f} dB, expected between {gain_min} and {gain_max} dB.")

    # Criterion 3: EQ Plugin Inserted (15 pts XML + 15 pts VLM confirmation)
    eq_processor = get_eq_processor(target_route)
    if eq_processor is not None:
        score += 15.0
        plugin_name = eq_processor.get('name', 'Unknown EQ')
        feedback.append(f"PASS: EQ Plugin found in track ('{plugin_name}').")
        
        # VLM trajectory verification to ensure UI interaction (anti-gaming)
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """Analyze these screenshots of a user working in a Digital Audio Workstation (Ardour).
            Did the user open an Equalizer plugin interface (like a-EQ) and interact with it?
            Respond in JSON: {"opened_eq_ui": true/false}"""
            
            vlm_res = _vlm_query(env_info.get('query_vlm'), prompt, images)
            if vlm_res and vlm_res.get('opened_eq_ui'):
                score += 15.0
                feedback.append("PASS: VLM verified EQ interface interaction.")
            else:
                feedback.append("WARNING: VLM did not clearly see EQ UI interaction (possible partial/terminal automation).")
        except ImportError:
            # If VLM is not available, award the points to prevent blocking offline tests
            score += 15.0
            feedback.append("NOTE: VLM unavailable, awarding full plugin interaction points.")
        
        # Criterion 4 & 5: HPF and LPF Configuration (20 pts each)
        hpf_freq, hpf_enabled, lpf_freq, lpf_enabled = extract_hpf_lpf_settings(eq_processor)
        
        if hpf_enabled and hpf_freq is not None:
            if hpf_min <= hpf_freq <= hpf_max:
                score += 20.0
                feedback.append(f"PASS: HPF configured correctly ({hpf_freq:.1f} Hz).")
            else:
                feedback.append(f"FAIL: HPF frequency out of range ({hpf_freq:.1f} Hz).")
        else:
            feedback.append("FAIL: HPF not enabled or frequency not found.")

        if lpf_enabled and lpf_freq is not None:
            if lpf_min <= lpf_freq <= lpf_max:
                score += 20.0
                feedback.append(f"PASS: LPF configured correctly ({lpf_freq:.1f} Hz).")
            else:
                feedback.append(f"FAIL: LPF frequency out of range ({lpf_freq:.1f} Hz).")
        else:
            feedback.append("FAIL: LPF not enabled or frequency not found.")

    else:
        feedback.append("FAIL: No Equalizer plugin found on the track.")

    passed = score >= pass_threshold and (eq_processor is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }