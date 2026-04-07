#!/usr/bin/env python3
"""Verifier for plan_tech_training_series task.

Checks that three planned dives were saved to the logbook with progressive
gas configurations, organized into a trip, with buddy and PDF export.

Scoring (100 points):
- File modified during task: 5 points
- 3+ new dives exist: 10 points
- Dive 1 (~30m, EAN32): 13 points
- Dive 2 (~40m, EAN32 + EAN50): 17 points
- Dive 3 (~50m, Trimix 21/35 + EAN50 + O2): 20 points
- Trip exists with relevant name: 10 points
- GPS near Blue Hole Dahab: 5 points
- Buddy on planned dives: 5 points
- PDF export exists: 10 points
- GF settings (30/70): 5 points

Pass threshold: 40 points
"""

import os
import re
import tempfile
import json
import xml.etree.ElementTree as ET


def verify_plan_tech_training_series(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp_ssrf = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    tmp_ssrf.close()
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_result.close()
    tmp_conf = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
    tmp_conf.close()
    tmp_pdf_check = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_pdf_check.close()
    tmp_ic = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_ic.close()

    try:
        # ---- Fetch files from environment ----
        try:
            copy_from_env('/home/ga/Documents/dives.ssrf', tmp_ssrf.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read dives.ssrf: {e}"}

        try:
            copy_from_env('/tmp/task_result.json', tmp_result.name)
            with open(tmp_result.name, 'r') as f:
                result = json.load(f)
        except Exception:
            result = {}

        try:
            copy_from_env('/tmp/plan_tech_training_series_initial_dive_count', tmp_ic.name)
            with open(tmp_ic.name) as f:
                initial_count = int(f.read().strip())
        except Exception:
            initial_count = 29  # fallback to known SampleDivesV2 count

        try:
            copy_from_env('/home/ga/.config/Subsurface/Subsurface.conf', tmp_conf.name)
            with open(tmp_conf.name, 'r') as f:
                conf_text = f.read()
        except Exception:
            conf_text = ""

        # ---- Parse SSRF XML ----
        try:
            tree = ET.parse(tmp_ssrf.name)
            root = tree.getroot()
        except ET.ParseError as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse SSRF XML: {e}"}

        score = 0
        feedback_parts = []

        # ---- 1. File modified (5 pts) ----
        task_start = result.get('task_start', 0)
        ssrf_mtime = result.get('ssrf_mtime', 0)
        if ssrf_mtime >= (task_start - 5):
            score += 5
            feedback_parts.append("File modified (+5)")
        else:
            feedback_parts.append("File not modified during task")

        # ---- 2. Dive count increased by >= 3 (10 pts) ----
        all_dives = list(root.iter('dive'))
        current_count = len(all_dives)
        new_dive_count = current_count - initial_count

        if new_dive_count >= 3:
            score += 10
            feedback_parts.append(f"3+ new dives ({initial_count}->{current_count}) (+10)")
        elif new_dive_count >= 1:
            score += 3
            feedback_parts.append(f"Only {new_dive_count} new dive(s) ({initial_count}->{current_count}) (+3)")
        else:
            feedback_parts.append(f"No new dives (count={current_count})")

        # ---- Helper functions ----
        def parse_depth(dive):
            for attr in ('depth', 'maxdepth'):
                ds = dive.get(attr, '')
                m = re.search(r'([0-9.]+)', ds)
                if m:
                    return float(m.group(1))
            return None

        def parse_duration_min(dive):
            dur = dive.get('duration', '')
            m = re.match(r'(\d+):(\d+)', dur)
            if m:
                return int(m.group(1)) + int(m.group(2)) / 60.0
            return None

        def get_cylinders(dive):
            cyls = []
            for cyl in dive.findall('cylinder'):
                o2_str = cyl.get('o2', '21%')
                he_str = cyl.get('he', '0%')
                try:
                    o2 = float(o2_str.replace('%', '').strip())
                except (ValueError, AttributeError):
                    o2 = 21.0
                try:
                    he = float(he_str.replace('%', '').strip())
                except (ValueError, AttributeError):
                    he = 0.0
                cyls.append({'o2': o2, 'he': he})
            return cyls

        def get_buddy(dive):
            b = dive.get('buddy', '')
            if not b:
                be = dive.find('buddy')
                if be is not None and be.text:
                    b = be.text
            return b.strip()

        # ---- Identify candidate planned dives (new dives not in original set) ----
        # Planned dives typically have divecomputer model containing "plan"
        # or they are simply new dives added after the initial count
        candidates = []
        for dive in all_dives:
            is_planned = False
            for dc in dive.findall('.//divecomputer'):
                if 'plan' in dc.get('model', '').lower():
                    is_planned = True
                    break
            mode = dive.get('dive_mode', '').lower()
            if 'plan' in mode or mode == '1':
                is_planned = True
            if is_planned:
                candidates.append(dive)

        # Fallback: if no planned dives found, use all dives with depth >= 25m
        # that have gas configs (likely the ones the agent added)
        if not candidates:
            for dive in all_dives:
                depth = parse_depth(dive)
                cyls = get_cylinders(dive)
                if depth and depth >= 25:
                    # Check if any cylinder has non-air gas
                    for c in cyls:
                        if c['o2'] > 22 or c['he'] > 0:
                            candidates.append(dive)
                            break

        # ---- 3. Score Dive 1: ~30m, EAN32 (13 pts) ----
        dive1_score = 0
        dive1_found = False
        for dive in candidates:
            d_score = 0
            depth = parse_depth(dive)
            dur = parse_duration_min(dive)
            cyls = get_cylinders(dive)

            # Depth ~30m (25-35m range)
            if depth and 25 <= depth <= 35:
                d_score += 5
                # Duration >= 25 min
                if dur and dur >= 25:
                    d_score += 3
                # Has EAN32 (O2 28-36%, no significant He)
                for c in cyls:
                    if 28 <= c['o2'] <= 36 and c['he'] <= 5:
                        d_score += 5
                        break

            if d_score > dive1_score:
                dive1_score = d_score
                dive1_found = True

        if dive1_found:
            score += dive1_score
            feedback_parts.append(f"Dive 1 (30m EAN32): +{dive1_score}")
        else:
            feedback_parts.append("Dive 1 (30m EAN32) not found")

        # ---- 4. Score Dive 2: ~40m, EAN32 + EAN50 (17 pts) ----
        dive2_score = 0
        dive2_found = False
        for dive in candidates:
            d_score = 0
            depth = parse_depth(dive)
            dur = parse_duration_min(dive)
            cyls = get_cylinders(dive)

            # Depth ~40m (35-45m range)
            if depth and 35 <= depth <= 45:
                d_score += 5
                # Duration >= 20 min
                if dur and dur >= 20:
                    d_score += 2
                # Has EAN32 bottom gas
                has_ean32 = False
                has_ean50 = False
                for c in cyls:
                    if 28 <= c['o2'] <= 36 and c['he'] <= 5:
                        has_ean32 = True
                    if 45 <= c['o2'] <= 55 and c['he'] <= 5:
                        has_ean50 = True
                if has_ean32:
                    d_score += 5
                if has_ean50:
                    d_score += 5

            if d_score > dive2_score:
                dive2_score = d_score
                dive2_found = True

        if dive2_found:
            score += dive2_score
            feedback_parts.append(f"Dive 2 (40m EAN32+EAN50): +{dive2_score}")
        else:
            feedback_parts.append("Dive 2 (40m EAN32+EAN50) not found")

        # ---- 5. Score Dive 3: ~50m, Trimix 21/35 + EAN50 + O2 (20 pts) ----
        dive3_score = 0
        dive3_found = False
        for dive in candidates:
            d_score = 0
            depth = parse_depth(dive)
            dur = parse_duration_min(dive)
            cyls = get_cylinders(dive)

            # Depth ~50m (45-55m range)
            if depth and 45 <= depth <= 55:
                d_score += 5
                # Duration >= 15 min
                if dur and dur >= 15:
                    d_score += 2
                # Has Trimix bottom gas (O2 18-25%, He 30-40%)
                has_trimix = False
                has_ean50 = False
                has_o2 = False
                for c in cyls:
                    if 18 <= c['o2'] <= 25 and 30 <= c['he'] <= 40:
                        has_trimix = True
                    if 45 <= c['o2'] <= 55 and c['he'] <= 5:
                        has_ean50 = True
                    if c['o2'] >= 95 and c['he'] <= 5:
                        has_o2 = True
                if has_trimix:
                    d_score += 5
                if has_ean50:
                    d_score += 4
                if has_o2:
                    d_score += 4

            if d_score > dive3_score:
                dive3_score = d_score
                dive3_found = True

        if dive3_found:
            score += dive3_score
            feedback_parts.append(f"Dive 3 (50m Trimix+EAN50+O2): +{dive3_score}")
        else:
            feedback_parts.append("Dive 3 (50m Trimix+EAN50+O2) not found")

        # ---- 6. Trip exists (10 pts) ----
        trip_found = False
        for trip in root.iter('trip'):
            trip_loc = trip.get('location', '').lower()
            if 'trimix' in trip_loc or 'dahab' in trip_loc or 'training' in trip_loc:
                trip_found = True
                break
        if not trip_found:
            for trip in root.iter('trip'):
                trip_loc = trip.get('location', '').lower()
                if 'advanced' in trip_loc or 'course' in trip_loc or 'blue hole' in trip_loc:
                    trip_found = True
                    break

        if trip_found:
            score += 10
            feedback_parts.append("Trip found (+10)")
        else:
            feedback_parts.append("No matching trip found")

        # ---- 7. GPS near Blue Hole (5 pts) ----
        gps_found = False
        ds_section = root.find('divesites')
        if ds_section is not None:
            for site in ds_section.findall('site'):
                gps_str = site.get('gps', '')
                if gps_str:
                    parts = gps_str.split()
                    if len(parts) >= 2:
                        try:
                            lat = float(parts[0])
                            lon = float(parts[1])
                            # Blue Hole Dahab: ~28.57N, ~34.54E (generous tolerance)
                            if 27.5 <= lat <= 29.5 and 33.5 <= lon <= 35.5:
                                gps_found = True
                                break
                        except ValueError:
                            pass

        if gps_found:
            score += 5
            feedback_parts.append("GPS near Blue Hole (+5)")
        else:
            feedback_parts.append("No GPS near Blue Hole found")

        # ---- 8. Buddy on planned dives (5 pts) ----
        buddy_count = 0
        for dive in candidates:
            buddy = get_buddy(dive)
            if 'ahmed' in buddy.lower() or 'hassan' in buddy.lower():
                buddy_count += 1

        if buddy_count >= 2:
            score += 5
            feedback_parts.append(f"Buddy on {buddy_count} dives (+5)")
        elif buddy_count == 1:
            score += 2
            feedback_parts.append(f"Buddy on 1 dive (+2)")
        else:
            feedback_parts.append("No buddy found on planned dives")

        # ---- 9. PDF exists (10 pts) ----
        pdf_exists = result.get('pdf_exists', False)
        pdf_size = result.get('pdf_size_bytes', 0)

        if pdf_exists and pdf_size > 1024:
            score += 10
            feedback_parts.append(f"PDF exported ({pdf_size} bytes) (+10)")
        elif pdf_exists:
            score += 3
            feedback_parts.append(f"PDF exists but small ({pdf_size} bytes) (+3)")
        else:
            feedback_parts.append("PDF not found")

        # ---- 10. GF settings (5 pts) ----
        gf_ok = False
        gf_low_match = re.search(r'gflow\s*=\s*(\d+)', conf_text, re.IGNORECASE)
        gf_high_match = re.search(r'gfhigh\s*=\s*(\d+)', conf_text, re.IGNORECASE)
        if gf_low_match and gf_high_match:
            gf_low_val = int(gf_low_match.group(1))
            gf_high_val = int(gf_high_match.group(1))
            if 28 <= gf_low_val <= 32 and 68 <= gf_high_val <= 72:
                gf_ok = True

        if gf_ok:
            score += 5
            feedback_parts.append("GF 30/70 configured (+5)")
        else:
            feedback_parts.append("GF settings not 30/70")

        # ---- Final scoring ----
        # Pass requires: at least 2 of 3 dives configured + file modified
        dives_configured = sum(1 for s in [dive1_score, dive2_score, dive3_score] if s >= 5)
        key_criteria_met = dives_configured >= 2 and (ssrf_mtime >= (task_start - 5))
        passed = (score >= 40) and key_criteria_met

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        for tmp_file in [tmp_ssrf, tmp_result, tmp_conf, tmp_pdf_check, tmp_ic]:
            if os.path.exists(tmp_file.name):
                os.unlink(tmp_file.name)
