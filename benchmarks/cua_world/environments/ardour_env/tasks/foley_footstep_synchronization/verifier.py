#!/usr/bin/env python3
"""
Verifier for foley_footstep_synchronization task.
Occupation: Foley Editor / Sound Editor
Industry: Film & Post-Production

Checks that the agent created a Foley track, trimmed the raw audio regions, 
and aligned them to specific timecodes per the spotting notes.
"""

import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ---------- Ardour XML Helpers ----------

def get_audio_routes(root):
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def find_foley_route(root, aliases):
    for route in get_audio_routes(root):
        name = route.get('name', '').lower()
        if any(alias in name for alias in aliases):
            return route
    return None

def get_unmuted_regions(root, route):
    """
    Finds the playlist associated with a route and extracts all unmuted regions.
    """
    playlist_name = None
    # Try finding Diskstream to get the exact playlist name
    for ds in route.iter('Diskstream'):
        if 'playlist' in ds.attrib:
            playlist_name = ds.attrib['playlist']
            break
            
    regions = []
    
    # If no explicit playlist attribute, use route name heuristics
    if not playlist_name:
        route_name = route.get('name', '')
        for playlist in root.iter('Playlist'):
            pl_name = playlist.get('name', '')
            base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
            if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
                for region in playlist.iter('Region'):
                    if region.get('muted', '0') != '1':
                        regions.append({
                            'name': region.get('name', ''),
                            'position': int(region.get('position', '0')),
                            'length': int(region.get('length', '0'))
                        })
        return regions

    # If we have the exact playlist_name, strictly match it
    for playlist in root.iter('Playlist'):
        if playlist.get('name') == playlist_name:
            for region in playlist.iter('Region'):
                if region.get('muted', '0') != '1':
                    regions.append({
                        'name': region.get('name', ''),
                        'position': int(region.get('position', '0')),
                        'length': int(region.get('length', '0'))
                    })
            break
            
    return regions


# ---------- Main Verifier ----------

def verify_foley_synchronization(traj, env_info, task_info):
    """
    Multi-criterion verifier for Foley synchronization.

    Criteria (100 pts total, pass >= 65):
      1. Track created & named appropriately                 (15 pts)
      2. Regions trimmed (>=4 active regions, all <= 2.0s)   (25 pts)
      3. Sync Cue 1 (5.0s / 220500)                          (10 pts)
      4. Sync Cue 2 (10.0s / 441000)                         (10 pts)
      5. Sync Cue 3 (15.0s / 661500)                         (10 pts)
      6. Sync Cue 4 (20.0s / 882000)                         (10 pts)
      7. Clean timeline (Exactly 4 unmuted regions)          (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    aliases = metadata.get('track_name_aliases', ["synced footsteps", "synced_footsteps", "footsteps sync", "footsteps"])
    max_length = metadata.get('max_region_length_samples', 88200)
    expected_cues = metadata.get('cues_samples', [220500, 441000, 661500, 882000])
    tolerance = metadata.get('tolerance_samples', 22050)
    pass_threshold = metadata.get('pass_threshold', 65)

    score = 0.0
    feedback = []

    # ---- Copy and Parse Session XML ----
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp.close()

    try:
        copy_from_env(session_remote, tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session not accessible: {e}"}

    if not os.path.exists(tmp.name) or os.path.getsize(tmp.name) == 0:
        return {"passed": False, "score": 0.0, "feedback": "Session empty or missing"}

    try:
        tree = ET.parse(tmp.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp.name)
        return {"passed": False, "score": 0.0, "feedback": f"XML parse error: {e}"}

    # ================================================================
    # EVALUATION
    # ================================================================

    # Criterion 1: Track found
    foley_route = find_foley_route(root, aliases)

    if foley_route:
        score += 15.0
        feedback.append("PASS: Foley track found")
        regions = get_unmuted_regions(root, foley_route)
    else:
        feedback.append("FAIL: Foley track not found (did you name it 'Synced Footsteps'?)")
        # Try to find regions on ANY audio track to give partial credit for work done
        regions = []
        for route in get_audio_routes(root):
            r_regs = get_unmuted_regions(root, route)
            if len(r_regs) >= 4:
                regions = r_regs
                break

    # Criterion 2: Regions trimmed
    if len(regions) >= 4:
        all_trimmed = True
        for r in regions:
            if r['length'] > max_length:
                all_trimmed = False
                break
        
        if all_trimmed:
            score += 25.0
            feedback.append("PASS: Regions trimmed correctly (<= 2.0s)")
        else:
            score += 10.0
            feedback.append("PARTIAL: >= 4 regions found, but some are longer than 2.0s (not trimmed)")
    else:
        feedback.append(f"FAIL: Expected at least 4 regions, found {len(regions)}")

    # Criteria 3-6: Sync Cues
    matched_cues = 0
    for i, cue in enumerate(expected_cues):
        matched = False
        for r in regions:
            if abs(r['position'] - cue) <= tolerance:
                matched = True
                break
        
        if matched:
            score += 10.0
            matched_cues += 1
            feedback.append(f"PASS: Cue {i+1} synced correctly at {cue/44100:.1f}s")
        else:
            feedback.append(f"FAIL: Cue {i+1} not found near {cue/44100:.1f}s")

    # Criterion 7: Clean timeline
    if len(regions) == 4 and matched_cues == 4:
        score += 20.0
        feedback.append("PASS: Clean timeline (exactly 4 correctly synced regions)")
    elif len(regions) == 4 and matched_cues > 0:
        score += 10.0
        feedback.append("PARTIAL: Exactly 4 regions, but some were not synced correctly")
    elif len(regions) > 4:
        feedback.append("FAIL: Timeline not clean (unused regions left unmuted/undeleted)")

    os.unlink(tmp.name)

    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "regions_found": len(regions),
            "cues_synced": matched_cues
        }
    }