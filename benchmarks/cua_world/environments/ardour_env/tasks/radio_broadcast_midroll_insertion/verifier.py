#!/usr/bin/env python3
"""
Verifier for radio_broadcast_midroll_insertion task.
Occupation: Broadcast Technician
Industry: Broadcasting / Media

Checks that the agent created a mid-roll gap by splitting and sliding an audio region,
trimmed an interlude to fit the exact gap, and exported the resulting broadcast mix.
"""

import json
import os
import math
import logging
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ---------- Ardour XML helpers ----------

def get_audio_routes(root):
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_gain_db(route):
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

def get_regions_for_route(root, route_name):
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        # Ardour playlist names are typically the route name or "RouteName.N"
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                regions.append({
                    'name': region.get('name', ''),
                    'position': int(region.get('position', '0')),
                    'length': int(region.get('length', '0')),
                    'start': int(region.get('start', '0'))  # Source file offset
                })
    return regions

# ---------- Main Verifier ----------

def verify_radio_broadcast_midroll_insertion(traj, env_info, task_info):
    """
    Multi-criterion verifier for radio broadcast midroll insertion.

    Criteria (100 pts total, pass >= 65):
      1. Track Setup (15 pts): 'Program' and 'Ad Break' tracks exist.
      2. Program Split & Slide (30 pts): region at 0s, and latter half region starting at 20s.
      3. Ad Break Trim & Placement (25 pts): region placed at 10s with 10s length.
      4. Ad Break Gain (15 pts): gain around -6 dB.
      5. Export Final Mix (15 pts): final_mix.wav exported successfully.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # Get metadata configuration
    meta = task_info.get('metadata', {})
    tol = meta.get('tolerance_samples', 22050)
    split_point = meta.get('split_point_samples', 441000)
    resume_point = meta.get('resume_point_samples', 882000)
    
    # ---------------------------------------------------------
    # JSON Result check (Export status)
    # ---------------------------------------------------------
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    
    export_exists = False
    export_size = 0
    export_mtime = 0
    task_start = 0

    try:
        copy_from_env("/tmp/radio_broadcast_midroll_insertion_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            res = json.load(f)
            export_exists = res.get('export_exists', False)
            export_size = res.get('export_size', 0)
            export_mtime = res.get('export_mtime', 0)
            task_start = res.get('task_start_timestamp', 0)
    except Exception as e:
        logger.warning(f"Failed to read result JSON: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if export_exists and export_size > 1024:
        if export_mtime >= int(task_start):
            score += 15.0
            feedback.append("PASS: Final mix exported properly")
        else:
            score += 5.0
            feedback.append("PARTIAL: Export found but timestamp indicates old file")
    else:
        feedback.append("FAIL: Final mix not exported or empty")

    # ---------------------------------------------------------
    # Ardour XML checking
    # ---------------------------------------------------------
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
        return {"passed": False, "score": score, "feedback": f"Session XML parse error: {e}"}

    if os.path.exists(tmp_xml.name):
        os.unlink(tmp_xml.name)

    routes = get_audio_routes(root)
    
    # Track discovery
    program_route = None
    ad_route = None
    
    for r in routes:
        name = r.get('name', '').lower()
        if 'program' in name:
            program_route = r
        elif 'ad break' in name or 'ad' in name or 'interlude' in name:
            ad_route = r

    if program_route and ad_route:
        score += 15.0
        feedback.append("PASS: 'Program' and 'Ad Break' tracks found")
    else:
        if program_route:
            feedback.append("PARTIAL: Only 'Program' track found")
            score += 7.0
        elif ad_route:
            feedback.append("PARTIAL: Only 'Ad Break' track found")
            score += 7.0
        else:
            feedback.append("FAIL: Required tracks not found")

    # Assess Program track (Split & Slide)
    if program_route:
        prog_regions = get_regions_for_route(root, program_route.get('name'))
        
        has_start_region = False
        has_resumed_region = False
        
        for reg in prog_regions:
            pos = reg['position']
            src_start = reg['start']
            
            if abs(pos - 0) <= tol:
                has_start_region = True
                
            # Verify region exists at 20.0s mark and source starts at ~10.0s (proving it was split)
            if abs(pos - resume_point) <= tol and abs(src_start - split_point) <= tol:
                has_resumed_region = True

        if has_start_region and has_resumed_region:
            score += 30.0
            feedback.append("PASS: Program correctly split and offset by 10 seconds")
        else:
            if has_start_region:
                score += 10.0
                feedback.append("PARTIAL: Program starts at 0s, but split/offset missing or incorrect")
            else:
                feedback.append("FAIL: Program region not correctly placed or split")

    # Assess Ad Break track (Trim & Placement)
    if ad_route:
        ad_regions = get_regions_for_route(root, ad_route.get('name'))
        has_correct_ad = False
        
        for reg in ad_regions:
            pos = reg['position']
            length = reg['length']
            
            # Verify placed exactly in the gap with correct length
            if abs(pos - split_point) <= tol and abs(length - (resume_point - split_point)) <= tol:
                has_correct_ad = True
                break
                
        if has_correct_ad:
            score += 25.0
            feedback.append("PASS: Ad Break properly placed and trimmed")
        else:
            if ad_regions:
                score += 10.0
                feedback.append("PARTIAL: Ad Break has regions, but not correctly placed or trimmed")
            else:
                feedback.append("FAIL: No regions found on Ad Break track")
                
        # Ad Break gain staging
        gain_db = get_route_gain_db(ad_route)
        if -8.0 <= gain_db <= -4.0:
            score += 15.0
            feedback.append(f"PASS: Ad Break gain is {gain_db:.1f} dB")
        else:
            feedback.append(f"FAIL: Ad Break gain is {gain_db:.1f} dB (expected ~-6 dB)")

    passed = score >= 65.0
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }