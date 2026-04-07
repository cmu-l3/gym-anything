#!/usr/bin/env python3
"""
Verifier for cubesat_multisite_qth task.

Scoring (100 points total, Pass >= 70):
1. Ground Stations (30 pts - 10 per station)
2. Module Satellites (37 pts - Europe=12, Japan=15, America=10)
3. Module QTH Assignments (24 pts - 8 per module)
4. Preservation of Amateur module (5 pts)
5. Existence of all 3 target modules (4 pts)
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def _close_enough(val_str, expected, tol=0.1):
    try:
        return abs(float(val_str) - expected) <= tol
    except (ValueError, TypeError):
        return False

def _extract_sats(sat_str):
    """Extract NORAD IDs from a semicolon delimited string."""
    if not sat_str:
        return set()
    parts = re.split(r'[;,\s]+', sat_str)
    return {int(p) for p in parts if p.isdigit()}

def verify_cubesat_multisite_qth(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/cubesat_multisite_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        with open(temp_path, 'r') as f:
            result = json.load(f)

    except (json.JSONDecodeError, FileNotFoundError) as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    
    qths = result.get('qths', [])
    mods = result.get('mods', [])
    start_time = result.get('task_start_time', 0)

    # Specs
    expected_qths = {
        "Delft_TU": {"lat": 52.0116, "lon": 4.3571, "alt": 5, "pts": 10},
        "Tokyo_Tech": {"lat": 35.6042, "lon": 139.6837, "alt": 26, "pts": 10},
        "CalPoly_SLO": {"lat": 35.3050, "lon": -120.6625, "alt": 96, "pts": 10}
    }
    
    expected_mods = {
        "EuropeSats": {"sats": {39444, 32789}, "sat_pts": 6, "qth": "Delft_TU", "qth_pts": 8},
        "JapanSats": {"sats": {27844, 27848, 32791}, "sat_pts": 5, "qth": "Tokyo_Tech", "qth_pts": 8},
        "AmericaSats": {"sats": {43017, 43137}, "sat_pts": 5, "qth": "CalPoly_SLO", "qth_pts": 8}
    }

    # 1. Evaluate Ground Stations
    # Map matched QTH names so we can verify module assignments robustly
    matched_qth_filenames = {
        "Delft_TU": None,
        "Tokyo_Tech": None,
        "CalPoly_SLO": None
    }

    for target_name, specs in expected_qths.items():
        best_match_filename = None
        best_pts = 0
        
        for qth in qths:
            pts = 0
            lat_ok = _close_enough(qth.get('lat'), specs['lat'], 0.1)
            lon_ok = _close_enough(qth.get('lon'), specs['lon'], 0.1)
            alt_ok = _close_enough(qth.get('alt'), specs['alt'], 20)
            
            # Identify by filename match OR coordinate match
            name_match = target_name.lower() in qth.get('filename', '').lower()
            
            if lat_ok and lon_ok:
                pts += specs['pts'] * 0.7
                if alt_ok:
                    pts += specs['pts'] * 0.3
                    
            if name_match and pts == 0:
                # Name matches but coords are totally wrong
                pts = 2
                
            if pts > best_pts:
                best_pts = pts
                best_match_filename = qth.get('filename')

        best_pts = int(best_pts)
        score += best_pts
        if best_pts == specs['pts']:
            feedback_parts.append(f"{target_name} QTH correct")
        elif best_pts > 0:
            feedback_parts.append(f"{target_name} QTH partially correct ({best_pts} pts)")
        else:
            feedback_parts.append(f"{target_name} QTH missing")
            
        matched_qth_filenames[target_name] = best_match_filename

    # 2 & 3. Evaluate Modules and QTH Assignments
    found_mod_count = 0
    
    for target_name, specs in expected_mods.items():
        mod_found = False
        target_sats = specs['sats']
        
        for mod in mods:
            # Look for exact or highly similar filename
            if target_name.lower() in mod.get('filename', '').lower():
                mod_found = True
                found_mod_count += 1
                
                # Check satellites
                actual_sats = _extract_sats(mod.get('satellites'))
                sat_score = 0
                for s in target_sats:
                    if s in actual_sats:
                        sat_score += specs['sat_pts']
                score += sat_score
                feedback_parts.append(f"{target_name} satellites: {sat_score}/{len(target_sats)*specs['sat_pts']} pts")
                
                # Check QTH Assignment
                actual_qthfile = mod.get('qthfile', '')
                expected_target_qth = specs['qth']
                expected_filename = matched_qth_filenames.get(expected_target_qth)
                
                qth_assigned_correctly = False
                
                if actual_qthfile and expected_filename and actual_qthfile.lower() == expected_filename.lower():
                    qth_assigned_correctly = True
                elif actual_qthfile and expected_target_qth.lower() in actual_qthfile.lower():
                    # Fallback string matching if the agent didn't configure coords properly but assigned the name
                    qth_assigned_correctly = True
                    
                if qth_assigned_correctly:
                    score += specs['qth_pts']
                    feedback_parts.append(f"{target_name} QTH assigned correctly")
                else:
                    feedback_parts.append(f"{target_name} QTH incorrectly assigned to '{actual_qthfile}'")
                break
                
        if not mod_found:
            feedback_parts.append(f"{target_name} module missing")

    # 4. Amateur module preserved
    amateur_preserved = any('amateur' in m.get('filename', '').lower() for m in mods)
    if amateur_preserved:
        score += 5
        feedback_parts.append("Amateur.mod preserved")
    else:
        feedback_parts.append("Amateur.mod DELETED (penalty)")

    # 5. All 3 target modules exist
    if found_mod_count == 3:
        score += 4
        feedback_parts.append("All 3 target modules exist")

    # Anti-gaming timestamp checks
    for m in mods:
        if m.get('mtime', 0) < start_time and m.get('filename', '').lower() != 'amateur.mod':
            logger.warning(f"File {m.get('filename')} predates task start time!")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }