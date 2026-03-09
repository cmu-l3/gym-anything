#!/usr/bin/env python3
"""Verifier for create_dive_trip task.

Checks that a new trip and dive were created for the Red Sea Liveaboard 2022.
"""

import os
import tempfile
import xml.etree.ElementTree as ET


def verify_create_dive_trip(traj, env_info, task_info):
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

        # Look for a trip element with Red Sea / 2022 context
        target_date = '2022-09-10'

        trip_found = False
        for trip in root.iter('trip'):
            loc = trip.get('location', '').lower()
            date = trip.get('date', '')
            if 'red sea' in loc or 'hurghada' in loc or 'egypt' in loc or date.startswith('2022'):
                trip_found = True
                break

        # Check for dive on target date
        new_dive = None
        for dive in root.iter('dive'):
            if dive.get('date') == target_date:
                new_dive = dive
                break
        if new_dive is None:
            for dive in root.iter('dive'):
                if dive.get('date', '').startswith('2022'):
                    new_dive = dive
                    break

        if new_dive is None and not trip_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No dive or trip found for 2022-09-10 — trip was not created"
            }

        # Check buddy on new dive
        buddy = ''
        if new_dive is not None:
            buddy = new_dive.get('buddy', '')
            if not buddy:
                buddy_elem = new_dive.find('buddy')
                buddy = buddy_elem.text.strip() if buddy_elem is not None and buddy_elem.text else ''

        has_buddy = 'sara' in buddy.lower() or 'rashid' in buddy.lower()

        # Check notes for wreck/Thistlegorm
        notes = ''
        if new_dive is not None:
            notes_elem = new_dive.find('notes')
            if notes_elem is not None and notes_elem.text:
                notes = notes_elem.text.lower()
        has_notes = 'thistlegorm' in notes or 'wreck' in notes

        criteria_met = sum([trip_found or new_dive is not None, has_buddy, has_notes])
        score = int(criteria_met / 3 * 100)

        return {
            "passed": score >= 50,
            "score": score,
            "feedback": (f"Trip {'found' if trip_found else 'not found'}; "
                         f"Dive on 2022-09-10 {'found' if new_dive is not None else 'not found'}; "
                         f"buddy='{buddy}' {'OK' if has_buddy else 'missing'}; "
                         f"notes={'OK' if has_notes else 'missing'}")
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
