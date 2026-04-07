#!/usr/bin/env python3
"""
Verifier for action_camera_retrofit task.

Scoring breakdown (100 points total):
  20 pts - 150g camera mass component added to the body tube.
  20 pts - Ballast mass component (>0g) added to the nose cone.
  20 pts - Time-series CSV data exported with valid Stability margin >= 1.50 calibers.
  15 pts - Anti-gaming / Sim up-to-date: CSV max altitude matches XML flightdata max altitude.
  10 pts - Written retrofit report exists and contains text.
  15 pts - VLM verification of trajectory (evidence of component menus and export).

Pass threshold: 65 points
"""

import os
import tempfile
import zipfile
import json
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


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


def _parse_csv_metrics(csv_path):
    """Parse OpenRocket CSV to extract max altitude and stability margins."""
    stability_margins = []
    max_alt = 0.0
    valid_csv = False

    if not os.path.exists(csv_path):
        return valid_csv, max_alt, stability_margins

    try:
        with open(csv_path, 'r', encoding='utf-8', errors='ignore') as f:
            headers = []
            for line in f:
                line = line.strip()
                if line.startswith('# Time'):
                    headers = [h.strip() for h in line.strip('#').split(',')]
                    valid_csv = True
                elif not line.startswith('#') and line:
                    parts = line.split(',')
                    if len(parts) == len(headers):
                        # Safely extract altitude
                        try:
                            alt_idx = next(i for i, h in enumerate(headers) if 'Altitude' in h)
                            max_alt = max(max_alt, float(parts[alt_idx]))
                        except (StopIteration, ValueError):
                            pass
                        
                        # Safely extract stability margin
                        try:
                            stab_idx = next(i for i, h in enumerate(headers) if 'Stability margin' in h)
                            stability_margins.append(float(parts[stab_idx]))
                        except (StopIteration, ValueError):
                            pass
    except Exception as e:
        logger.error(f"Error parsing CSV: {e}")

    return valid_csv, max_alt, stability_margins


def verify_action_camera_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('output_ork', '/home/ga/Documents/rockets/camera_retrofitted.ork')
    csv_vm_path = metadata.get('output_csv', '/home/ga/Documents/exports/camera_flight.csv')
    report_vm_path = metadata.get('output_report', '/home/ga/Documents/exports/retrofit_report.txt')
    expected_camera_mass = metadata.get('expected_camera_mass_kg', 0.15)
    target_stability = metadata.get('target_stability_calibers', 1.50)

    score = 0
    feedback_parts = []

    # ================================================================
    # 1. ORK FILE PARSING & COMPONENT CHECKS
    # ================================================================
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception:
        feedback_parts.append("Could not retrieve camera_retrofitted.ork")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    xml_max_alt = 0.0
    camera_found = False
    ballast_found = False

    if ork_root is not None:
        # Build parent map to identify where mass components are attached
        parent_map = {c: p for p in ork_root.iter() for c in p}
        
        for mc in ork_root.findall('.//masscomponent'):
            parent = parent_map.get(mc)
            if parent is not None:
                try:
                    mass_val = float(mc.findtext('mass', '0'))
                except ValueError:
                    mass_val = 0.0
                
                # Check for camera in bodytube (allow +/- 5g tolerance for typical UI rounding)
                if parent.tag == 'bodytube' and (expected_camera_mass - 0.005 <= mass_val <= expected_camera_mass + 0.005):
                    camera_found = True
                
                # Check for ballast in nosecone
                elif parent.tag == 'nosecone' and mass_val > 0.001:
                    ballast_found = True

        if camera_found:
            score += 20
            feedback_parts.append("150g Camera added to Body Tube [20/20 pts]")
        else:
            feedback_parts.append("150g Camera NOT found in Body Tube [0/20 pts]")

        if ballast_found:
            score += 20
            feedback_parts.append("Ballast added to Nose Cone [20/20 pts]")
        else:
            feedback_parts.append("Ballast NOT found in Nose Cone [0/20 pts]")

        # Extract max altitude from XML simulations to cross-reference CSV
        for sim in ork_root.findall('.//simulation'):
            if sim.get('status') == 'uptodate':
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        xml_max_alt = max(xml_max_alt, float(fd.get('maxaltitude', '0')))
                    except ValueError:
                        pass

    # ================================================================
    # 2. CSV FLIGHT DATA CHECKS
    # ================================================================
    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    tmp_csv.close()
    valid_csv = False
    csv_max_alt = 0.0
    stability_margins = []
    
    try:
        copy_from_env(csv_vm_path, tmp_csv.name)
        valid_csv, csv_max_alt, stability_margins = _parse_csv_metrics(tmp_csv.name)
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_csv.name):
            os.unlink(tmp_csv.name)

    if valid_csv and stability_margins:
        # We take the maximum stability margin recorded or check if the first stable phase is >= 1.5
        # OpenRocket stability can fluctuate; checking if it ever reaches >= target stability safely off the rod
        achieved_stability = max(stability_margins)
        if achieved_stability >= target_stability:
            score += 20
            feedback_parts.append(f"CSV exported, stability reached {achieved_stability:.2f} >= {target_stability} [20/20 pts]")
        else:
            feedback_parts.append(f"CSV exported, but max stability {achieved_stability:.2f} < {target_stability} [0/20 pts]")
            
        # Anti-gaming: Ensure CSV max altitude roughly matches the XML (simulation was actually run in this file)
        if xml_max_alt > 0 and abs(csv_max_alt - xml_max_alt) / xml_max_alt < 0.10:
            score += 15
            feedback_parts.append("Simulation up-to-date and CSV matches XML physics [15/15 pts]")
        else:
            feedback_parts.append("CSV altitude data does not match an uptodate .ork simulation (possible fake data) [0/15 pts]")
    else:
        feedback_parts.append("Valid CSV flight data not found [0/35 pts]")

    # ================================================================
    # 3. REPORT EXISTENCE
    # ================================================================
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_valid = False
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 20:
            report_valid = True
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    if report_valid:
        score += 10
        feedback_parts.append("Retrofit report exists [10/10 pts]")
    else:
        feedback_parts.append("Retrofit report missing or empty [0/10 pts]")

    # ================================================================
    # 4. VLM PROCESS VERIFICATION (TRAJECTORY)
    # ================================================================
    vlm_points = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            # Sample frames to see if they opened Mass Component menus and Export menus
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                prompt = """You are evaluating screenshots from an agent using OpenRocket.
Did the agent perform the necessary workflow to complete this task? 
Look for evidence of:
1. COMPONENT_EDIT: Editing 'Mass Components' (dialog boxes with mass/position settings).
2. EXPORT_DATA: The 'Export data' dialog or CSV saving window.

Respond strictly in JSON format:
{
    "component_edit_visible": true/false,
    "export_dialog_visible": true/false
}"""
                result = query_vlm(prompt=prompt, images=frames)
                if result and result.get("success"):
                    parsed = result.get("parsed", {})
                    if parsed.get("component_edit_visible"):
                        vlm_points += 8
                    if parsed.get("export_dialog_visible"):
                        vlm_points += 7
                
                score += vlm_points
                feedback_parts.append(f"VLM trajectory verification [{vlm_points}/15 pts]")
            else:
                feedback_parts.append("No trajectory frames available for VLM [0/15 pts]")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification failed [0/15 pts]")
    else:
        feedback_parts.append("VLM not available [0/15 pts]")

    # ================================================================
    # FINAL EVALUATION
    # ================================================================
    passed = score >= metadata.get('pass_threshold', 65)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }