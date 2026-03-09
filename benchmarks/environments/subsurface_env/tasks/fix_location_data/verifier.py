#!/usr/bin/env python3
"""Verifier for fix_location_data task.

Checks that the three injected location errors have been corrected:
1. "Snd Rck" site name corrected back to "Sund Rock" (or similar correct spelling)
2. Sund Rock GPS corrected from 0.0,0.0 to Hood Canal WA region (~47.4, -123.1)
3. Yellow House GPS corrected from 35.0,-120.0 to Hood Canal WA region (~47.4, -123.1)

Scoring (100 points):
- Sund Rock name corrected: 25 points
- Sund Rock GPS in correct region: 25 points
- Yellow House GPS in correct region: 25 points
- All sites have GPS coordinates (none missing): 25 points

Pass threshold: 50 points (2 of 4 criteria met)
"""

import os
import tempfile
import xml.etree.ElementTree as ET


def _parse_gps(gps_str):
    """Parse 'lat lon' GPS string, return (lat, lon) floats or None."""
    try:
        parts = gps_str.strip().split()
        if len(parts) == 2:
            return float(parts[0]), float(parts[1])
    except (ValueError, AttributeError):
        pass
    return None


def _in_hood_canal(lat, lon):
    """Check if coordinates are in the Hood Canal, WA region."""
    return (47.2 <= lat <= 47.6) and (-123.3 <= lon <= -122.9)


def verify_fix_location_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    tmp.close()
    try:
        try:
            copy_from_env('/home/ga/Documents/dives.ssrf', tmp.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read dives.ssrf: {e}"}

        try:
            tree = ET.parse(tmp.name)
            root = tree.getroot()
        except ET.ParseError as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse SSRF XML: {e}"}

        score = 0
        feedback_parts = []

        # Collect all dive sites
        divesites = root.find('divesites')
        sites = {}
        if divesites is not None:
            for site in divesites.findall('site'):
                name = site.get('name', '')
                gps_str = site.get('gps', '')
                gps = _parse_gps(gps_str)
                sites[site.get('uuid', '')] = {
                    'name': name,
                    'gps': gps,
                    'gps_raw': gps_str
                }

        # Also check location elements in dives
        for dive in root.iter('dive'):
            loc = dive.find('location')
            if loc is not None:
                loc_text = (loc.text or '').strip()
                gps_str = loc.get('gps', '')
                gps = _parse_gps(gps_str)
                dsid = dive.get('divesiteid', '')
                if dsid and dsid in sites:
                    # Prefer divesites section data, but note location text
                    if loc_text and not sites[dsid]['name']:
                        sites[dsid]['name'] = loc_text
                elif loc_text:
                    # No divesiteid, use location element
                    key = f"loc_{loc_text}"
                    if key not in sites:
                        sites[key] = {'name': loc_text, 'gps': gps, 'gps_raw': gps_str}

        # Check 1: Sund Rock name corrected from "Snd Rck"
        sund_rock_fixed = False
        sund_rock_gps_fixed = False
        yellow_house_gps_fixed = False
        all_have_gps = True

        for sid, info in sites.items():
            name_lower = info['name'].lower()

            # Check for Sund Rock (corrected from "Snd Rck")
            if 'sund' in name_lower and 'rock' in name_lower:
                sund_rock_fixed = True
                # Also check its GPS
                if info['gps'] is not None:
                    lat, lon = info['gps']
                    if _in_hood_canal(lat, lon):
                        sund_rock_gps_fixed = True

            # Still garbled?
            if name_lower in ('snd rck', 'snd rock', 'sund rck'):
                sund_rock_fixed = False

            # Check Yellow House GPS
            if 'yellow' in name_lower and 'house' in name_lower:
                if info['gps'] is not None:
                    lat, lon = info['gps']
                    if _in_hood_canal(lat, lon):
                        yellow_house_gps_fixed = True

            # Check if any site is missing GPS
            if info['gps'] is None or (info['gps'][0] == 0.0 and info['gps'][1] == 0.0):
                all_have_gps = False

        if sund_rock_fixed:
            score += 25
            feedback_parts.append("Sund Rock name corrected")
        else:
            feedback_parts.append("Sund Rock name still garbled or not found")

        if sund_rock_gps_fixed:
            score += 25
            feedback_parts.append("Sund Rock GPS in correct region")
        else:
            feedback_parts.append("Sund Rock GPS not in Hood Canal region")

        if yellow_house_gps_fixed:
            score += 25
            feedback_parts.append("Yellow House GPS in correct region")
        else:
            feedback_parts.append("Yellow House GPS not in Hood Canal region")

        if all_have_gps:
            score += 25
            feedback_parts.append("All sites have valid GPS")
        else:
            feedback_parts.append("Some sites still missing GPS or at 0,0")

        passed = score >= 50
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
