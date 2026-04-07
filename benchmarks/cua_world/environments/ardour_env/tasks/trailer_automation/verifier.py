#!/usr/bin/env python3
"""
Verifier for trailer_automation@1 task.
Parses the Ardour session XML to check track name, gain/pan automation, and automation mode.
Uses copy_from_env to safely retrieve files from the container.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_automation_events(events_text):
    """Parse automation events from text format: 'time value\\ntime value\\n...'"""
    events = []
    if not events_text or not events_text.strip():
        return events
    for line in events_text.strip().split('\n'):
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) >= 2:
            try:
                time_val = float(parts[0])
                value = float(parts[1])
                events.append((time_val, value))
            except ValueError:
                continue
    return events


def find_audio_routes(root):
    """Find all audio routes (excluding Master, Monitor buses)."""
    routes = []
    for route in root.iter('Route'):
        name = route.get('name', '')
        default_type = route.get('default-type', '')
        # Skip master and monitor buses
        if name.lower() in ('master', 'monitor'):
            continue
        # Check if it's an audio track
        if default_type == 'audio' or route.find('.//Diskstream') is not None:
            routes.append(route)
    # Also check Track elements (some Ardour versions use <Track> instead of <Route>)
    for track in root.iter('Track'):
        name = track.get('name', '')
        if name.lower() not in ('master', 'monitor'):
            routes.append(track)
    return routes


def get_gain_automation(route):
    """Extract gain automation events and state from a route."""
    # Look for amp processor's gaincontrol automation
    for processor in route.iter('Processor'):
        if processor.get('type') == 'amp' or 'Amp' in processor.get('name', ''):
            for controllable in processor.iter('Controllable'):
                if 'gain' in controllable.get('name', '').lower():
                    for auto_list in controllable.iter('AutomationList'):
                        state = auto_list.get('state', 'Off')
                        events_elem = auto_list.find('events')
                        events_text = events_elem.text if events_elem is not None else ''
                        events = parse_automation_events(events_text)
                        return events, state

    # Fallback: search for any AutomationList with gain-related automation-id
    for auto_list in route.iter('AutomationList'):
        auto_id = auto_list.get('automation-id', '')
        if 'gain' in auto_id.lower() or auto_id == 'parameter-16':
            state = auto_list.get('state', 'Off')
            events_elem = auto_list.find('events')
            events_text = events_elem.text if events_elem is not None else ''
            events = parse_automation_events(events_text)
            return events, state

    return [], 'Off'


def get_pan_automation(route):
    """Extract pan automation events and state from a route."""
    # Look in Pannable section
    for pannable in route.iter('Pannable'):
        for auto_list in pannable.iter('AutomationList'):
            state = auto_list.get('state', 'Off')
            events_elem = auto_list.find('events')
            events_text = events_elem.text if events_elem is not None else ''
            events = parse_automation_events(events_text)
            if events:
                return events, state

    # Fallback: search for pan-related automation-id
    for auto_list in route.iter('AutomationList'):
        auto_id = auto_list.get('automation-id', '')
        if 'pan' in auto_id.lower() or 'azimuth' in auto_id.lower():
            state = auto_list.get('state', 'Off')
            events_elem = auto_list.find('events')
            events_text = events_elem.text if events_elem is not None else ''
            events = parse_automation_events(events_text)
            if events:
                return events, state

    return [], 'Off'


def check_gain_shape(events):
    """
    Check if gain automation has fade-in / sustain / fade-out shape.
    Returns (shape_ok, details_str)
    """
    if len(events) < 4:
        return False, f"Need at least 4 events, got {len(events)}"

    events_sorted = sorted(events, key=lambda e: e[0])

    first_val = events_sorted[0][1]
    if first_val > 0.15:
        return False, f"First event value {first_val:.3f} > 0.15 (not starting quiet)"

    last_val = events_sorted[-1][1]
    if last_val > 0.15:
        return False, f"Last event value {last_val:.3f} > 0.15 (not ending quiet)"

    middle_events = events_sorted[1:-1]
    max_middle = max(e[1] for e in middle_events) if middle_events else 0
    if max_middle < 0.7:
        return False, f"Max middle value {max_middle:.3f} < 0.7 (no loud sustain section)"

    # Check temporal shape: goes low -> high -> low
    first_high_idx = None
    last_high_idx = None
    for i, (t, v) in enumerate(events_sorted):
        if v >= 0.7:
            if first_high_idx is None:
                first_high_idx = i
            last_high_idx = i

    if first_high_idx is None:
        return False, "No high-value events found"

    if first_high_idx < 1:
        return False, "High value too early (no fade-in)"
    if last_high_idx >= len(events_sorted) - 1:
        return False, "High value at end (no fade-out)"

    return True, "Fade-in/sustain/fade-out shape verified"


def check_pan_sweep(events):
    """
    Check if pan automation sweeps left to right.
    Returns (sweep_ok, details_str)
    """
    if len(events) < 3:
        return False, f"Need at least 3 events, got {len(events)}"

    events_sorted = sorted(events, key=lambda e: e[0])

    first_val = events_sorted[0][1]
    last_val = events_sorted[-1][1]

    if first_val > 0.35:
        return False, f"First pan value {first_val:.3f} > 0.35 (not starting left)"

    if last_val < 0.65:
        return False, f"Last pan value {last_val:.3f} < 0.65 (not ending right)"

    tolerance = 0.05
    for i in range(1, len(events_sorted)):
        if events_sorted[i][1] < events_sorted[i-1][1] - tolerance:
            return False, (
                f"Pan not monotonically increasing: "
                f"event {i-1} val={events_sorted[i-1][1]:.3f} > "
                f"event {i} val={events_sorted[i][1]:.3f}"
            )

    return True, "Left-to-right pan sweep verified"


def verify_trailer_automation(traj, env_info, task_info):
    """
    Verify the cinematic trailer automation task.
    Uses copy_from_env to read results and parse the Ardour session XML.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_session_file = metadata.get('expected_session_file', '/home/ga/Audio/sessions/MyProject/MyProject.ardour')

    score = 0
    feedback_parts = []
    
    # --- 1. Copy result JSON to check timestamps ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load export result JSON: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check anti-gaming timestamp
    session_modified = result_data.get('session_modified_during_task', False)
    if not session_modified:
        feedback_parts.append("WARNING: Session file was not modified after task start. Did you save the session?")
    else:
        feedback_parts.append("Session was modified (saved) during task.")

    # --- 2. Copy the Ardour session XML ---
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    try:
        copy_from_env(expected_session_file, temp_xml.name)
        if not os.path.exists(temp_xml.name) or os.path.getsize(temp_xml.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Session file could not be retrieved or is empty."}

        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse session XML: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # --- 3. Evaluate criteria based on XML ---
    routes = find_audio_routes(root)
    if not routes:
        return {"passed": False, "score": 0, "feedback": "No audio routes found in session"}

    # Criterion 1: Track renamed (15 pts)
    score_rename = 0
    target_route = routes[0] # Default to first audio route
    
    for route in routes:
        name = route.get('name', '')
        name_lower = name.lower()
        if 'trailer' in name_lower and 'score' in name_lower:
            score_rename = 15
            target_route = route
            feedback_parts.append(f"Track renamed correctly to '{name}'")
            break
        elif name_lower not in ('audio 1', 'audio', 'audio 2', ''):
            if score_rename < 7:
                score_rename = 7
                target_route = route
                feedback_parts.append(f"Track renamed to '{name}' (partial credit)")
    
    if score_rename == 0:
        feedback_parts.append(f"Track not renamed (remained '{target_route.get('name', 'unknown')}')")
    
    score += score_rename

    # Find the best automation across routes (in case agent used a different track)
    best_gain_events, best_gain_state = [], 'Off'
    best_pan_events, best_pan_state = [], 'Off'
    
    for route in routes:
        ge, gs = get_gain_automation(route)
        if len(ge) > len(best_gain_events):
            best_gain_events, best_gain_state = ge, gs
            
        pe, ps = get_pan_automation(route)
        if len(pe) > len(best_pan_events):
            best_pan_events, best_pan_state = pe, ps

    # Criterion 2: Gain automation exists (15 pts)
    if len(best_gain_events) >= 4:
        score += 15
        feedback_parts.append(f"Gain automation exists ({len(best_gain_events)} pts)")
    elif len(best_gain_events) >= 2:
        score += 7
        feedback_parts.append(f"Gain automation partial ({len(best_gain_events)} pts)")
    else:
        feedback_parts.append("Gain automation insufficient/missing")

    # Criterion 3: Gain automation shape (25 pts)
    if best_gain_events:
        shape_ok, shape_detail = check_gain_shape(best_gain_events)
        if shape_ok:
            score += 25
            feedback_parts.append("Gain envelope shape correct")
        else:
            # Partial credit logic
            if len(best_gain_events) >= 3:
                events_sorted = sorted(best_gain_events, key=lambda e: e[0])
                has_low_start = events_sorted[0][1] <= 0.2
                has_high_mid = any(e[1] >= 0.5 for e in events_sorted[1:-1]) if len(events_sorted) > 2 else False
                has_low_end = events_sorted[-1][1] <= 0.2
                partial = sum([has_low_start, has_high_mid, has_low_end])
                partial_score = int(25 * partial / 3 * 0.6)
                score += partial_score
                feedback_parts.append(f"Gain shape partial: {shape_detail}")
            else:
                feedback_parts.append(f"Gain shape issue: {shape_detail}")
    
    # Criterion 4: Pan automation exists (15 pts)
    if len(best_pan_events) >= 3:
        score += 15
        feedback_parts.append(f"Pan automation exists ({len(best_pan_events)} pts)")
    elif len(best_pan_events) >= 2:
        score += 7
        feedback_parts.append(f"Pan automation partial ({len(best_pan_events)} pts)")
    else:
        feedback_parts.append("Pan automation insufficient/missing")

    # Criterion 5: Pan automation sweep (15 pts)
    if best_pan_events:
        sweep_ok, sweep_detail = check_pan_sweep(best_pan_events)
        if sweep_ok:
            score += 15
            feedback_parts.append("Pan sweep shape correct")
        else:
            # Partial credit
            events_sorted = sorted(best_pan_events, key=lambda e: e[0])
            starts_left = events_sorted[0][1] <= 0.4
            ends_right = events_sorted[-1][1] >= 0.6
            if starts_left and ends_right:
                score += 8
                feedback_parts.append("Pan sweep partial (endpoints ok)")
            elif starts_left or ends_right:
                score += 4
                feedback_parts.append("Pan sweep partial (one endpoint ok)")
            else:
                feedback_parts.append(f"Pan sweep issue: {sweep_detail}")
    
    # Criterion 6: Automation Play mode (15 pts)
    gain_play = best_gain_state.lower() in ('play', '1')
    if gain_play:
        score += 7.5
        feedback_parts.append("Gain mode: Play")
    else:
        feedback_parts.append(f"Gain mode NOT Play (was {best_gain_state})")

    pan_play = best_pan_state.lower() in ('play', '1')
    if pan_play:
        score += 7.5
        feedback_parts.append("Pan mode: Play")
    elif best_pan_state.lower() in ('touch', 'write', 'latch', '2', '3', '4'):
        score += 3
        feedback_parts.append(f"Pan mode active but not Play (was {best_pan_state})")
    else:
        feedback_parts.append(f"Pan mode NOT Play (was {best_pan_state})")

    # Anti-gaming: Ensure it was saved (if it wasn't modified during task, max score is capped)
    if not session_modified and score > 20:
        logger.warning("Session wasn't modified after task start! Capping score due to missing save.")
        score = 20
        feedback_parts.append("SCORE CAPPED: Session was not saved after task start.")

    passed = score >= 55

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }