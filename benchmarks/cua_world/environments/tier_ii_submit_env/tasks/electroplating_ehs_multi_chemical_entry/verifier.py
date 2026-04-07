#!/usr/bin/env python3
"""
Verifier for electroplating_ehs_multi_chemical_entry task.

This verifier pulls the extracted T2SData.xml and runs robust RegEx queries on the
chemical blocks to ensure all required fields (identity, hazards, exact amounts,
and storage types) were successfully entered, completely bypassing any unpredictable 
XML nesting structures.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_electroplating_ehs_multi_chemical_entry(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\Users\\Docker\\Desktop\\electroplating_ehs_result.json")
    xml_file = metadata.get("xml_file", "C:\\Users\\Docker\\Desktop\\T2SData_exported.xml")
    pass_threshold = metadata.get("pass_threshold", 75)

    tmp_json = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    tmp_xml = tempfile.NamedTemporaryFile(suffix=".xml", delete=False)
    
    # 1. Fetch JSON manifest
    try:
        copy_from_env(result_file, tmp_json.name)
        with open(tmp_json.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp_json.name)
        except Exception:
            pass

    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found (task not completed)."}
        
    if not result.get("xml_extracted", False):
        return {"passed": False, "score": 0, "feedback": "Could not extract XML from .t2s file."}

    # 2. Fetch extracted XML Data
    try:
        copy_from_env(xml_file, tmp_xml.name)
        with open(tmp_xml.name, "r", encoding="utf-8-sig") as f:
            xml_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read extracted XML: {e}"}
    finally:
        try:
            os.unlink(tmp_xml.name)
        except Exception:
            pass

    score = 0
    feedback = []
    
    score += 10
    feedback.append("File exported (+10)")

    # 3. Chemical Block Validation Logic
    def check_chem(cas, label, conditions):
        nonlocal score
        # Extract chemical-specific block via non-greedy regex
        blocks = re.findall(r'<Chemical(?:(?!</Chemical>).)*?</Chemical>', xml_content, re.DOTALL | re.IGNORECASE)
        target_block = None
        for b in blocks:
            if cas in b:
                target_block = b
                break
        
        if not target_block:
            feedback.append(f"FAIL: {label} (CAS {cas}) not found.")
            return

        chem_score = 0
        for cond_name, pattern, pts in conditions:
            found = False
            # Tuples are treated as OR fallback searches
            if isinstance(pattern, tuple):
                for alt in pattern:
                    if re.search(alt, target_block, re.IGNORECASE):
                        found = True
                        break
            else:
                if re.search(pattern, target_block, re.IGNORECASE):
                    found = True
                    
            if found:
                chem_score += pts
                feedback.append(f"PASS: {label} - {cond_name} (+{pts})")
            else:
                feedback.append(f"FAIL: {label} - {cond_name} missing")
                
        score += chem_score

    # Check 1: Sodium Cyanide (45 max pts)
    cyanide_conds = [
        ("EHS Checked", r'<[^>]*EHS[^>]*>\s*(?:true|1)\s*</', 10),
        ("State Solid", r'>\s*Solid\s*<', 5),
        ("Acute Toxicity", r'Acute\s*toxicity', 10),
        ("Max Amount 500", r'>\s*500\s*<', 5),
        ("Avg Amount 250", r'>\s*250\s*<', 5),
        ("Storage Vat", (r'Vat', r'Open Vessel', r'Vat/Open Vessel'), 10)
    ]
    check_chem("143-33-9", "Sodium Cyanide", cyanide_conds)

    # Check 2: Nitric Acid (45 max pts)
    nitric_conds = [
        ("EHS Checked", r'<[^>]*EHS[^>]*>\s*(?:true|1)\s*</', 10),
        ("State Liquid", r'>\s*Liquid\s*<', 5),
        ("Oxidizer", r'Oxidizer', 3),
        ("Corrosive to metal", r'Corrosive to metal', 2),
        ("Skin corrosion", r'Skin corrosion', 3),
        ("Eye damage", r'eye damage', 2),
        ("Max Amount 1200", r'>\s*1,?200\s*<', 5),
        ("Avg Amount 800", r'>\s*800\s*<', 5),
        ("Storage Carboy", (r'Carboy', r'Plastic Receptacle', r'Carboy/Plastic Receptacle'), 10)
    ]
    check_chem("7697-37-2", "Nitric Acid", nitric_conds)

    passed = score >= pass_threshold
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }