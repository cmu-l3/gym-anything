#!/usr/bin/env python3
"""
Verifier for airframe_splice_coupler_retrofit task.

Verification checks OpenRocket's internal component tree (XML inside the .ork ZIP).
In OpenRocket, physical front-to-back layout is determined by the order of components
in the tree, and parent-child relationships dictate physical attachment.

Scoring breakdown (100 points total):
  25 pts - Dual Airframe Structure: XML contains exactly two main body tubes (lengths 10-18cm each).
  15 pts - Structural Coupler: A tube coupler component is present inside one of the body tubes.
  20 pts - Fins Correctly Re-parented: The fin set is a child of the Aft (second) body tube.
  15 pts - Motor Mount Re-parented: The inner tube is a child of the Aft (second) body tube.
  15 pts - Powered Simulation: An 'uptodate' simulation exists showing an apogee > 50m.
  10 pts - Repair Summary Report: Text file exists with reasonable size.

Pass threshold: 70 points
"""

import os
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET


def _parse_ork(local_path):
    """Parse .ork ZIP+XML and return (root_element, error_string)."""
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        root = ET.fromstring(xml_bytes.decode('utf-8'))
        return root, None
    except zipfile.BadZipFile:
        try:
            tree = ET.parse(local_path)
            return tree.getroot(), None
        except Exception as e:
            return None, f"Could not parse .ork as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"


def verify_airframe_splice_coupler_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/spliced_airframe.ork')

    score = 0
    feedback_parts = []
    
    # ---- Read Exported JSON ----
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/splice_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if not result.get('ork_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Modified rocket file was not saved to expected location."
        }

    # ---- Copy .ork file from VM ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) or "Failed to retrieve rocket file."
        }

    # OpenRocket Component Tree: <rocket> -> <subcomponents> -> <stage> -> <subcomponents> -> <bodytube>
    stage_sub = ork_root.find('.//stage/subcomponents')
    if stage_sub is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not find stage subcomponents in XML (corrupt design)."
        }

    main_bodytubes = list(stage_sub.findall('bodytube'))

    # ---- Criterion 1: Dual Airframe Structure (25 points) ----
    if len(main_bodytubes) == 2:
        l1 = float(main_bodytubes[0].findtext('length', '0'))
        l2 = float(main_bodytubes[1].findtext('length', '0'))
        if 0.10 <= l1 <= 0.18 and 0.10 <= l2 <= 0.18:
            score += 25
            feedback_parts.append("Dual Airframe Structure (2 body tubes, correct lengths) [25/25 pts]")
        else:
            score += 10
            feedback_parts.append(f"Two body tubes found but lengths are incorrect ({l1:.3f}m, {l2:.3f}m) [10/25 pts]")
    else:
        feedback_parts.append(f"Expected exactly 2 main body tubes, found {len(main_bodytubes)} [0/25 pts]")

    # ---- Criterion 2: Structural Coupler (15 points) ----
    coupler_found = False
    for bt in main_bodytubes:
        sub = bt.find('subcomponents')
        if sub is not None:
            if sub.find('tubecoupler') is not None:
                coupler_found = True
                break
    
    if coupler_found:
        score += 15
        feedback_parts.append("Structural Coupler found [15/15 pts]")
    else:
        feedback_parts.append("Structural Coupler not found inside body tubes [0/15 pts]")

    # ---- Criteria 3 & 4: Re-parenting to Aft tube (20 + 15 points) ----
    if len(main_bodytubes) >= 2:
        aft_bt = main_bodytubes[1]  # The second body tube acts as the Aft section
        aft_sub = aft_bt.find('subcomponents')
        if aft_sub is not None:
            
            # Check Fins
            has_fins = False
            for fin_tag in ['trapezoidfinset', 'ellipticalfinset', 'freeformfinset']:
                if aft_sub.find(fin_tag) is not None:
                    has_fins = True
                    break
            
            if has_fins:
                score += 20
                feedback_parts.append("Fins correctly re-parented to Aft tube [20/20 pts]")
            else:
                feedback_parts.append("Fins NOT found on Aft tube [0/20 pts]")

            # Check Motor Mount (innertube)
            if aft_sub.find('innertube') is not None:
                score += 15
                feedback_parts.append("Motor Mount (innertube) re-parented to Aft tube [15/15 pts]")
            else:
                feedback_parts.append("Motor Mount NOT found on Aft tube [0/15 pts]")
        else:
            feedback_parts.append("Aft tube has no subcomponents [0/35 pts]")
    else:
        feedback_parts.append("Could not check Aft tube reparenting (not enough body tubes)")

    # ---- Criterion 5: Powered Simulation Run (15 points) ----
    sims = ork_root.find('simulations')
    uptodate_sim = False
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        apogee = float(fd.get('maxaltitude', '0'))
                        if apogee > 50.0:  # Confirms motor is assigned and firing
                            uptodate_sim = True
                            break
                    except (ValueError, TypeError):
                        pass

    if uptodate_sim:
        score += 15
        feedback_parts.append("Powered Simulation Run with Apogee > 50m [15/15 pts]")
    else:
        feedback_parts.append("No uptodate simulation with powered flight found [0/15 pts]")

    # ---- Criterion 6: Repair Summary Report (10 points) ----
    report_exists = result.get('report_exists', False)
    if report_exists and result.get('report_size', 0) > 10:
        score += 10
        feedback_parts.append("Repair Summary Report exists [10/10 pts]")
    else:
        feedback_parts.append("Repair Summary Report missing or empty [0/10 pts]")

    pass_threshold = metadata.get('pass_threshold', 70)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }