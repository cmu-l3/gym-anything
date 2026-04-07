#!/usr/bin/env python3
"""
Verifier for cas_lookup_range_reporting task.
Evaluates the exported Tier2 Submit (.t2s) zip archive to confirm the CAS number,
range codes, physical state, and EHS flags were correctly applied.
"""

import json
import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def strip_ns(tag):
    """Remove namespace from XML tag for easier matching."""
    if '}' in tag:
        return tag.split('}', 1)[1]
    return tag

def verify_cas_lookup_range_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the task result JSON
    tmp_json = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\task_result.json", tmp_json.name)
        with open(tmp_json.name, "r", encoding="utf-8") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # Validate output exists and timestamp
    if not result.get("output_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output .t2s file not found at C:\\Tier2Data\\output\\agrichem_ammonia.t2s"
        }
        
    task_start = result.get("task_start", 0)
    output_mtime = result.get("output_mtime", 0)
    
    if output_mtime > 0 and output_mtime < task_start:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file was created before task started (anti-gaming block)"
        }

    # 2. Retrieve the exported .t2s submission file
    tmp_t2s = tempfile.NamedTemporaryFile(suffix=".t2s", delete=False)
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\exported_submission.t2s", tmp_t2s.name)
        
        # .t2s files are standard zip archives containing an XML export
        xml_content = None
        try:
            with zipfile.ZipFile(tmp_t2s.name, 'r') as z:
                xml_files = [f for f in z.namelist() if f.endswith('.xml')]
                if xml_files:
                    # Sort to prioritize main XML over manifest.xml
                    xml_files.sort(key=lambda x: 'manifest' in x.lower())
                    xml_content = z.read(xml_files[0])
        except zipfile.BadZipFile:
            return {"passed": False, "score": 0, "feedback": "Output file is not a valid zip/t2s archive"}

        if not xml_content:
            return {"passed": False, "score": 0, "feedback": "No XML data found in the .t2s file"}

        score = 0
        fb = []
        
        # File integrity points
        if result.get("output_size_bytes", 0) > 1024:
            score += 5
            fb.append("PASS: File exists and valid size (+5)")
            
        if output_mtime >= task_start:
            score += 5
            fb.append("PASS: File timestamp valid (+5)")

        # Parse XML
        root = ET.fromstring(xml_content)
        parent_map = {c: p for p in root.iter() for c in p}
        
        # Check for the correct CAS number anywhere in the tree
        cas_nodes = []
        for el in root.iter():
            if el.text and '7664-41-7' in el.text:
                cas_nodes.append(el)
                
        if not cas_nodes:
            fb.append("FAIL: CAS number 7664-41-7 not found in submission")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(fb)
            }
            
        score += 15
        fb.append("PASS: Chemical with CAS 7664-41-7 found (+15)")
        
        # Extract the chemical entry context block
        cas_node = cas_nodes[0]
        chem_node = parent_map.get(cas_node)
        
        curr = cas_node
        while curr is not None:
            tag = strip_ns(curr.tag).lower()
            if tag in ['chemical', 'inventory', 'inventoryitem', 'chemicalinventory']:
                chem_node = curr
                break
            curr = parent_map.get(curr)
            
        if chem_node is None:
            chem_node = parent_map.get(cas_node)
            
        # Convert element branch to lowercase string for robust inspection 
        # (Handles arbitrary schema attribute/node naming variations)
        chem_str = ET.tostring(chem_node).decode('utf-8').lower() if chem_node is not None else ""
        
        # 1. Chemical Name
        if 'ammonia' in chem_str:
            score += 5
            fb.append("PASS: Chemical name contains Ammonia (+5)")
        else:
            fb.append("FAIL: Chemical name missing Ammonia")
            
        # 2. EHS verification
        ehs_set = False
        if chem_node is not None:
            for el in chem_node.iter():
                tag = strip_ns(el.tag).lower()
                if 'ehs' in tag or 'extremelyhazardous' in tag:
                    if el.text and el.text.lower() in ['true', 'yes', '1', 'y']:
                        ehs_set = True
        if not ehs_set and ('ehs>true' in chem_str.replace(' ', '') or 'ehs>yes' in chem_str.replace(' ', '')):
            ehs_set = True
            
        if ehs_set:
            score += 10
            fb.append("PASS: EHS status set (+10)")
        else:
            fb.append("FAIL: EHS status not set to true")
            
        # 3. Physical State: Gas verification
        gas_set = False
        if chem_node is not None:
            for el in chem_node.iter():
                tag = strip_ns(el.tag).lower()
                if 'physical' in tag or 'state' in tag:
                    if el.text and 'gas' in el.text.lower():
                        gas_set = True
                if 'gas' in tag:
                    if el.text and el.text.lower() in ['true', '1', 'yes', 'y']:
                        gas_set = True
                    elif not el.text: # Tag presence implies true
                        gas_set = True
        if not gas_set and 'gas' in chem_str:
            gas_set = True
            
        if gas_set:
            score += 10
            fb.append("PASS: Physical state Gas (+10)")
        else:
            fb.append("FAIL: Physical state Gas not selected")
            
        # 4. Range code verifications
        max_05 = False
        avg_04 = False
        days_365 = False
        range_mode = False
        
        if chem_node is not None:
            for el in chem_node.iter():
                tag = strip_ns(el.tag).lower()
                text = (el.text or '').strip()
                
                if 'max' in tag and ('amount' in tag or 'code' in tag or 'quantity' in tag):
                    if text in ['05', '5']:
                        max_05 = True
                if 'avg' in tag or 'average' in tag:
                    if text in ['04', '4']:
                        avg_04 = True
                if 'day' in tag or 'site' in tag:
                    if text == '365':
                        days_365 = True
                if 'range' in tag or 'range' in text.lower():
                    range_mode = True
                    
        # String fallbacks to catch edge-case schemas
        clean_chem_str = chem_str.replace(' ', '')
        if not max_05 and ('maxamountcode>05' in clean_chem_str or '>05<' in chem_str):
            max_05 = True
        if not avg_04 and ('averageamountcode>04' in clean_chem_str or '>04<' in chem_str):
            avg_04 = True
        if not days_365 and '>365<' in chem_str:
            days_365 = True
        if not range_mode and 'range' in chem_str:
            range_mode = True
            
        if range_mode or (max_05 and avg_04):
            score += 10
            fb.append("PASS: Range reporting mode (+10)")
        else:
            fb.append("FAIL: Range reporting mode not selected")
            
        if max_05:
            score += 15
            fb.append("PASS: Max daily range code 05 (+15)")
        else:
            fb.append("FAIL: Max daily range code not 05")
            
        if avg_04:
            score += 10
            fb.append("PASS: Avg daily range code 04 (+10)")
        else:
            fb.append("FAIL: Avg daily range code not 04")
            
        if days_365:
            score += 10
            fb.append("PASS: Days on site 365 (+10)")
        else:
            fb.append("FAIL: Days on site not 365")
            
        # +5 workflow points for completing core parameters successfully
        if score >= 75:
            score += 5
            fb.append("PASS: Workflow verified (+5)")
            
        passed = score >= 70
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(fb)
        }
            
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification exception: {e}"}
    finally:
        if os.path.exists(tmp_t2s.name):
            try:
                os.unlink(tmp_t2s.name)
            except:
                pass