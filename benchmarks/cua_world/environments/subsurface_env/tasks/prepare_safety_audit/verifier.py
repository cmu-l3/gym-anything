#!/usr/bin/env python3
"""Verifier for prepare_safety_audit task.

Checks four independent subtasks:
1. Deep tagging: All dives deeper than 18m have tag 'deep'
2. Buddy fill: Dives #3 and #5 (Dec 2010) have buddy 'David Price' filled in
3. Imperial units: Subsurface.conf has unit_system=1
4. CSV export: /home/ga/Documents/safety_audit_export.csv exists and has data

Scoring (100 points):
- Deep tagging (at least 3 qualifying dives tagged): 25 points
- Buddy fill (both #3 and #5 have buddy): 25 points
- Imperial units set: 25 points
- CSV export exists with dive data: 25 points

Pass threshold: 50 points (2 of 4 subtasks)
"""

import csv
import os
import re
import tempfile
import xml.etree.ElementTree as ET


def verify_prepare_safety_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback_parts = []

    # =========================================
    # Subtask 1: Check deep tagging in SSRF
    # =========================================
    tmp_ssrf = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    tmp_ssrf.close()
    try:
        try:
            copy_from_env('/home/ga/Documents/dives.ssrf', tmp_ssrf.name)
        except Exception as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not read dives.ssrf: {e}"}

        try:
            tree = ET.parse(tmp_ssrf.name)
            root = tree.getroot()
        except ET.ParseError as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not parse SSRF XML: {e}"}

        # Find all dives deeper than 18m and check for 'deep' tag
        deep_dives_total = 0
        deep_dives_tagged = 0

        for dive in root.iter('dive'):
            depth_str = dive.get('depth', '')
            try:
                depth_val = float(re.sub(r'[^0-9.]', '', depth_str))
            except (ValueError, AttributeError):
                continue

            if depth_val > 18:
                deep_dives_total += 1
                tags_raw = dive.get('tags', '').lower()
                tags = [t.strip() for t in tags_raw.split(',') if t.strip()]
                if 'deep' in tags:
                    deep_dives_tagged += 1

        if deep_dives_total > 0 and deep_dives_tagged >= min(3, deep_dives_total):
            score += 25
            feedback_parts.append(
                f"Deep tags: {deep_dives_tagged}/{deep_dives_total} qualifying dives tagged")
        else:
            feedback_parts.append(
                f"Deep tags: only {deep_dives_tagged}/{deep_dives_total} qualifying dives tagged (need >= 3)")

        # =========================================
        # Subtask 2: Check buddy fill for Dives #3 and #5
        # =========================================
        buddies_filled = 0
        for dive in root.iter('dive'):
            num = dive.get('number', '')
            if num in ('3', '5'):
                buddy = dive.get('buddy', '').strip()
                if not buddy:
                    buddy_elem = dive.find('buddy')
                    if buddy_elem is not None and buddy_elem.text:
                        buddy = buddy_elem.text.strip()
                if buddy:
                    buddies_filled += 1

        if buddies_filled >= 2:
            score += 25
            feedback_parts.append("Buddy fill: both Dive #3 and #5 have buddy names")
        elif buddies_filled == 1:
            score += 12
            feedback_parts.append("Buddy fill: only 1 of 2 dives has buddy filled")
        else:
            feedback_parts.append("Buddy fill: Dives #3 and #5 still missing buddy names")

    finally:
        if os.path.exists(tmp_ssrf.name):
            os.unlink(tmp_ssrf.name)

    # =========================================
    # Subtask 3: Check Imperial units in config
    # =========================================
    tmp_conf = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
    tmp_conf.close()
    try:
        try:
            copy_from_env('/home/ga/.config/Subsurface/Subsurface.conf', tmp_conf.name)
            with open(tmp_conf.name) as f:
                conf = f.read()

            if 'unit_system=1' in conf:
                score += 25
                feedback_parts.append("Imperial units: set correctly")
            else:
                feedback_parts.append("Imperial units: not set (unit_system != 1)")
        except Exception as e:
            feedback_parts.append(f"Imperial units: could not read config ({e})")
    finally:
        if os.path.exists(tmp_conf.name):
            os.unlink(tmp_conf.name)

    # =========================================
    # Subtask 4: Check CSV export
    # =========================================
    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    tmp_csv.close()
    try:
        try:
            copy_from_env('/home/ga/Documents/safety_audit_export.csv', tmp_csv.name)
            file_size = os.path.getsize(tmp_csv.name)

            if file_size == 0:
                feedback_parts.append("CSV export: file exists but is empty")
            else:
                with open(tmp_csv.name, encoding='utf-8', errors='replace') as f:
                    reader = csv.reader(f)
                    rows = list(reader)
                data_rows = [r for r in rows[1:] if any(c.strip() for c in r)]

                if len(data_rows) >= 5:
                    score += 25
                    feedback_parts.append(
                        f"CSV export: {len(data_rows)} dive records exported")
                else:
                    score += 10
                    feedback_parts.append(
                        f"CSV export: only {len(data_rows)} rows (expected more)")

        except FileNotFoundError:
            feedback_parts.append("CSV export: file not found at expected path")
        except Exception as e:
            feedback_parts.append(f"CSV export: error reading file ({e})")
    finally:
        if os.path.exists(tmp_csv.name):
            os.unlink(tmp_csv.name)

    passed = score >= 50
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
