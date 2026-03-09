#!/usr/bin/env python3
"""Verifier for update_dive_notes task.

Checks that Dive #4 in the saved SSRF file has notes mentioning the octopus sighting.
"""

import os
import tempfile
import xml.etree.ElementTree as ET


def verify_update_dive_notes(traj, env_info, task_info):
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

        # Find dive number 4
        dive4 = None
        for dive in root.iter('dive'):
            if dive.get('number') == '4':
                dive4 = dive
                break

        if dive4 is None:
            return {"passed": False, "score": 0, "feedback": "Dive #4 not found in SSRF file"}

        # Get notes — may be in <notes> child element or notes attribute
        notes = ''
        notes_elem = dive4.find('notes')
        if notes_elem is not None and notes_elem.text:
            notes = notes_elem.text
        if not notes:
            notes = dive4.get('notes', '')

        notes_lower = notes.lower()

        # Check for key phrases from the required note
        has_octopus = 'octopus' in notes_lower
        has_depth = '10 meter' in notes_lower or '10m' in notes_lower
        has_visibility = 'visibility' in notes_lower
        has_temperature = 'celsius' in notes_lower or 'temperature' in notes_lower

        criteria = [has_octopus, has_depth, has_visibility, has_temperature]
        passed_count = sum(criteria)
        score = int((passed_count / len(criteria)) * 100)

        if has_octopus and passed_count >= 3:
            return {
                "passed": True,
                "score": score,
                "feedback": f"Dive #4 notes updated with octopus sighting. Notes preview: {notes[:100]}..."
            }
        elif has_octopus:
            return {
                "passed": True,
                "score": score,
                "feedback": f"Dive #4 notes mention octopus. Notes: {notes[:100]}"
            }
        else:
            return {
                "passed": False,
                "score": score,
                "feedback": f"Dive #4 notes do not mention octopus. Current notes: {notes[:100]}"
            }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
