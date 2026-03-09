#!/usr/bin/env python3
"""Verifier for plan_tech_deco_dive task.

Checks that a planned dive was saved to the logbook with:
- Depth approximately 50m
- Bottom time approximately 20 min
- Bottom gas: Trimix 21/35 (O2~21%, He~35%)
- Deco gas: EAN50 (O2~50%)

Scoring (100 points):
- Planned dive exists with correct depth: 25 points
- Duration approximately correct: 25 points
- Bottom gas is trimix with correct O2/He: 25 points
- Deco gas with ~50% O2 present: 25 points

Pass threshold: 50 points
"""

import os
import re
import tempfile
import xml.etree.ElementTree as ET


def verify_plan_tech_deco_dive(traj, env_info, task_info):
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

        # Read baseline count of planned dives
        initial_count = 0
        try:
            copy_from_env('/tmp/plan_tech_deco_dive_initial_planned_count', '/tmp/_ptdd_ic.txt')
            with open('/tmp/_ptdd_ic.txt') as f:
                initial_count = int(f.read().strip())
            os.unlink('/tmp/_ptdd_ic.txt')
        except Exception:
            pass

        # Find all planned dives
        planned_dives = []
        for dive in root.iter('dive'):
            mode = dive.get('dive_mode', '').lower()
            # Subsurface marks planned dives with dive_mode="1" or "planned"
            if 'plan' in mode or mode == '1':
                planned_dives.append(dive)

        # Also check for any new dive that has trimix gas (likely a planned dive)
        # as Subsurface might store the mode differently
        trimix_dives = []
        for dive in root.iter('dive'):
            cyls = dive.findall('cylinder')
            for cyl in cyls:
                he = cyl.get('he', '0%')
                try:
                    he_val = float(he.replace('%', '').strip())
                    if he_val > 10:
                        trimix_dives.append(dive)
                        break
                except (ValueError, AttributeError):
                    pass

        # Combine candidates (prefer planned dives, fallback to trimix dives)
        candidates = planned_dives if planned_dives else trimix_dives

        if not candidates:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No planned dive or trimix dive found in the logbook"
            }

        # Score the best candidate
        best_score = 0
        best_feedback = []

        for dive in candidates:
            score = 0
            feedback_parts = []

            # Check depth (~50m)
            depth_str = dive.get('depth', '')
            depth_val = None
            try:
                depth_val = float(re.sub(r'[^0-9.]', '', depth_str))
            except (ValueError, AttributeError):
                pass

            if depth_val is not None and 45 <= depth_val <= 55:
                score += 25
                feedback_parts.append(f"depth={depth_val}m OK")
            else:
                feedback_parts.append(f"depth={depth_str} (expected ~50m)")

            # Check duration (~20 min bottom time)
            # Total dive time will be longer due to deco, but bottom time ~20min
            dur_str = dive.get('duration', '')
            dur_ok = False
            try:
                m = re.match(r'(\d+):(\d+)', dur_str)
                if m:
                    total_min = int(m.group(1)) + int(m.group(2)) / 60
                    # Total time including deco could be 40-90+ min
                    # Bottom time is 20 min, but total stored could be much more
                    if total_min >= 15:
                        dur_ok = True
                        score += 25
            except (ValueError, AttributeError):
                pass
            if dur_ok:
                feedback_parts.append(f"duration={dur_str} OK")
            else:
                feedback_parts.append(f"duration={dur_str} (expected >= 20min)")

            # Check cylinders for trimix bottom gas (O2~21%, He~35%)
            cyls = dive.findall('cylinder')
            has_trimix = False
            has_deco = False

            for cyl in cyls:
                o2_str = cyl.get('o2', '21%')
                he_str = cyl.get('he', '0%')
                try:
                    o2_val = float(o2_str.replace('%', '').strip())
                    he_val = float(he_str.replace('%', '').strip())
                except (ValueError, AttributeError):
                    continue

                # Bottom gas: O2 18-25%, He 30-40%
                if 18 <= o2_val <= 25 and 30 <= he_val <= 40:
                    has_trimix = True

                # Deco gas: O2 45-55%, He 0-5%
                if 45 <= o2_val <= 55 and he_val <= 5:
                    has_deco = True

            if has_trimix:
                score += 25
                feedback_parts.append("trimix bottom gas found")
            else:
                feedback_parts.append("no trimix bottom gas found")

            if has_deco:
                score += 25
                feedback_parts.append("EAN50 deco gas found")
            else:
                feedback_parts.append("no EAN50 deco gas found")

            if score > best_score:
                best_score = score
                best_feedback = feedback_parts

        passed = best_score >= 50
        return {
            "passed": passed,
            "score": best_score,
            "feedback": " | ".join(best_feedback)
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
