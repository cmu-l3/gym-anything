#!/usr/bin/env python3
"""
Verifier for ekos_robotic_schedule_generation task.

Checks XML sequence (.esq) and schedule (.esl) files for correct tags and attributes.
Matches exposures, filter slots, counts, and altitude/moon constraints.
"""

import json
import base64
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_child_text(element, tag_name):
    """Helper to find a child tag (case-insensitive) and return its text."""
    for child in element:
        if child.tag.lower() == tag_name.lower():
            return child.text.strip() if child.text else ""
    return ""

def filter_match(actual, expected_aliases):
    """Matches filter name/slot to accepted aliases."""
    return actual.strip().lower() in [e.lower() for e in expected_aliases]

def verify_schedule_generation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    dir_exists = result.get('dir_exists', False)
    files = result.get('files', {})

    if dir_exists:
        score += 10
        feedback.append("Ekos directory created")
    else:
        feedback.append("Ekos directory missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Helper to decode file or return None if missing/stale
    def decode_file(b64_str):
        if not b64_str or b64_str in ["MISSING", "STALE"]:
            return None
        try:
            return base64.b64decode(b64_str).decode('utf-8', errors='ignore')
        except:
            return None

    m81_xml = decode_file(files.get('m81_lrgb.esq'))
    ngc1499_xml = decode_file(files.get('ngc1499_ha.esq'))
    m42_xml = decode_file(files.get('m42_hdr.esq'))
    master_xml = decode_file(files.get('master_schedule.esl'))

    # 1. Verify M81 Sequence (20 points)
    # Target: 10x60s Lum, 5x60s Red, 5x60s Green, 5x60s Blue
    m81_ok = False
    if m81_xml:
        try:
            root = ET.fromstring(m81_xml)
            jobs = root.findall('.//Job')
            if len(jobs) >= 4:
                expected_jobs_found = { 'L': False, 'R': False, 'G': False, 'B': False }
                for j in jobs:
                    f = get_child_text(j, 'Filter')
                    e = get_child_text(j, 'Exposure')
                    c = get_child_text(j, 'Count')
                    
                    if filter_match(f, ['1', 'l', 'luminance', 'lum']) and e == '60' and c == '10':
                        expected_jobs_found['L'] = True
                    elif filter_match(f, ['4', 'r', 'red']) and e == '60' and c == '5':
                        expected_jobs_found['R'] = True
                    elif filter_match(f, ['5', 'g', 'green']) and e == '60' and c == '5':
                        expected_jobs_found['G'] = True
                    elif filter_match(f, ['6', 'b', 'blue']) and e == '60' and c == '5':
                        expected_jobs_found['B'] = True
                        
                if all(expected_jobs_found.values()):
                    score += 20
                    m81_ok = True
                    feedback.append("M81 LRGB sequence valid")
                else:
                    feedback.append("M81 sequence missing expected filters/exposures/counts")
            else:
                feedback.append(f"M81 sequence has only {len(jobs)} jobs (expected 4)")
        except ET.ParseError:
            feedback.append("M81 sequence XML is malformed")
    else:
        feedback.append("M81 sequence file missing or stale")

    # 2. Verify NGC 1499 Sequence (15 points)
    # Target: 15x300s Ha
    ngc1499_ok = False
    if ngc1499_xml:
        try:
            root = ET.fromstring(ngc1499_xml)
            jobs = root.findall('.//Job')
            if len(jobs) >= 1:
                found = False
                for j in jobs:
                    f = get_child_text(j, 'Filter')
                    e = get_child_text(j, 'Exposure')
                    c = get_child_text(j, 'Count')
                    if filter_match(f, ['2', 'ha', 'h-alpha', 'halpha']) and e == '300' and c == '15':
                        found = True
                        break
                if found:
                    score += 15
                    ngc1499_ok = True
                    feedback.append("NGC 1499 Ha sequence valid")
                else:
                    feedback.append("NGC 1499 sequence missing expected Ha configuration")
            else:
                feedback.append("NGC 1499 sequence has no jobs")
        except ET.ParseError:
            feedback.append("NGC 1499 sequence XML is malformed")
    else:
        feedback.append("NGC 1499 sequence file missing or stale")

    # 3. Verify M42 Sequence (15 points)
    # Target: 5x10s Lum, 5x60s Lum
    m42_ok = False
    if m42_xml:
        try:
            root = ET.fromstring(m42_xml)
            jobs = root.findall('.//Job')
            if len(jobs) >= 2:
                expected = {'short': False, 'long': False}
                for j in jobs:
                    f = get_child_text(j, 'Filter')
                    e = get_child_text(j, 'Exposure')
                    c = get_child_text(j, 'Count')
                    if filter_match(f, ['1', 'l', 'luminance', 'lum']):
                        if e == '10' and c == '5': expected['short'] = True
                        if e == '60' and c == '5': expected['long'] = True
                if all(expected.values()):
                    score += 15
                    m42_ok = True
                    feedback.append("M42 HDR sequence valid")
                else:
                    feedback.append("M42 sequence missing expected HDR configuration")
            else:
                feedback.append(f"M42 sequence has only {len(jobs)} jobs (expected 2)")
        except ET.ParseError:
            feedback.append("M42 sequence XML is malformed")
    else:
        feedback.append("M42 sequence file missing or stale")

    # 4. Verify Master Schedule (40 points total)
    master_exists_score = 0
    master_targets_score = 0
    master_constraints_score = 0
    
    if master_xml:
        master_exists_score = 15
        try:
            root = ET.fromstring(master_xml)
            sched_jobs = root.findall('.//Job')
            
            # Target mapping
            target_linked = { 'm81': False, 'ngc1499': False, 'm42': False }
            constraints_ok = { 'm81': False, 'ngc1499': False, 'm42': False }
            
            for j in sched_jobs:
                seq_path = get_child_text(j, 'Sequence').lower()
                min_alt = get_child_text(j, 'MinAltitude')
                min_moon = get_child_text(j, 'MinMoonDist')
                
                if 'm81_lrgb.esq' in seq_path:
                    target_linked['m81'] = True
                    if min_alt == '30': constraints_ok['m81'] = True
                        
                elif 'ngc1499_ha.esq' in seq_path:
                    target_linked['ngc1499'] = True
                    if min_alt == '20' and min_moon == '40': constraints_ok['ngc1499'] = True
                        
                elif 'm42_hdr.esq' in seq_path:
                    target_linked['m42'] = True
                    if min_alt == '25': constraints_ok['m42'] = True
            
            # Add points based on what was found
            if all(target_linked.values()):
                master_targets_score = 15
                feedback.append("Master schedule links all 3 sequence files")
            else:
                found_targets = sum(target_linked.values())
                master_targets_score = 5 * found_targets
                feedback.append(f"Master schedule links {found_targets}/3 sequence files")
                
            if all(constraints_ok.values()):
                master_constraints_score = 10
                feedback.append("All environmental constraints applied correctly")
            else:
                feedback.append("Some/All environmental constraints incorrect or missing")

        except ET.ParseError:
            feedback.append("Master schedule XML is malformed")
            
        score += master_exists_score + master_targets_score + master_constraints_score
    else:
        feedback.append("Master schedule file missing or stale")

    # Final logic
    # Need directory created, master schedule, and at least two sequence files perfect to pass.
    seqs_ok_count = sum([m81_ok, ngc1499_ok, m42_ok])
    passed = score >= 70 and master_exists_score == 15 and seqs_ok_count >= 2

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }