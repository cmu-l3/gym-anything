#!/usr/bin/env python3
"""Verifier for add_nitrox_cylinder task.

Checks that Dive #3 in the saved SSRF file has a nitrox (EAN32) cylinder added.
"""

import os
import tempfile
import xml.etree.ElementTree as ET


def verify_add_nitrox_cylinder(traj, env_info, task_info):
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

        # Find dive number 3
        dive3 = None
        for dive in root.iter('dive'):
            if dive.get('number') == '3':
                dive3 = dive
                break

        if dive3 is None:
            return {"passed": False, "score": 0, "feedback": "Dive #3 not found in SSRF file"}

        # Check cylinders
        cylinders = dive3.findall('cylinder')
        if not cylinders:
            return {"passed": False, "score": 0,
                    "feedback": "Dive #3 has no cylinder elements"}

        # Look for EAN32 (32% O2) cylinder
        nitrox_cyl = None
        for cyl in cylinders:
            o2 = cyl.get('o2', '0%')
            # Remove % sign and check if close to 32
            try:
                o2_val = float(o2.replace('%', '').strip())
                if 30 <= o2_val <= 34:
                    nitrox_cyl = cyl
                    break
            except ValueError:
                pass

        if nitrox_cyl is None:
            o2_vals = [c.get('o2', 'none') for c in cylinders]
            return {
                "passed": False,
                "score": 20,
                "feedback": f"Dive #3 has {len(cylinders)} cylinder(s) but none with ~32% O2. O2 values: {o2_vals}"
            }

        # Check size and pressure
        size = nitrox_cyl.get('size', '')
        pressure = nitrox_cyl.get('workpressure', '')

        has_size = '12' in size or '11' in size or '10' in size  # ~12L
        has_pressure = '200' in pressure or '210' in pressure    # ~200 bar

        score = 60 + (20 if has_size else 0) + (20 if has_pressure else 0)

        return {
            "passed": True,
            "score": score,
            "feedback": (f"EAN32 cylinder found on Dive #3. "
                         f"o2={nitrox_cyl.get('o2')}, size={size}, pressure={pressure}")
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
