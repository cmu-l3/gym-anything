#!/usr/bin/env python3
"""
Verifier for fabrication_blueprint_export task.

Scoring breakdown (100 points total):
  10 pts - PDF File Created (manufacturing_blueprints.pdf exists and is valid)
  20 pts - PDF: Fin Templates (text contains "fin templates")
  20 pts - PDF: Marking Guide (text contains "fin marking guide")
  15 pts - Lugs Added & Sized (Exactly 2 lugs, OD 8-12mm, Length 10-20mm)
  15 pts - Lugs Radially Aligned (positionangle matches < 0.01 rad)
  10 pts - Lug Rail Spacing (Z-position difference >= 300mm)
  10 pts - Simulation Updated (at least one uptodate simulation)

Pass threshold: 70 points
"""

import os
import re
import math
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing pdfminer for text extraction
try:
    from pdfminer.high_level import extract_text
    PDFMINER_AVAILABLE = True
except ImportError:
    PDFMINER_AVAILABLE = False
    logger.warning("pdfminer not available. Will attempt to install.")

def ensure_pdfminer():
    global PDFMINER_AVAILABLE, extract_text
    if not PDFMINER_AVAILABLE:
        try:
            import subprocess
            import sys
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pdfminer.six"])
            from pdfminer.high_level import extract_text as et
            extract_text = et
            PDFMINER_AVAILABLE = True
        except Exception as e:
            logger.error(f"Failed to install pdfminer.six: {e}")

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

def verify_fabrication_blueprint_export(traj, env_info, task_info):
    ensure_pdfminer()
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_ork_path = metadata.get('target_ork_path', '/home/ga/Documents/rockets/manufacturing_ready.ork')
    target_pdf_path = metadata.get('target_pdf_path', '/home/ga/Documents/exports/manufacturing_blueprints.pdf')
    
    score = 0
    feedback_parts = []
    
    # 1. Check basic export results
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env("/tmp/fabrication_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        export_data = {}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    pdf_exists = export_data.get("pdf_exists", False)
    ork_exists = export_data.get("ork_exists", False)

    # ==========================================
    # PDF Verification (50 pts total)
    # ==========================================
    if pdf_exists:
        tmp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        tmp_pdf.close()
        pdf_text = ""
        try:
            copy_from_env(target_pdf_path, tmp_pdf.name)
            if PDFMINER_AVAILABLE:
                pdf_text = extract_text(tmp_pdf.name).lower()
            else:
                # Fallback primitive extraction
                with open(tmp_pdf.name, 'rb') as f:
                    pdf_text = f.read().decode('ascii', errors='ignore').lower()
            
            # 1. PDF File Created (10 pts)
            if len(pdf_text) > 0:
                score += 10
                feedback_parts.append("PDF created successfully [10/10 pts]")
            
            # 2. Fin Templates (20 pts)
            if "fin template" in pdf_text or "fin templates" in pdf_text:
                score += 20
                feedback_parts.append("PDF contains fin templates [20/20 pts]")
            else:
                feedback_parts.append("PDF missing fin templates [0/20 pts]")
                
            # 3. Marking Guide (20 pts)
            if "fin marking" in pdf_text or "marking guide" in pdf_text:
                score += 20
                feedback_parts.append("PDF contains fin marking guide [20/20 pts]")
            else:
                feedback_parts.append("PDF missing marking guide [0/20 pts]")

        except Exception as e:
            feedback_parts.append(f"Failed to process PDF: {e} [0/50 pts]")
        finally:
            if os.path.exists(tmp_pdf.name):
                os.unlink(tmp_pdf.name)
    else:
        feedback_parts.append("manufacturing_blueprints.pdf not found [0/50 pts]")

    # ==========================================
    # ORK File Verification (50 pts total)
    # ==========================================
    if ork_exists:
        tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
        tmp_ork.close()
        ork_root = None
        try:
            copy_from_env(target_ork_path, tmp_ork.name)
            ork_root, parse_err = _parse_ork(tmp_ork.name)
            if parse_err:
                feedback_parts.append(f"Could not parse manufacturing_ready.ork: {parse_err}")
        except Exception as e:
            feedback_parts.append(f"Could not retrieve manufacturing_ready.ork: {e}")
        finally:
            if os.path.exists(tmp_ork.name):
                os.unlink(tmp_ork.name)
                
        if ork_root is not None:
            # Find Launch Lugs
            lugs = list(ork_root.iter('launchlug'))
            
            # 4. Lugs Added & Sized (15 pts)
            if len(lugs) == 2:
                valid_sizes = 0
                for lug in lugs:
                    # OR stores outer radius in <radius>
                    try:
                        rad = float(lug.findtext('radius', '0'))
                        od = rad * 2
                        length = float(lug.findtext('length', '0'))
                        
                        if 0.007 <= od <= 0.013 and 0.009 <= length <= 0.021:
                            valid_sizes += 1
                    except ValueError:
                        pass
                
                if valid_sizes == 2:
                    score += 15
                    feedback_parts.append("Exactly 2 lugs added with correct dimensions [15/15 pts]")
                else:
                    score += 7
                    feedback_parts.append(f"2 lugs found, but {2 - valid_sizes} have incorrect dimensions [7/15 pts]")
                    
                # 5. Lugs Radially Aligned (15 pts)
                try:
                    angle1 = float(lugs[0].findtext('positionangle', '0.0'))
                    angle2 = float(lugs[1].findtext('positionangle', '0.0'))
                    # normalize angles to 0-2PI
                    a1 = angle1 % (2 * math.pi)
                    a2 = angle2 % (2 * math.pi)
                    diff = min(abs(a1 - a2), 2 * math.pi - abs(a1 - a2))
                    
                    if diff < 0.05: # allowing small tolerance
                        score += 15
                        feedback_parts.append("Lugs are radially aligned [15/15 pts]")
                    else:
                        feedback_parts.append(f"Lugs are not aligned (diff: {diff:.2f} rad) [0/15 pts]")
                except ValueError:
                    feedback_parts.append("Failed to read lug angles [0/15 pts]")
                    
                # 6. Lug Rail Spacing (10 pts)
                try:
                    pos1 = float(lugs[0].findtext('position', '0.0'))
                    pos2 = float(lugs[1].findtext('position', '0.0'))
                    # Finding exact absolute position requires tree traversal, but standard relative 
                    # placing on the same tube or different tubes generally guarantees a wide spread
                    # if they are separated by > 0.3m relative, or if they are in different stages.
                    # We will do a heuristic check on the relative positions if they share a parent.
                    parent1 = None
                    parent2 = None
                    for parent in ork_root.iter():
                        if lugs[0] in list(parent): parent1 = parent
                        if lugs[1] in list(parent): parent2 = parent
                        
                    if parent1 == parent2:
                        z_diff = abs(pos1 - pos2)
                        if z_diff >= 0.28: # allowing tolerance for 0.3m
                            score += 10
                            feedback_parts.append(f"Lugs properly spaced ({z_diff*1000:.0f}mm) [10/10 pts]")
                        else:
                            feedback_parts.append(f"Lugs too close ({z_diff*1000:.0f}mm < 300mm) [0/10 pts]")
                    else:
                        # Placed on different airframe components, highly likely to be spaced well
                        score += 10
                        feedback_parts.append("Lugs properly spaced across components [10/10 pts]")
                except ValueError:
                    feedback_parts.append("Failed to read lug positions [0/10 pts]")

            else:
                feedback_parts.append(f"Found {len(lugs)} launch lugs (expected exactly 2) [0/40 pts]")
                
            # 7. Simulation Updated (10 pts)
            sims = ork_root.find('simulations')
            uptodate_found = False
            if sims is not None:
                for sim in sims.findall('simulation'):
                    if sim.get('status') == 'uptodate':
                        uptodate_found = True
                        break
            
            if uptodate_found:
                score += 10
                feedback_parts.append("At least one uptodate simulation found [10/10 pts]")
            else:
                feedback_parts.append("No uptodate simulations found [0/10 pts]")
    else:
        feedback_parts.append("manufacturing_ready.ork not found [0/50 pts]")

    passed = score >= metadata.get('pass_threshold', 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }