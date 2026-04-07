#!/usr/bin/env python3
"""
Verifier for distillery_ethanol_co2_reporting task.

Verification Strategy:
1. Validates that the .t2s (Zip/XML format) file was created by the agent.
2. Unzips and parses the XML database file created by EPA Tier2 Submit.
3. Retrieves chemical inventory entries via regex to bypass XML namespace complexities.
4. Distinguishes scoring for Ethanol vs. Carbon Dioxide correctly configuring contrasting attributes
   (Flammable Liquid vs. Pressurized Asphyxiating Gas).
"""

import tempfile
import os
import json
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_distillery_ethanol_co2_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get("metadata", {})
    meta_file_path = metadata.get("meta_file", "C:\\Users\\Docker\\Desktop\\distillery_meta.json")
    xml_file_path = metadata.get("xml_file", "C:\\Users\\Docker\\Desktop\\distillery_xml_data.xml")

    # Secure temporary host files
    meta_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    xml_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".xml")
    meta_tmp.close()
    xml_tmp.close()

    score = 0
    feedback = []

    try:
        copy_from_env(meta_file_path, meta_tmp.name)
        with open(meta_tmp.name, 'r') as f:
            meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read metadata: {e}"}
    
    # Check 1: Agent must have generated the .t2s output file
    if not meta.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file was not created. Task incomplete."}
    
    score += 10
    feedback.append("Submission file created successfully (+10)")

    # Check 2: File must be a valid zip format (extractable XML)
    if not meta.get("xml_extracted"):
        return {"passed": False, "score": score, "feedback": f"Could not extract XML from .t2s file (Invalid structure): {meta.get('extract_error', 'Unknown error')}"}

    try:
        copy_from_env(xml_file_path, xml_tmp.name)
        with open(xml_tmp.name, 'r', encoding='utf-8', errors='ignore') as f:
            xml_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read extracted XML data: {e}"}
    finally:
        if os.path.exists(meta_tmp.name): os.unlink(meta_tmp.name)
        if os.path.exists(xml_tmp.name): os.unlink(xml_tmp.name)

    # XML Helper: Extract specific chemical block ensuring robustness against EPA namespace variants
    def extract_chemical_block(xml_text, cas):
        pattern = r'<([a-zA-Z0-9:]*Chemical\b|ChemicalInventory\b|ChemInv\b).*?</\1>'
        blocks = [m.group(0) for m in re.finditer(pattern, xml_text, re.IGNORECASE | re.DOTALL)]
        for b in blocks:
            if cas in b:
                return b.lower()
        return ""

    eth_block = extract_chemical_block(xml_content, "64-17-5")
    co2_block = extract_chemical_block(xml_content, "124-38-9")

    # === ETHANOL VERIFICATION (CAS 64-17-5) ===
    if eth_block:
        score += 10
        feedback.append("Ethanol (64-17-5) entry found (+10)")
        
        if "liquid" in eth_block: 
            score += 5
            feedback.append("Ethanol State: Liquid (+5)")
            
        if "flammable" in eth_block: 
            score += 10
            feedback.append("Ethanol Hazard: Flammable (+10)")
            
        if "eye" in eth_block or "irritation" in eth_block: 
            score += 5
            feedback.append("Ethanol Hazard: Eye Damage/Irritation (+5)")
        
        # Must be ambient pressure, ensure it wasn't broadly tagged 'greater than ambient'
        if "ambient" in eth_block and "greater than ambient" not in eth_block:
            score += 10
            feedback.append("Ethanol Pressure: Ambient (+10)")
        
        # Negative Check: Ensure agent didn't just check ALL hazards lazily
        if "explosive" not in eth_block and "reactive" not in eth_block:
            score += 5
            feedback.append("Ethanol: Properly withheld explosive/reactive hazards (+5)")
    else:
        feedback.append("FAIL: Ethanol (64-17-5) NOT found in inventory")

    # === CARBON DIOXIDE VERIFICATION (CAS 124-38-9) ===
    if co2_block:
        score += 10
        feedback.append("CO2 (124-38-9) entry found (+10)")
        
        if "gas" in co2_block: 
            score += 5
            feedback.append("CO2 State: Gas (+5)")
            
        if "pressure" in co2_block: 
            score += 10
            feedback.append("CO2 Hazard: Gas under pressure (+10)")
            
        if "asphyxiant" in co2_block: 
            score += 5
            feedback.append("CO2 Hazard: Simple Asphyxiant (+5)")
        
        if "greater than ambient" in co2_block:
            score += 10
            feedback.append("CO2 Pressure: Greater than ambient (+10)")
        
        # Negative Check: Ensure gas isn't marked as a flammable liquid
        if "flammable" not in co2_block and "liquid" not in co2_block:
            score += 5
            feedback.append("CO2: Correctly marked non-flammable/non-liquid (+5)")
    else:
        feedback.append("FAIL: CO2 (124-38-9) NOT found in inventory")

    pass_threshold = metadata.get("pass_threshold", 70)
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }