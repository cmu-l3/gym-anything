#!/usr/bin/env python3
"""Verifier for audit_fix_gas_configs task.

Checks that the three injected gas configuration errors have been corrected:
- Dive #85: O2 was set to 50% (unsafe for ~27m depth) -> should be <= 32%
- Dive #86: Cylinder size was set to 3.0L (too small) -> should be >= 7.0L
- Dive #87: Working pressure was set to 50 bar (too low) -> should be >= 150 bar

Scoring (100 points):
- Dive #85 O2 corrected: 33 points
- Dive #86 size corrected: 33 points
- Dive #87 working pressure corrected: 34 points

Pass threshold: 66 points (2 of 3 errors fixed)
"""

import os
import re
import tempfile
import xml.etree.ElementTree as ET


def verify_audit_fix_gas_configs(traj, env_info, task_info):
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

        # Helper to parse percentage value
        def parse_pct(val):
            try:
                return float(val.replace('%', '').strip())
            except (ValueError, AttributeError):
                return None

        # Helper to parse size in liters
        def parse_size(val):
            try:
                return float(re.sub(r'[^0-9.]', '', val.strip()))
            except (ValueError, AttributeError):
                return None

        # Helper to parse pressure in bar
        def parse_pressure(val):
            try:
                return float(re.sub(r'[^0-9.]', '', val.strip()))
            except (ValueError, AttributeError):
                return None

        for dive in root.iter('dive'):
            num = dive.get('number', '')

            if num == '85':
                # Check O2: should be corrected from 50% to something <= 32%
                # (appropriate for the recorded depth of ~27m)
                for cyl in dive.findall('cylinder'):
                    o2_val = parse_pct(cyl.get('o2', ''))
                    if o2_val is not None:
                        if o2_val <= 32:
                            score += 33
                            feedback_parts.append(
                                f"Dive #85 O2 corrected to {o2_val}% (was 50%)")
                        else:
                            feedback_parts.append(
                                f"Dive #85 O2 still unsafe at {o2_val}% (needs <= 32%)")
                        break
                else:
                    feedback_parts.append("Dive #85: no cylinder found")

            elif num == '86':
                # Check size: should be corrected from 3.0L to >= 7.0L
                for cyl in dive.findall('cylinder'):
                    size_val = parse_size(cyl.get('size', ''))
                    if size_val is not None:
                        if size_val >= 7.0:
                            score += 33
                            feedback_parts.append(
                                f"Dive #86 cylinder size corrected to {size_val}L (was 3.0L)")
                        else:
                            feedback_parts.append(
                                f"Dive #86 cylinder still too small at {size_val}L (needs >= 7L)")
                        break
                else:
                    feedback_parts.append("Dive #86: no cylinder found")

            elif num == '87':
                # Check working pressure: should be corrected from 50 bar to >= 150 bar
                for cyl in dive.findall('cylinder'):
                    wp_val = parse_pressure(cyl.get('workpressure', ''))
                    if wp_val is not None:
                        if wp_val >= 150:
                            score += 34
                            feedback_parts.append(
                                f"Dive #87 working pressure corrected to {wp_val} bar (was 50)")
                        else:
                            feedback_parts.append(
                                f"Dive #87 working pressure still too low at {wp_val} bar (needs >= 150)")
                        break
                else:
                    feedback_parts.append("Dive #87: no cylinder found")

        passed = score >= 66
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) if feedback_parts else "No target dives found"
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
