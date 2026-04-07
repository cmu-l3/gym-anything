#!/usr/bin/env python3
"""
Verifier for collision_avoidance_investigation task.

Verifies:
1. Reconstruction scenario (directory, INI structure, vessel data).
2. Avoidance scenario (directory, altered course for give-way vessel).
3. Investigation report (collision analysis, CPA values, COLREGS).
4. Radar configuration in bc5.ini.

Scoring is a stub — full verification will use vlm_checklist_verifier.
"""

import json
import os
import logging
import tempfile
import re
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_collision_avoidance_investigation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    gt = metadata.get('ground_truth', {})

    # Load result JSON from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # ---------------------------------------------------------
    # Criterion 1: Reconstruction Scenario Structure (15 pts)
    # ---------------------------------------------------------
    recon = result.get('reconstruction', {})
    if recon.get('scenario_exists'):
        score += 5
        feedback.append("Reconstruction scenario directory created.")
    else:
        feedback.append("Reconstruction scenario directory NOT found.")

    recon_files = recon.get('files', {})
    if recon_files.get('environment') and recon_files.get('ownship') and recon_files.get('othership'):
        score += 5
        feedback.append("Reconstruction: all 3 INI files present.")
    else:
        feedback.append("Reconstruction: missing INI files.")

    # Check vessel count in reconstruction othership
    recon_others = recon_files.get('othership', [])
    if isinstance(recon_others, list) and len(recon_others) >= 3:
        score += 5
        feedback.append(f"Reconstruction: {len(recon_others)} vessels found (need >= 3).")
    else:
        count = len(recon_others) if isinstance(recon_others, list) else 0
        feedback.append(f"Reconstruction: only {count} vessels found, need >= 3.")

    # ---------------------------------------------------------
    # Criterion 2: Avoidance Scenario Structure (15 pts)
    # ---------------------------------------------------------
    avoid = result.get('avoidance', {})
    if avoid.get('scenario_exists'):
        score += 5
        feedback.append("Avoidance scenario directory created.")
    else:
        feedback.append("Avoidance scenario directory NOT found.")

    avoid_files = avoid.get('files', {})
    if avoid_files.get('environment') and avoid_files.get('ownship') and avoid_files.get('othership'):
        score += 5
        feedback.append("Avoidance: all 3 INI files present.")
    else:
        feedback.append("Avoidance: missing INI files.")

    # Check that avoidance ownship has a different heading from reconstruction
    recon_own = recon_files.get('ownship', {}) or {}
    avoid_own = avoid_files.get('ownship', {}) or {}
    try:
        recon_hdg = float(recon_own.get('InitialBearing', 0))
        avoid_hdg = float(avoid_own.get('InitialBearing', 0))
        if abs(recon_hdg - avoid_hdg) > 5:
            score += 5
            feedback.append(f"Avoidance heading ({avoid_hdg}) differs from reconstruction ({recon_hdg}).")
        else:
            feedback.append("Avoidance heading not significantly altered from reconstruction.")
    except:
        feedback.append("Could not parse ownship headings for comparison.")

    # ---------------------------------------------------------
    # Criterion 3: Radar Configuration (10 pts)
    # ---------------------------------------------------------
    conf = result.get('config', {})

    if str(conf.get('arpa_on')) == '1':
        score += 3
    else:
        feedback.append("ARPA not enabled.")

    if str(conf.get('full_radar')) == '1':
        score += 3
    else:
        feedback.append("Full Radar not enabled.")

    try:
        rng = int(conf.get('max_radar_range', 48))
        if rng == 24:
            score += 4
        else:
            feedback.append(f"Radar range {rng} != 24")
    except:
        pass

    # ---------------------------------------------------------
    # Criterion 4: Investigation Report (60 pts)
    # ---------------------------------------------------------
    rep = result.get('report', {})
    if not rep.get('exists'):
        feedback.append("Investigation report NOT found.")
        return {"passed": score >= 60, "score": score, "feedback": " | ".join(feedback)}

    score += 5
    content = rep.get('content', '').lower()

    # 4a. Collision coordinates mentioned (10 pts)
    # Ground truth: collision near 50.780, -0.970
    has_collision_lat = bool(re.search(r'50\.78[0-9]', content))
    has_collision_lon = bool(re.search(r'0\.97[0-9]', content))
    if has_collision_lat and has_collision_lon:
        score += 10
        feedback.append("Collision coordinates found in report.")
    elif has_collision_lat or has_collision_lon:
        score += 5
        feedback.append("Partial collision coordinates found.")
    else:
        feedback.append("Collision coordinates not found in report.")

    # 4b. Encounter classification (10 pts)
    if 'crossing' in content:
        score += 5
        feedback.append("Encounter classified as crossing.")
    else:
        feedback.append("Encounter type 'crossing' not found.")

    if 'give-way' in content or 'give way' in content or 'giveway' in content:
        score += 5
        feedback.append("Give-way vessel identified.")
    else:
        feedback.append("Give-way vessel identification not found.")

    # 4c. COLREGS rule citations (10 pts)
    rules_found = set(re.findall(r'rule\s*(\d+)', content))
    if len(rules_found) >= 3:
        score += 10
    elif len(rules_found) >= 1:
        score += 5
    else:
        feedback.append("Insufficient COLREGS rule citations.")
    feedback.append(f"COLREGS rules cited: {sorted(rules_found)}")

    # 4d. CPA values mentioned (10 pts)
    cpa_mentions = re.findall(r'cpa', content)
    cpa_values = re.findall(r'(?:cpa|closest\s+point)[^\d]*(\d+\.?\d*)\s*(?:nm|nautical)', content)
    if len(cpa_mentions) >= 3:
        score += 10
        feedback.append(f"CPA analysis present ({len(cpa_mentions)} mentions).")
    elif len(cpa_mentions) >= 1:
        score += 5
        feedback.append("Some CPA analysis present.")
    else:
        feedback.append("CPA analysis not found in report.")

    # 4e. Avoidance maneuver described (10 pts)
    has_avoidance = 'avoidance' in content or 'alter' in content or 'maneuver' in content or 'manoeuvre' in content
    has_heading = bool(re.search(r'0[67][0-9]|08[0-9]|09[0-9]|1[01][0-9]|120', content))
    has_starboard = 'starboard' in content

    if has_avoidance and has_heading:
        score += 10
        feedback.append("Avoidance maneuver with heading described.")
    elif has_avoidance:
        score += 5
        feedback.append("Avoidance maneuver mentioned but heading unclear.")
    else:
        feedback.append("Avoidance maneuver not described.")

    # 4f. Vessel names present (5 pts)
    names_found = 0
    if 'pacific grace' in content:
        names_found += 1
    if 'solent star' in content:
        names_found += 1
    if 'solent express' in content:
        names_found += 1
    if 'morning catch' in content:
        names_found += 1

    if names_found >= 3:
        score += 5
    elif names_found >= 1:
        score += 2
    feedback.append(f"Vessel names found: {names_found}/4")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }
