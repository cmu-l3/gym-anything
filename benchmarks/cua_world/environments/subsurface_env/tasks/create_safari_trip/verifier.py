#!/usr/bin/env python3
"""Verifier for create_safari_trip task.

Checks that a multi-day trip 'Komodo Safari 2023' was created with 3 dives:
- Dive at Crystal Rock (2023-03-05, Nitrox 32, buddy Wayan Surya)
- Dive at Castle Rock (2023-03-05, Air, buddy Wayan Surya)
- Dive at Batu Bolong (2023-03-06, Nitrox 32, buddy Adi Pratama)

Scoring (100 points):
- Trip exists with correct name: 10 points
- Dive 1 (Crystal Rock) found with correct date: 10 points
- Dive 1 has correct gas (Nitrox 32): 5 points
- Dive 1 has correct buddy: 5 points
- Dive 2 (Castle Rock) found with correct date: 10 points
- Dive 2 has correct gas (Air): 5 points
- Dive 2 has correct buddy: 5 points
- Dive 3 (Batu Bolong) found with correct date: 10 points
- Dive 3 has correct gas (Nitrox 32): 5 points
- Dive 3 has correct buddy: 5 points
- At least 2 dives have tags: 10 points
- At least 2 dives have notes: 10 points
- All 3 dives have duration data: 10 points

Pass threshold: 60 points
"""

import os
import re
import tempfile
import xml.etree.ElementTree as ET


def verify_create_safari_trip(traj, env_info, task_info):
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

        # Check for trip with "Komodo" in the name
        trip_found = False
        for trip in root.iter('trip'):
            trip_loc = trip.get('location', '').lower()
            # Subsurface stores trip name in 'location' attribute of <trip>
            if 'komodo' in trip_loc or 'labuan bajo' in trip_loc:
                trip_found = True
                break

        # Also check trip elements for matching text
        if not trip_found:
            for trip in root.iter('trip'):
                trip_date = trip.get('date', '')
                if '2023-03' in trip_date:
                    trip_found = True
                    break

        if trip_found:
            score += 10
            feedback_parts.append("Trip found")
        else:
            feedback_parts.append("No Komodo trip found")

        # Find the three target dives by date
        march5_dives = []
        march6_dives = []
        for dive in root.iter('dive'):
            d = dive.get('date', '')
            if d == '2023-03-05':
                march5_dives.append(dive)
            elif d == '2023-03-06':
                march6_dives.append(dive)

        # Helper to extract location text
        def get_location(dive):
            loc = dive.find('location')
            if loc is not None and loc.text:
                return loc.text.lower()
            # Check divesiteid
            dsid = dive.get('divesiteid', '')
            if dsid:
                ds_section = root.find('divesites')
                if ds_section is not None:
                    for site in ds_section.findall('site'):
                        if site.get('uuid') == dsid:
                            return site.get('name', '').lower()
            return ''

        # Helper to get buddy
        def get_buddy(dive):
            b = dive.get('buddy', '')
            if not b:
                be = dive.find('buddy')
                if be is not None and be.text:
                    b = be.text
            return b.strip()

        # Helper to check gas
        def get_o2(dive):
            for cyl in dive.findall('cylinder'):
                o2_str = cyl.get('o2', '21%')
                try:
                    return float(o2_str.replace('%', '').strip())
                except (ValueError, AttributeError):
                    pass
            return None

        # Helper to check tags
        def get_tags(dive):
            return [t.strip().lower() for t in dive.get('tags', '').split(',') if t.strip()]

        # Helper to check notes
        def get_notes(dive):
            notes_elem = dive.find('notes')
            if notes_elem is not None:
                text_elem = notes_elem.find('text')
                if text_elem is not None and text_elem.text:
                    return text_elem.text.strip()
                if notes_elem.text:
                    return notes_elem.text.strip()
            return ''

        # Helper to check duration
        def get_duration_min(dive):
            dur_str = dive.get('duration', '')
            try:
                m = re.match(r'(\d+):(\d+)', dur_str)
                if m:
                    return int(m.group(1)) + int(m.group(2)) / 60
            except (ValueError, AttributeError):
                pass
            return None

        # Match Dive 1 - Crystal Rock (March 5)
        dive1 = None
        for d in march5_dives:
            loc = get_location(d)
            if 'crystal' in loc:
                dive1 = d
                break
        # Fallback: first March 5 dive with nitrox
        if dive1 is None:
            for d in march5_dives:
                o2 = get_o2(d)
                if o2 is not None and 30 <= o2 <= 34:
                    t = d.get('time', '')
                    if '09' in t or not t:
                        dive1 = d
                        break
        # Fallback: any March 5 morning dive
        if dive1 is None and march5_dives:
            dive1 = march5_dives[0]

        if dive1 is not None:
            score += 10
            feedback_parts.append("Dive 1 (Mar 5) found")
            o2 = get_o2(dive1)
            if o2 is not None and 30 <= o2 <= 34:
                score += 5
                feedback_parts.append(f"Dive 1 gas OK ({o2}%)")
            buddy = get_buddy(dive1)
            if 'wayan' in buddy.lower() or 'surya' in buddy.lower():
                score += 5
                feedback_parts.append("Dive 1 buddy OK")
        else:
            feedback_parts.append("Dive 1 not found")

        # Match Dive 2 - Castle Rock (March 5)
        dive2 = None
        for d in march5_dives:
            if d is dive1:
                continue
            loc = get_location(d)
            if 'castle' in loc:
                dive2 = d
                break
        if dive2 is None:
            for d in march5_dives:
                if d is dive1:
                    continue
                dive2 = d
                break

        if dive2 is not None:
            score += 10
            feedback_parts.append("Dive 2 (Mar 5) found")
            o2 = get_o2(dive2)
            if o2 is None or (o2 is not None and 19 <= o2 <= 22):
                score += 5
                feedback_parts.append("Dive 2 gas OK (air)")
            buddy = get_buddy(dive2)
            if 'wayan' in buddy.lower() or 'surya' in buddy.lower():
                score += 5
                feedback_parts.append("Dive 2 buddy OK")
        else:
            feedback_parts.append("Dive 2 not found")

        # Match Dive 3 - Batu Bolong (March 6)
        dive3 = None
        for d in march6_dives:
            loc = get_location(d)
            if 'batu' in loc or 'bolong' in loc:
                dive3 = d
                break
        if dive3 is None and march6_dives:
            dive3 = march6_dives[0]

        if dive3 is not None:
            score += 10
            feedback_parts.append("Dive 3 (Mar 6) found")
            o2 = get_o2(dive3)
            if o2 is not None and 30 <= o2 <= 34:
                score += 5
                feedback_parts.append(f"Dive 3 gas OK ({o2}%)")
            buddy = get_buddy(dive3)
            if 'adi' in buddy.lower() or 'pratama' in buddy.lower():
                score += 5
                feedback_parts.append("Dive 3 buddy OK")
        else:
            feedback_parts.append("Dive 3 not found")

        # Check tags across dives
        all_dives = [d for d in [dive1, dive2, dive3] if d is not None]
        dives_with_tags = sum(1 for d in all_dives if get_tags(d))
        if dives_with_tags >= 2:
            score += 10
            feedback_parts.append(f"Tags found on {dives_with_tags} dives")

        # Check notes across dives
        dives_with_notes = sum(1 for d in all_dives if get_notes(d))
        if dives_with_notes >= 2:
            score += 10
            feedback_parts.append(f"Notes found on {dives_with_notes} dives")

        # Check duration data across dives
        dives_with_dur = sum(1 for d in all_dives if get_duration_min(d) is not None)
        if dives_with_dur >= 3:
            score += 10
            feedback_parts.append(f"Duration data on {dives_with_dur} dives")

        passed = score >= 60
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts)
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
