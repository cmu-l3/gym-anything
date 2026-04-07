#!/usr/bin/env python3
"""
Verifier for dialogue_checkerboarding_assembly task.
Occupation: Dialogue Editor / Sound Editor
Industry: Motion Picture and Video Production
"""

import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_name(name):
    """Normalize names for flexible matching."""
    return name.lower().replace(" ", "").replace("_", "")

def get_route_by_name(root, target_name):
    """Find a route by fuzzy name matching."""
    target = normalize_name(target_name)
    for route in root.iter('Route'):
        name = normalize_name(route.get('name', ''))
        if target in name:
            return route
    return None

def is_routed_to(route, target_bus_name):
    """Check if the route output is connected to the target bus."""
    if route is None:
        return False
    target = normalize_name(target_bus_name)
    for output in route.iter('Output'):
        for conn in output.iter('Connection'):
            other = normalize_name(conn.get('other', ''))
            if target in other:
                return True
    return False

def get_regions_for_track(root, track_name):
    """Get region positions for a given track name."""
    target = normalize_name(track_name)
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = normalize_name(playlist.get('name', ''))
        if pl_name.startswith(target):
            for region in playlist.iter('Region'):
                try:
                    regions.append(int(region.get('position', '0')))
                except ValueError:
                    pass
    return sorted(regions)

def verify_dialogue_checkerboarding(traj, env_info, task_info):
    """
    Evaluates:
    1. Track & Bus Setup (15)
    2. Dialogue Bus Routing (20)
    3. Playlist Distribution A (15)
    4. Playlist Distribution B (15)
    5. Timeline Synchronization (25)
    6. Source Track Cleanup (10)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback = []

    # Get session XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to parse Ardour session XML: {e}"}

    # 1. Track & Bus Setup (15)
    char_a_route = get_route_by_name(root, "Character A")
    char_b_route = get_route_by_name(root, "Character B")
    dia_bus_route = get_route_by_name(root, "Dia Bus")

    setup_score = sum([5 for r in (char_a_route, char_b_route, dia_bus_route) if r is not None])
    score += setup_score
    if setup_score == 15:
        feedback.append("PASS: All required tracks and bus created.")
    else:
        feedback.append(f"PARTIAL: Missing some tracks/buses (Score: {setup_score}/15).")

    # 2. Routing (20)
    routes_connected = 0
    if is_routed_to(char_a_route, "Dia Bus"):
        routes_connected += 10
    if is_routed_to(char_b_route, "Dia Bus"):
        routes_connected += 10

    score += routes_connected
    if routes_connected == 20:
        feedback.append("PASS: Characters routed to Dia Bus correctly.")
    elif routes_connected == 10:
        feedback.append("PARTIAL: Only one character routed to Dia Bus.")
    else:
        feedback.append("FAIL: Characters not routed to Dia Bus.")

    # 3 & 4. Playlist Distribution (15 + 15)
    a_regions = get_regions_for_track(root, "Character A")
    b_regions = get_regions_for_track(root, "Character B")

    a_dist_score = min(15, len(a_regions) * 7.5)
    b_dist_score = min(15, len(b_regions) * 7.5)
    
    score += a_dist_score
    score += b_dist_score
    
    feedback.append(f"Distribution: Character A has {len(a_regions)} regions, Character B has {len(b_regions)} regions.")

    # 5. Timeline Synchronization (25)
    expected_a = task_info.get('metadata', {}).get('char_a_expected_positions', [0, 661500])
    expected_b = task_info.get('metadata', {}).get('char_b_expected_positions', [352800, 970200])

    sync_pts = 0
    perfect_tol = 10000  # ~0.22s
    loose_tol = 44100    # ~1.0s

    def check_sync(actuals, expected):
        points = 0
        matched = set()
        for exp in expected:
            best_diff = float('inf')
            best_idx = -1
            for i, act in enumerate(actuals):
                if i in matched: continue
                diff = abs(act - exp)
                if diff < best_diff:
                    best_diff = diff
                    best_idx = i
            
            if best_diff <= perfect_tol:
                points += 1
                matched.add(best_idx)
            elif best_diff <= loose_tol:
                points += 0.5
                matched.add(best_idx)
        return points

    total_sync_hits = check_sync(a_regions, expected_a) + check_sync(b_regions, expected_b)
    
    # Scale 0-4 hits to 0-25 points
    sync_score = (total_sync_hits / 4.0) * 25.0
    score += sync_score
    feedback.append(f"Sync check: {total_sync_hits}/4 sync boundaries matched (Score: {sync_score:.1f}/25).")

    # 6. Source Track Cleanup (10)
    raw_route = get_route_by_name(root, "Raw Scene")
    cleanup_score = 0
    if raw_route is None:
        cleanup_score = 10  # Deleted
    else:
        # Check if muted or empty
        is_muted = False
        for ctrl in raw_route.iter('Controllable'):
            if ctrl.get('name') == 'mute' and ctrl.get('value') in ('1', 'yes', 'true'):
                is_muted = True
        if raw_route.get('muted') in ('1', 'yes', 'true'):
            is_muted = True
            
        raw_regions = get_regions_for_track(root, "Raw Scene")
        
        if is_muted or len(raw_regions) == 0:
            cleanup_score = 10
            
    score += cleanup_score
    if cleanup_score == 10:
        feedback.append("PASS: Raw Scene track cleaned up/muted.")
    else:
        feedback.append("FAIL: Raw Scene track still active in session.")

    # Anti-Gaming / VLM check
    # Make sure we didn't just load an empty session and rename things
    if score >= 65 and len(a_regions) + len(b_regions) == 0:
        score = 0
        feedback.append("CRITICAL FAIL: No regions found. Cannot pass without processing audio.")

    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        # Fetching trajectory frames to check workflow visually
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        if final:
            # We don't mandate VLM scores here to keep verifier reliable strictly by XML, 
            # but we attach them to the trajectory logging if accessible
            pass
    except ImportError:
        pass

    os.unlink(tmp_xml.name)
    
    passed = score >= task_info.get('metadata', {}).get('pass_threshold', 65)
    if passed and sync_score < 12:
        # Sync is the core of checkerboarding. Hard fail if sync is completely off.
        passed = False
        feedback.append("CRITICAL FAIL: Timeline synchronization was lost during checkerboarding. Lip-sync is ruined.")

    return {
        "passed": passed,
        "score": round(score),
        "feedback": " | ".join(feedback)
    }