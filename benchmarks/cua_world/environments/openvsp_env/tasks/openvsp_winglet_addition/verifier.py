#!/usr/bin/env python3
"""
Verifier for openvsp_winglet_addition task.

Checks that the agent added a winglet section to the eCRM-001 wing model:
  1. File exists and is valid XML (10 pts)
  2. Wing component present (5 pts)
  3. Wing has more sections than original (10 pts)
  4. Winglet section exists (Dihedral >= 55) (20 pts)
  5. Cant angle (Dihedral) in [60, 85] (15 pts)
  6. Span in [0.4, 1.5] (15 pts)
  7. Sweep in [20, 50] (10 pts)
  8. Taper in [0.15, 0.50] (10 pts)
  9. File modified during task (5 pts)

Pass threshold: 60.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_openvsp_winglet_addition(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    spec_dih = metadata.get('spec_dihedral_range', [60.0, 85.0])
    spec_span = metadata.get('spec_span_range', [0.4, 1.5])
    spec_sweep = metadata.get('spec_sweep_range', [20.0, 50.0])
    spec_taper = metadata.get('spec_taper_range', [0.15, 0.50])

    # Copy exported result from container
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/openvsp_winglet_result.json", local_tmp)
        with open(local_tmp, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback = []

    # Check 1: File Existence
    if not data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Target file eCRM001_winglet.vsp3 does not exist."}

    content = data.get('content', '')
    if not content:
        return {"passed": False, "score": 0, "feedback": "Target file is empty."}

    # Verify XML structure
    try:
        root = ET.fromstring(content)
        score += 10
        feedback.append("File is valid XML (+10)")
    except ET.ParseError:
        return {"passed": False, "score": 5, "feedback": "File is not valid XML (partial points applied)."}

    # Check 9: Anti-gaming (timestamp check)
    mtime = data.get('mtime', 0)
    task_start = data.get('task_start', 0)
    if mtime >= task_start:
        score += 5
        feedback.append("File created/modified during task (+5)")
    else:
        feedback.append("File modified before task start (failed anti-gaming check) (+0)")

    # Check 2: Wing Component Present
    has_wing = "WingGeom" in content or "<WingGeom>" in content
    if has_wing:
        score += 5
        feedback.append("Wing component present (+5)")
    else:
        feedback.append("Wing component missing (+0)")

    # Check 3: Wing Section Count
    current_dihedrals = content.count('<Dihedral ')
    orig_dihedrals = data.get('orig_dihedrals', 0)
    if current_dihedrals > orig_dihedrals:
        score += 10
        feedback.append(f"Added new sections (Count: {orig_dihedrals} -> {current_dihedrals}) (+10)")
    else:
        feedback.append("No new sections added (+0)")

    # Locate Winglet Section Container
    winglet_container = None
    for parent in root.iter():
        dihedral = parent.find('Dihedral')
        if dihedral is not None:
            val = float(dihedral.get('Value', 0))
            if val >= 55.0:
                winglet_container = parent
                break

    # Fallback/Regex checks if exact XML structure is unusual
    if not winglet_container:
        d_vals = re.findall(r'<Dihedral\s+Value="([^"]+)"', content)
        found_high_d = any(float(v) >= 55 for v in d_vals)
        if found_high_d:
            score += 20
            feedback.append("Winglet section found via regex fallback (+20)")
            # Loose parameter checks via regex
            s_vals = [float(v) for v in re.findall(r'<Span\s+Value="([^"]+)"', content)]
            sw_vals = [float(v) for v in re.findall(r'<Sweep\s+Value="([^"]+)"', content)]
            
            if any(spec_span[0] <= v <= spec_span[1] for v in s_vals):
                score += 15
                feedback.append("Found valid span (+15)")
            if any(spec_sweep[0] <= v <= spec_sweep[1] for v in sw_vals):
                score += 10
                feedback.append("Found valid sweep (+10)")
                
            score += 10
            feedback.append("Taper assumed valid in fallback (+10)")
        else:
            feedback.append("No winglet section (Dihedral >= 55) found (+0)")
            return {"passed": score >= 60, "score": score, "feedback": " | ".join(feedback)}
    else:
        score += 20
        feedback.append("Winglet section found (+20)")

        # Check 5: Cant Angle / Dihedral
        d_val = float(winglet_container.find('Dihedral').get('Value', 0))
        if spec_dih[0] <= d_val <= spec_dih[1]:
            score += 15
            feedback.append(f"Cant angle {d_val:.1f} in {spec_dih} (+15)")
        else:
            feedback.append(f"Cant angle {d_val:.1f} outside {spec_dih} (+0)")

        # Check 6: Span
        span_elem = winglet_container.find('Span')
        span_val = float(span_elem.get('Value', -1)) if span_elem is not None else -1
        if spec_span[0] <= span_val <= spec_span[1]:
            score += 15
            feedback.append(f"Span {span_val:.2f} in {spec_span} (+15)")
        else:
            feedback.append(f"Span {span_val:.2f} outside {spec_span} (+0)")

        # Check 7: Sweep
        sweep_elem = winglet_container.find('Sweep')
        sweep_val = float(sweep_elem.get('Value', -1)) if sweep_elem is not None else -1
        if spec_sweep[0] <= sweep_val <= spec_sweep[1]:
            score += 10
            feedback.append(f"Sweep {sweep_val:.1f} in {spec_sweep} (+10)")
        else:
            feedback.append(f"Sweep {sweep_val:.1f} outside {spec_sweep} (+0)")

        # Check 8: Taper
        taper_elem = winglet_container.find('Taper')
        if taper_elem is None:
            taper_elem = winglet_container.find('Taper_Ratio')
            
        taper_val = float(taper_elem.get('Value', -1)) if taper_elem is not None else -1
        if taper_val == -1:
            # Fallback to computing from Root and Tip chords
            tip = winglet_container.find('Tip_Chord')
            root_c = winglet_container.find('Root_Chord')
            if tip is not None and root_c is not None:
                tv = float(tip.get('Value', 0))
                rv = float(root_c.get('Value', 1))
                taper_val = tv / rv if rv != 0 else -1

        if spec_taper[0] <= taper_val <= spec_taper[1]:
            score += 10
            feedback.append(f"Taper {taper_val:.2f} in {spec_taper} (+10)")
        else:
            feedback.append(f"Taper {taper_val:.2f} outside {spec_taper} (+0)")

    passed = score >= 60
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}