#!/usr/bin/env python3
"""
Verifier for the University Campus Multi-Building Solvent task.

Verification Strategy:
1. Validates task_result.json for basic file metadata.
2. Anti-Gaming: Checks if the submission ZIP was created during the task.
3. Programmatic: Pulls the actual ZIP file from the VM, extracts the Tier2 XML.
4. XML Parsing: Fuzzily parses the XML to find the Acetone (67-64-1) entry, 
   verifies all 3 requested hazards, quantities, and all 3 distinct storage locations.
5. VLM: Uses trajectory frames to verify real UI interaction and workflow.
"""

import json
import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants for scoring
PASS_THRESHOLD = 75

def _vlm_verify_trajectory(traj, env_info):
    """Uses VLM to verify the agent actually interacted with the Tier2 Submit UI."""
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        if not frames:
            return 0
            
        prompt = """You are auditing a regulatory compliance agent. Look at these chronological frames.
        Did the agent actually navigate the EPA Tier2 Submit software UI to enter chemical data?
        Indicators of genuine work:
        1. Navigating through the Chemical Inventory screens.
        2. Entering data into text fields or interacting with dropdown menus/modals (specifically for Storage Locations).
        
        Respond in JSON format:
        {
            "genuine_ui_interaction": true/false,
            "storage_modal_seen": true/false
        }
        """
        
        vlm_result = query_vlm(prompt=prompt, images=frames)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            score = 0
            if parsed.get("genuine_ui_interaction"): score += 10
            if parsed.get("storage_modal_seen"): score += 5
            return score
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
    
    return 0

def verify_university_multi_building_solvent(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable."}

    # 1. Fetch Result Metadata
    tmp_json = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\task_result.json", tmp_json.name)
        with open(tmp_json.name, "r") as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Check File Existence & Anti-Gaming
    if not result_meta.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "FAIL: Submission ZIP file was not created at the target path."}
    if not result_meta.get("file_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "FAIL: Anti-Gaming check failed. Submission file was created before the task started."}

    score = 10  # Base points for creating the file legitimately
    fb = ["PASS: Submission ZIP generated (+10)"]

    # 3. Fetch & Parse the actual ZIP file
    tmp_zip = tempfile.NamedTemporaryFile(suffix=".zip", delete=False)
    try:
        copy_from_env(result_meta.get("zip_path"), tmp_zip.name)
        
        with zipfile.ZipFile(tmp_zip.name, 'r') as z:
            # Tier2 Submit usually exports a .t2s (which is a ZIP) containing an XML file.
            xml_files = [f for f in z.namelist() if f.endswith('.xml') or f.endswith('.t2s')]
            if not xml_files:
                return {"passed": False, "score": score, "feedback": "FAIL: No XML payload found inside the submission ZIP."}
                
            xml_content = z.read(xml_files[0]).decode('utf-8', errors='ignore')
            
        root = ET.fromstring(xml_content)
        
        # 4. Locate the Acetone Chemical Node
        target_chem = None
        for elem in root.iter():
            # Look for chemical node containing CAS
            if 'chemical' in elem.tag.lower():
                chem_text = ET.tostring(elem, encoding='unicode').lower()
                if '67-64-1' in chem_text:
                    target_chem = elem
                    break
                    
        if target_chem is None:
            # Fallback: Fuzzy search whole XML if structure differs
            if '67-64-1' in xml_content.lower():
                target_chem = root 
            else:
                fb.append("FAIL: Acetone (CAS 67-64-1) not found in the submission data.")
                return {"passed": False, "score": score, "feedback": " | ".join(fb)}

        score += 10
        fb.append("PASS: Acetone (67-64-1) entry found (+10)")
        chem_text = ET.tostring(target_chem, encoding='unicode').lower()

        # 5. Verify Hazards (20 pts)
        hazards_found = 0
        if 'flammable' in chem_text: hazards_found += 1
        if 'eye' in chem_text or 'irritation' in chem_text: hazards_found += 1
        if 'target organ' in chem_text or 'stot' in chem_text or 'specific target' in chem_text: hazards_found += 1
        
        if hazards_found == 3:
            score += 20
            fb.append("PASS: All 3 GHS hazards correctly configured (+20)")
        elif hazards_found > 0:
            score += (hazards_found * 6)
            fb.append(f"PARTIAL: {hazards_found}/3 GHS hazards configured (+{hazards_found * 6})")
        else:
            fb.append("FAIL: Required GHS hazards not configured.")

        # 6. Verify Quantities (10 pts)
        if '25000' in chem_text or '25,000' in chem_text or 'code 06' in chem_text or 'code 05' in chem_text:
            score += 5
            fb.append("PASS: Max Quantity / Range Code correct (+5)")
        if '15000' in chem_text or '15,000' in chem_text or 'code 05' in chem_text or 'code 04' in chem_text:
            score += 5
            fb.append("PASS: Avg Quantity / Range Code correct (+5)")

        # 7. Verify Storage Locations (30 pts - 10 per location)
        # Location 1: Underground Tank, Ambient Temp
        if ('underground' in chem_text and 'facilities management' in chem_text):
            score += 10
            fb.append("PASS: Storage 1 (Underground Tank) correct (+10)")
        else:
            fb.append("FAIL: Storage 1 missing or incorrect.")

        # Location 2: Steel Drum, Ambient Temp
        if (('drum' in chem_text or 'steel' in chem_text) and 'chemistry building' in chem_text):
            score += 10
            fb.append("PASS: Storage 2 (Steel Drum) correct (+10)")
        else:
            fb.append("FAIL: Storage 2 missing or incorrect.")

        # Location 3: Carboy/Glass, Cold Room (< Ambient Temp)
        if (('carboy' in chem_text or 'glass' in chem_text) and 'cold room' in chem_text):
            score += 10
            fb.append("PASS: Storage 3 (Carboy/Glass) correct (+10)")
        else:
            fb.append("FAIL: Storage 3 missing or incorrect.")

    except Exception as e:
        logger.error(f"Error parsing ZIP/XML: {e}")
        fb.append(f"WARNING: Validation hit a parsing error: {e}")
    finally:
        if os.path.exists(tmp_zip.name):
            os.unlink(tmp_zip.name)

    # 8. VLM Trajectory Verification (15 pts)
    vlm_score = _vlm_verify_trajectory(traj, env_info)
    if vlm_score > 0:
        score += vlm_score
        fb.append(f"PASS: VLM trajectory confirmed genuine workflow (+{vlm_score})")

    # Finalize
    score = min(score, 100)
    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb)
    }