#!/usr/bin/env python3
"""
Verifier for field_recording_segmentation task.
Occupation: Conservation Scientist / Wildlife Biologist (SOC 19-1031)
Industry: Environmental Science

Checks that the agent imported a continuous field recording, split it into 5 segments,
renamed the regions, added range markers for vocalizations, muted background noise,
and created a log file.
"""

import os
import tempfile
import logging
import json
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ---------- Ardour XML helpers ----------

def get_regions(root):
    regions = []
    for playlist in root.iter('Playlist'):
        # Check all regions within playlists
        for region in playlist.iter('Region'):
            regions.append({
                'name': region.get('name', ''),
                'position': int(region.get('position', '0')),
                'length': int(region.get('length', '0')),
                'muted': region.get('muted', '0')
            })
    return regions

def get_markers(root):
    markers = []
    for loc in root.iter('Location'):
        flags = loc.get('flags', '')
        if any(f in flags for f in ('IsSessionRange', 'IsAutoLoop', 'IsAutoPunch')):
            continue
        markers.append({
            'name': loc.get('name', ''),
            'start': int(loc.get('start', '0')),
            'end': int(loc.get('end', '0')),
            'flags': flags,
        })
    return markers

# ---------- Main verifier ----------

def verify_field_recording_segmentation(traj, env_info, task_info):
    """
    Multi-criterion verifier for field recording segmentation.

    Criteria (100 pts total, pass >= 55):
      1. Regions split (>= 4 regions exist)                           (20 pts)
      2. Region names correct (contain AMRO, MOCH, YWAR, BKGD x 2)    (25 pts)
      3. Range markers at correct positions                           (20 pts)
      4. Background regions muted                                     (15 pts)
      5. Species log file created with correct contents               (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # 1. Read export json
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env("/tmp/field_recording_segmentation_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Result JSON error: {e}"}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    # 2. Parse XML
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
        return {"passed": False, "score": 0.0, "feedback": f"Session XML error: {e}"}
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    regions = get_regions(root)
    markers = get_markers(root)

    # ================================================================
    # CRITERION 1: Regions split (20 pts)
    # ================================================================
    if len(regions) >= 4:
        score += 20.0
        feedback.append(f"PASS: Found {len(regions)} regions (expected 5)")
    elif len(regions) >= 2:
        score += 10.0
        feedback.append(f"PARTIAL: Found {len(regions)} regions")
    else:
        feedback.append(f"FAIL: Found only {len(regions)} regions, expected 5")

    # ================================================================
    # CRITERION 2: Region names (25 pts)
    # ================================================================
    region_names_lower = [r['name'].lower() for r in regions]
    
    codes_found = {'amro': False, 'moch': False, 'ywar': False}
    bkgd_count = 0
    
    for rname in region_names_lower:
        if 'amro' in rname: codes_found['amro'] = True
        elif 'moch' in rname: codes_found['moch'] = True
        elif 'ywar' in rname: codes_found['ywar'] = True
        elif 'bkgd' in rname: bkgd_count += 1
        
    pts2 = 0
    if codes_found['amro']: pts2 += 5
    if codes_found['moch']: pts2 += 5
    if codes_found['ywar']: pts2 += 5
    pts2 += min(10, bkgd_count * 5)
    
    score += pts2
    if pts2 == 25:
        feedback.append("PASS: All region names contain correct species codes")
    else:
        feedback.append(f"PARTIAL: Region names matched for {pts2}/25 pts")

    # ================================================================
    # CRITERION 3: Range markers (20 pts)
    # ================================================================
    m_pts = 0
    expected_ranges = {
        'amro': {'start': 264600, 'end': 529200},
        'moch': {'start': 529200, 'end': 793800},
        'ywar': {'start': 793800, 'end': 1058400}
    }
    tolerance = 88200 # 2 seconds at 44.1kHz
    
    for code, expected in expected_ranges.items():
        found = False
        for m in markers:
            m_name = m['name'].lower()
            # Ensure it's a range (start != end or IsRangeMarker flag)
            is_range = 'IsRangeMarker' in m['flags'] or m['start'] != m['end']
            if code in m_name and is_range:
                if abs(m['start'] - expected['start']) <= tolerance and abs(m['end'] - expected['end']) <= tolerance:
                    found = True
                    break
        if found:
            m_pts += 7.0

    m_pts = min(20.0, m_pts)
    score += m_pts
    if m_pts == 20.0:
        feedback.append("PASS: Range markers placed correctly")
    else:
        feedback.append(f"PARTIAL: Range markers matched for {m_pts:.1f}/20 pts")

    # ================================================================
    # CRITERION 4: Muted backgrounds (15 pts)
    # ================================================================
    muted_bkgd_count = 0
    for r in regions:
        if 'bkgd' in r['name'].lower():
            if r['muted'] == '1' or r['muted'] == 'true':
                muted_bkgd_count += 1
                
    b_pts = min(15.0, muted_bkgd_count * 7.5)
    score += b_pts
    if b_pts == 15.0:
        feedback.append("PASS: Background regions are muted")
    else:
        feedback.append(f"PARTIAL/FAIL: Background muted regions found: {muted_bkgd_count} ({b_pts:.1f}/15 pts)")

    # ================================================================
    # CRITERION 5: Species log file (20 pts)
    # ================================================================
    l_pts = 0
    if result.get('log_exists', False):
        l_pts += 5.0
        content = result.get('log_content', '').lower()
        if 'amro' in content: l_pts += 5.0
        if 'moch' in content: l_pts += 5.0
        if 'ywar' in content: l_pts += 5.0
    
    score += l_pts
    if l_pts == 20.0:
        feedback.append("PASS: Species log file created with correct codes")
    else:
        feedback.append(f"PARTIAL/FAIL: Species log matched for {l_pts:.1f}/20 pts")

    passed = score >= 55.0
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }