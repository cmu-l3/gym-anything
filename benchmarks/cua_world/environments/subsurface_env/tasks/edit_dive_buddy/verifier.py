#!/usr/bin/env python3
"""Verifier for edit_dive_buddy task.

Checks that Dive #2 in the saved SSRF file has buddy="Michael Chen".
"""

import os
import tempfile
import xml.etree.ElementTree as ET


def verify_edit_dive_buddy(traj, env_info, task_info):
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

        # Find dive number 2
        dive2 = None
        for dive in root.iter('dive'):
            if dive.get('number') == '2':
                dive2 = dive
                break

        if dive2 is None:
            return {"passed": False, "score": 0, "feedback": "Dive #2 not found in SSRF file"}

        # Check buddy attribute (may be in attribute or child element)
        buddy_val = dive2.get('buddy', '')
        if not buddy_val:
            buddy_elem = dive2.find('buddy')
            if buddy_elem is not None:
                buddy_val = buddy_elem.text or ''

        buddy_val = buddy_val.strip()
        expected = 'Michael Chen'

        if expected.lower() in buddy_val.lower():
            return {
                "passed": True,
                "score": 100,
                "feedback": f"Dive #2 buddy correctly set to '{buddy_val}'"
            }
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Dive #2 buddy is '{buddy_val}', expected '{expected}'"
            }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
