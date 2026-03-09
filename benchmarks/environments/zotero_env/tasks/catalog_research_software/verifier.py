#!/usr/bin/env python3
"""
Verifier for catalog_research_software task.
Checks if Zotero and PyTorch items are correctly created as Computer Programs.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_catalog_research_software(traj, env_info, task_info):
    """
    Verify that two computer program items (Zotero, PyTorch) were created with correct metadata.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    items = result.get('computer_programs', [])
    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # Verify Item 1: Zotero
    # ------------------------------------------------------------------
    zotero_item = None
    for item in items:
        if item.get('fields', {}).get('title') == 'Zotero':
            zotero_item = item
            break
            
    if zotero_item:
        score += 10
        feedback_parts.append("Zotero item created")
        
        fields = zotero_item.get('fields', {})
        
        # Version (10 pts)
        if fields.get('version') == '7.0.11':
            score += 10
            feedback_parts.append("Zotero version correct")
        else:
            feedback_parts.append(f"Zotero version mismatch (found: {fields.get('version')})")

        # Company (10 pts)
        # Note: fieldName might be 'company' or 'publisher' depending on Zotero version schema mapping
        # We check exact match in values we extracted
        if fields.get('company') == 'Corporation for Digital Scholarship' or fields.get('publisher') == 'Corporation for Digital Scholarship':
            score += 10
            feedback_parts.append("Zotero company correct")
        else:
            feedback_parts.append("Zotero company mismatch")

        # System (10 pts)
        if fields.get('system') == 'Linux':
            score += 10
            feedback_parts.append("Zotero system correct")
        else:
            feedback_parts.append("Zotero system mismatch")
    else:
        feedback_parts.append("Zotero item NOT found")

    # ------------------------------------------------------------------
    # Verify Item 2: PyTorch
    # ------------------------------------------------------------------
    pytorch_item = None
    for item in items:
        if item.get('fields', {}).get('title') == 'PyTorch':
            pytorch_item = item
            break
            
    if pytorch_item:
        score += 10
        feedback_parts.append("PyTorch item created")
        
        fields = pytorch_item.get('fields', {})
        creators = pytorch_item.get('creators', [])
        
        # Version (10 pts)
        if fields.get('version') == '2.1.0':
            score += 10
            feedback_parts.append("PyTorch version correct")
        else:
            feedback_parts.append(f"PyTorch version mismatch (found: {fields.get('version')})")
            
        # URL (5 pts)
        if 'pytorch.org' in fields.get('url', ''):
            score += 5
            feedback_parts.append("PyTorch URL correct")
        else:
            feedback_parts.append("PyTorch URL missing")
            
        # Programmer: Meta AI (15 pts)
        # Must be single field mode (fieldMode = 1) and lastName = "Meta AI"
        programmer_found = False
        for c in creators:
            if c.get('type') == 'programmer' and c.get('lastName') == 'Meta AI':
                if c.get('fieldMode') == 1:
                    score += 15
                    programmer_found = True
                    feedback_parts.append("PyTorch programmer correct (Single Field)")
                else:
                    score += 5 # Partial credit for correct name but wrong mode
                    feedback_parts.append("PyTorch programmer name correct but wrong mode (Two Fields)")
                break
        
        if not programmer_found:
            feedback_parts.append("PyTorch programmer mismatch")
            
    else:
        feedback_parts.append("PyTorch item NOT found")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    passed = score >= 80  # Must get almost everything right
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }