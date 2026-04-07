#!/usr/bin/env python3
"""
Verifier for nose_cone_drag_optimization task.

Verification Strategy (Programmatic via XML Parsing):
1. Retrieve the saved .ork file from the environment.
2. Verify the nose cone shape is an aerodynamic profile (not conical).
3. Verify the nose cone length is >= 120mm (0.12m).
4. Verify at least one simulation has 'uptodate' status.
5. Verify a trade study report was written with meaningful content.

Scoring breakdown (100 points total):
  25 pts - Nose cone shape changed from conical to ogive/haack/etc
  20 pts - Nose cone length increased to >= 120mm
  20 pts - Simulation ran ('uptodate' status)
  10 pts - File saved to exactly the expected path
  10 pts - Trade study report file exists
  15 pts - Trade study report quality/keywords
  
Pass Threshold: 60 points
"""

import os
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


def verify_nose_cone_drag_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_ork_path = metadata.get('expected_ork_path', '/home/ga/Documents/rockets/optimized_nosecone_rocket.ork')
    fallback_ork_path = metadata.get('fallback_ork_path', '/home/ga/Documents/rockets/drag_issue_rocket.ork')
    report_path = metadata.get('report_path', '/home/ga/Documents/exports/nosecone_trade_study.txt')
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch .ork file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    
    ork_found = False
    saved_as_expected = False
    
    # Check expected path first
    try:
        copy_from_env(expected_ork_path, tmp_ork.name)
        if os.path.exists(tmp_ork.name) and os.path.getsize(tmp_ork.name) > 100:
            ork_found = True
            saved_as_expected = True
    except Exception:
        pass
        
    # Check fallback path if expected path not found
    if not ork_found:
        try:
            copy_from_env(fallback_ork_path, tmp_ork.name)
            if os.path.exists(tmp_ork.name) and os.path.getsize(tmp_ork.name) > 100:
                ork_found = True
        except Exception:
            pass
            
    if not ork_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not find modified .ork file at expected or fallback paths"
        }
        
    # Evaluate Save Path
    if saved_as_expected:
        score += 10
        feedback_parts.append("File saved to correct path [10/10 pts]")
    else:
        score += 5
        feedback_parts.append("File saved over original (not to optimized_nosecone_rocket.ork) [5/10 pts]")
        
    # Parse the XML
    ork_root, parse_err = _parse_ork(tmp_ork.name)
    if os.path.exists(tmp_ork.name):
        os.unlink(tmp_ork.name)
        
    if not ork_root:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + f" | Parse error: {parse_err}"}
        
    # 2 & 3. Evaluate Nose Cone Shape and Length
    nc_shape = 'unknown'
    nc_length = 0.0
    for nc in ork_root.iter('nosecone'):
        shape_el = nc.find('shape')
        if shape_el is not None and shape_el.text:
            nc_shape = shape_el.text.lower().strip()
            
        len_el = nc.find('length')
        if len_el is not None and len_el.text:
            try:
                nc_length = float(len_el.text)
            except ValueError:
                pass
        break  # Only check the primary nose cone

    aerodynamic_shapes = ['ogive', 'haack', 'power', 'parabolic', 'ellipsoid']
    if nc_shape in aerodynamic_shapes:
        score += 25
        feedback_parts.append(f"Nose cone shape optimized ({nc_shape}) [25/25 pts]")
    else:
        feedback_parts.append(f"Nose cone shape is '{nc_shape}' (not optimized) [0/25 pts]")
        
    if nc_length >= 0.12:
        score += 20
        feedback_parts.append(f"Nose cone length {nc_length*1000:.0f}mm >= 120mm [20/20 pts]")
    elif nc_length > 0.055:
        score += 10
        feedback_parts.append(f"Nose cone length {nc_length*1000:.0f}mm improved but < 120mm [10/20 pts]")
    else:
        feedback_parts.append(f"Nose cone length {nc_length*1000:.0f}mm too short [0/20 pts]")
        
    # 4. Evaluate Simulation Status
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                
    if uptodate_count > 0:
        score += 20
        feedback_parts.append(f"Simulation(s) up-to-date ({uptodate_count} found) [20/20 pts]")
    else:
        feedback_parts.append("No up-to-date simulation found [0/20 pts]")
        
    # 5. Evaluate Trade Study Report
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_text = ""
    
    try:
        copy_from_env(report_path, tmp_report.name)
        if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 0:
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_text = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)
            
    if len(report_text) >= 100:
        score += 10
        feedback_parts.append("Report file exists with adequate content length [10/10 pts]")
        
        # Keyword checks for report quality
        quality_score = 0
        text_lower = report_text.lower()
        
        if any(w in text_lower for w in ['ogive', 'haack', 'parabolic', 'conical', 'shape', 'drag']):
            quality_score += 5
        if any(w in text_lower for w in ['altitude', 'apogee', 'meters', 'feet', 'm', 'ft']):
            quality_score += 5
        if any(w in text_lower for w in ['stability', 'margin', 'caliber', 'cg', 'cp']):
            quality_score += 5
            
        score += quality_score
        feedback_parts.append(f"Report quality keyword score [{quality_score}/15 pts]")
    else:
        feedback_parts.append("Report file missing or too short [0/25 pts for report criteria]")

    # Pass logic: Must reach threshold AND actually fix the injected faults
    key_faults_fixed = (nc_shape != 'conical' and nc_length >= 0.12 and uptodate_count > 0)
    passed = score >= 60 and key_faults_fixed
    
    if score >= 60 and not key_faults_fixed:
        feedback_parts.append("Failed: Score met but key engineering faults (shape/length/simulation) not fully resolved.")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }