#!/usr/bin/env python3
"""Verifier for add_new_dive task.

Checks that a new dive dated 2023-07-15 at Blue Hole Dahab was added.
"""

import os
import tempfile
import xml.etree.ElementTree as ET


def verify_add_new_dive(traj, env_info, task_info):
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

        # Look for a dive dated 2023-07-15
        target_date = '2023-07-15'
        new_dive = None
        for dive in root.iter('dive'):
            if dive.get('date') == target_date:
                new_dive = dive
                break

        if new_dive is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"No dive found with date {target_date} — new dive was not added"
            }

        # Check buddy
        buddy = new_dive.get('buddy', '')
        if not buddy:
            buddy_elem = new_dive.find('buddy')
            buddy = buddy_elem.text.strip() if buddy_elem is not None and buddy_elem.text else ''

        has_buddy = 'ahmed' in buddy.lower() or 'hassan' in buddy.lower()

        # Check location (in <location> child or divesiteid)
        location_text = ''
        loc_elem = new_dive.find('location')
        if loc_elem is not None and loc_elem.text:
            location_text = loc_elem.text.lower()

        has_location = 'blue hole' in location_text or 'dahab' in location_text

        # Check duration (should be close to 45 min)
        # Subsurface stores duration as "45:00 min" or "45:30 min"
        duration_raw = new_dive.get('duration', '')
        has_duration = False
        if duration_raw:
            import re
            m = re.match(r'(\d+):(\d+)', duration_raw)
            if m:
                total_minutes = int(m.group(1)) + int(m.group(2)) / 60
                has_duration = 40 <= total_minutes <= 50

        criteria = [True, has_buddy, has_location, has_duration]
        score = int(sum(criteria) / len(criteria) * 100)

        feedback_parts = [
            f"date=2023-07-15 ✓",
            f"buddy='{buddy}' {'✓' if has_buddy else '✗ (expected Ahmed Hassan)'}",
            f"location='{location_text[:30]}' {'✓' if has_location else '✗ (expected Blue Hole, Dahab)'}",
            f"duration='{duration_raw}' {'✓' if has_duration else '✗ (expected ~45 min)'}"
        ]

        return {
            "passed": score >= 75,
            "score": score,
            "feedback": "New dive found. " + "; ".join(feedback_parts)
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
