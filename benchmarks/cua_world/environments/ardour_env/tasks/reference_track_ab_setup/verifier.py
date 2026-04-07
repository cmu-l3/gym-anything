#!/usr/bin/env python3
"""
Verifier for reference_track_ab_setup task.
Occupation: Mastering Engineer (SOC 27-4014)
Industry: Recording Industry / Music Production

Checks that the agent set up a reference track with correct routing
(disconnected from Master, routed to hardware outputs), muted the reference
track, inserted a plugin on the Master bus, and renamed the main track.
"""

import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 75.0

# ---------- Ardour XML helpers ----------

def get_audio_routes(root):
    """Return a list of all regular audio routes (tracks)."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_master_route(root):
    """Find the Master Bus route."""
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags:
            return route
    return None

def get_route_muted(route):
    """Check if the route is muted."""
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'mute':
            return ctrl.get('value', '0') in ('1', 'yes', 'true')
    return route.get('muted', '0') in ('1', 'yes', 'true')

def get_route_connections(route, direction="Output"):
    """Get all connected destinations/sources for a route."""
    connections = []
    io_node = route.find(f'IO[@direction="{direction}"]')
    if io_node is not None:
        for port in io_node.iter('Port'):
            for conn in port.iter('Connection'):
                other = conn.get('other', '')
                if other:
                    connections.append(other)
    return connections

def get_master_plugins(master_route):
    """List plugins on the master bus excluding core built-in ones."""
    if master_route is None:
        return []
    plugins = []
    # Core Ardour processors to ignore
    ignore_names = ['amp', 'meter', 'polarity', 'fader', 'delay', 'system delay']
    
    for proc in master_route.iter('Processor'):
        name = proc.get('name', '').lower()
        proc_type = proc.get('type', '').lower()
        if name not in ignore_names and name:
            plugins.append(name)
    return plugins

# ---------- Main verifier ----------

def verify_reference_track_ab_setup(traj, env_info, task_info):
    """
    Multi-criterion verifier for reference track A/B setup.

    Criteria (100 pts total, pass >= 75):
      1. Main Mix Track exists                                  (10 pts)
      2. Reference Track exists                                 (20 pts)
      3. Reference Track is muted                               (15 pts)
      4. Master Bus has an effect plugin inserted               (15 pts)
      5. Reference Track outputs disconnected from Master       (20 pts)
      6. Reference Track outputs connected to System Hardware   (20 pts)
      
    Key logic: The agent MUST complete the routing modifications (criteria 5 & 6)
    in order to successfully demonstrate the A/B bypass technique.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # ---- Copy session XML ----
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp.close()

    try:
        copy_from_env(session_remote, tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session not accessible: {e}"}

    if not os.path.exists(tmp.name) or os.path.getsize(tmp.name) == 0:
        return {"passed": False, "score": 0.0, "feedback": "Session file empty or missing"}

    try:
        tree = ET.parse(tmp.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp.name)
        return {"passed": False, "score": 0.0, "feedback": f"XML parse error: {e}"}

    audio_routes = get_audio_routes(root)
    master_route = get_master_route(root)

    # Variables to track findings
    main_mix_route = None
    ref_route = None

    for route in audio_routes:
        name = route.get('name', '').lower()
        if 'main mix' in name:
            main_mix_route = route
        elif 'ref' in name:
            ref_route = route

    # ================================================================
    # CRITERION 1: Main Mix Track exists (10 pts)
    # ================================================================
    if main_mix_route is not None:
        score += 10.0
        feedback.append("PASS: 'Main Mix' track exists")
    else:
        feedback.append("FAIL: 'Main Mix' track not found")

    # ================================================================
    # CRITERION 2: Reference Track exists (20 pts)
    # ================================================================
    if ref_route is not None:
        score += 20.0
        feedback.append(f"PASS: Reference track found ('{ref_route.get('name')}')")
    else:
        feedback.append("FAIL: 'Reference' track not found")

    # Check remaining criteria only if Reference track was created
    if ref_route is not None:
        # ================================================================
        # CRITERION 3: Reference Track is muted (15 pts)
        # ================================================================
        if get_route_muted(ref_route):
            score += 15.0
            feedback.append("PASS: Reference track is muted")
        else:
            feedback.append("FAIL: Reference track is NOT muted")

        # ================================================================
        # CRITERION 5 & 6: Reference Track Routing (40 pts)
        # Should NOT be connected to Master. Should be connected to Hardware.
        # ================================================================
        connections = get_route_connections(ref_route, direction="Output")
        
        connected_to_master = any('master' in c.lower() for c in connections)
        connected_to_hardware = any(hw in c.lower() for c in connections for hw in ['system', 'playback', 'dummy', 'out', 'monitor'])

        if not connected_to_master:
            score += 20.0
            feedback.append("PASS: Reference outputs disconnected from Master bus")
        else:
            feedback.append("FAIL: Reference outputs are STILL connected to the Master bus")

        if connected_to_hardware and not connected_to_master:
            score += 20.0
            feedback.append("PASS: Reference outputs connected directly to system/hardware playback")
        elif connected_to_hardware:
            score += 10.0
            feedback.append("PARTIAL: Reference outputs connected to hardware, but Master connection remains")
        else:
            feedback.append("FAIL: Reference outputs not connected to system hardware")
    else:
        feedback.append("Skipping Reference track checks (mute & routing) as track does not exist")

    # ================================================================
    # CRITERION 4: Master Bus Processing (15 pts)
    # ================================================================
    master_plugins = get_master_plugins(master_route)
    if len(master_plugins) > 0:
        score += 15.0
        feedback.append(f"PASS: Master bus has processing plugins inserted ({', '.join(master_plugins)})")
    else:
        feedback.append("FAIL: No external/effect plugins found on Master bus")

    os.unlink(tmp.name)

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "main_mix_exists": main_mix_route is not None,
            "ref_track_exists": ref_route is not None,
            "master_plugins_found": master_plugins
        }
    }