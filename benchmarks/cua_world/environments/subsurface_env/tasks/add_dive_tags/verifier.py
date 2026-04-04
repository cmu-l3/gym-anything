#!/usr/bin/env python3
"""Verifier for add_dive_tags task.

Checks that Dive #85 in the saved SSRF file has 'deep' and 'deco' in its tags.
"""

import os
import tempfile
import xml.etree.ElementTree as ET


def verify_add_dive_tags(traj, env_info, task_info):
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

        # Find dive number 85
        dive85 = None
        for dive in root.iter('dive'):
            if dive.get('number') == '85':
                dive85 = dive
                break

        if dive85 is None:
            return {"passed": False, "score": 0, "feedback": "Dive #85 not found in SSRF file"}

        tags_raw = dive85.get('tags', '')
        # Tags are comma-separated
        tags = [t.strip().lower() for t in tags_raw.split(',') if t.strip()]

        has_deep = 'deep' in tags
        has_deco = 'deco' in tags

        score = (int(has_deep) + int(has_deco)) * 50

        if has_deep and has_deco:
            return {
                "passed": True,
                "score": 100,
                "feedback": f"Dive #85 has both 'deep' and 'deco' tags. All tags: {tags_raw}"
            }
        else:
            missing = []
            if not has_deep:
                missing.append('deep')
            if not has_deco:
                missing.append('deco')
            return {
                "passed": False,
                "score": score,
                "feedback": f"Dive #85 tags: '{tags_raw}'. Missing: {missing}"
            }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
