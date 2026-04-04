#!/usr/bin/env python3
"""Verifier for plan_basic_dive task.

Checks that a planned dive with 30m depth / 40min duration on air was created,
either as a saved dive in the SSRF file or visible in the dive planner UI.
Uses VLM screenshot check as primary method for the planner UI case.
"""

import os
import tempfile
import xml.etree.ElementTree as ET


def verify_plan_basic_dive(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')

    # Method 1: Check for a planned dive saved in the SSRF file
    if copy_from_env:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
        tmp.close()
        try:
            try:
                copy_from_env('/home/ga/Documents/dives.ssrf', tmp.name)
                tree = ET.parse(tmp.name)
                root = tree.getroot()

                # Look for a dive with dive_mode="planned" or similar indicator
                for dive in root.iter('dive'):
                    mode = dive.get('dive_mode', '').lower()
                    depth_str = dive.get('depth', '')
                    duration_str = dive.get('duration', '')

                    # Check if this looks like a planned dive
                    is_planned = 'plan' in mode

                    # Check depth ~30m and duration ~40min
                    depth_ok = False
                    dur_ok = False

                    try:
                        depth_val = float(depth_str.replace('m', '').strip())
                        depth_ok = 25 <= depth_val <= 35
                    except (ValueError, AttributeError):
                        pass

                    if '40' in duration_str or '39' in duration_str or '41' in duration_str:
                        dur_ok = True

                    # Check gas (air = ~21% O2, 0% He)
                    has_air = False
                    for cyl in dive.findall('cylinder'):
                        o2 = cyl.get('o2', '21%')
                        he = cyl.get('he', '0%')
                        try:
                            o2_val = float(o2.replace('%', '').strip())
                            he_val = float(he.replace('%', '').strip())
                            if 20 <= o2_val <= 22 and he_val == 0:
                                has_air = True
                                break
                        except ValueError:
                            pass

                    if is_planned and depth_ok and dur_ok:
                        return {
                            "passed": True,
                            "score": 100,
                            "feedback": f"Planned dive found: depth={depth_str}, duration={duration_str}, air={has_air}"
                        }
            except Exception:
                pass
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # Method 2: VLM screenshot check for the dive planner UI
    if query_vlm and get_final_screenshot:
        screenshot = get_final_screenshot(traj)
        if screenshot:
            result = query_vlm(
                prompt=(
                    "Is the Subsurface dive planner visible with these parameters set: "
                    "depth = 30 meters, time/duration = 40 minutes, gas = air (21% O2)? "
                    "Answer YES or NO and briefly explain what you see."
                ),
                image=screenshot
            )
            response = result.get('response', '').upper()
            if 'YES' in response:
                return {
                    "passed": True,
                    "score": 90,
                    "feedback": f"Dive planner shows correct parameters (VLM confirmed). Response: {result.get('response', '')[:100]}"
                }

    return {
        "passed": False,
        "score": 0,
        "feedback": "Could not verify planned dive — no planned dive in SSRF and planner UI not confirmed"
    }
