#!/usr/bin/env python3
"""Verifier for set_dive_site_gps task.

Checks that the dive site associated with Dive #2 has GPS coordinates
close to 47.4005, -123.1420 (Sund Rock, Hoodsport WA).
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


def verify_set_dive_site_gps(traj, env_info, task_info):
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

        target_lat = 47.4005
        target_lon = -123.1420
        tolerance = 0.02  # ~2km tolerance

        # Find dive number 2 and its divesiteid
        dive2 = None
        for dive in root.iter('dive'):
            if dive.get('number') == '2':
                dive2 = dive
                break

        if dive2 is None:
            return {"passed": False, "score": 0, "feedback": "Dive #2 not found in SSRF file"}

        # Method 1: Check divesiteid -> look in <divesites>
        divesiteid = dive2.get('divesiteid', '')
        gps_found = None

        if divesiteid:
            divesite_section = root.find('divesites')
            if divesite_section is not None:
                for site in divesite_section.findall('site'):
                    if site.get('uuid') == divesiteid:
                        gps_str = site.get('gps', '')
                        if gps_str:
                            gps_found = _parse_gps(gps_str)
                        break

        # Method 2: Check <location> child element of dive2
        if gps_found is None:
            loc_elem = dive2.find('location')
            if loc_elem is not None:
                gps_str = loc_elem.get('gps', '')
                if gps_str:
                    gps_found = _parse_gps(gps_str)

        if gps_found is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No GPS coordinates found for Dive #2 / Sund Rock dive site"
            }

        lat, lon = gps_found
        lat_ok = abs(lat - target_lat) <= tolerance
        lon_ok = abs(lon - target_lon) <= tolerance

        if lat_ok and lon_ok:
            return {
                "passed": True,
                "score": 100,
                "feedback": f"GPS set correctly: {lat:.4f}, {lon:.4f} (target: {target_lat}, {target_lon})"
            }
        else:
            return {
                "passed": False,
                "score": 30,
                "feedback": (f"GPS found ({lat:.4f}, {lon:.4f}) but doesn't match "
                             f"target ({target_lat}, {target_lon})")
            }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
