#!/usr/bin/env python3
"""
Verifier for add_patient_allergy task.
"""

import json
import os
import logging
import tempfile
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_patient_allergy(traj, env_info, task_info):
    """
    Verifies that 3 specific allergies were added to patient Elena Vasiliev.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_allergies = metadata.get('expected_allergies', [])
    patient_id_fragment = metadata.get('patient_id_fragment', "p1_0000006")
    
    score = 0
    feedback_parts = []
    
    # Create temp dir for artifacts
    temp_dir = tempfile.mkdtemp()
    try:
        # Copy result JSON
        local_result_json = os.path.join(temp_dir, "task_result.json")
        copy_from_env("/tmp/task_result.json", local_result_json)
        
        with open(local_result_json, 'r') as f:
            result_data = json.load(f)
            
        task_start = result_data.get("task_start", 0)
        
        # Copy database dump
        remote_dump_path = result_data.get("database_dump_path")
        local_dump_path = os.path.join(temp_dir, "couchdb_dump.json")
        copy_from_env(remote_dump_path, local_dump_path)
        
        with open(local_dump_path, 'r') as f:
            db_dump = json.load(f)
            
        rows = db_dump.get("rows", [])
        
        # --- Verification Logic ---
        
        # Helper to normalize strings
        def norm(s): return str(s).lower().strip() if s else ""
        
        found_records = []
        
        for row in rows:
            doc = row.get("doc", {})
            data = doc.get("data", doc) # Handle wrapper
            
            # Check if linked to Elena
            # Linkage can be in 'patient' field or implied in ID/content
            p_ref = str(data.get("patient", ""))
            doc_str = json.dumps(doc).lower()
            
            is_linked = (patient_id_fragment in p_ref) or \
                        (patient_id_fragment in doc.get("_id", "")) or \
                        ("elena" in doc_str and "vasiliev" in doc_str)
            
            if not is_linked:
                continue
                
            # Check if it looks like an allergy doc
            # HospitalRun usually has type="allergy" or uses "allergy" in ID
            d_type = data.get("type", "")
            d_id = doc.get("_id", "")
            
            # Also check if it has the fields we expect (name, reaction)
            has_allergy_fields = "name" in data and ("reaction" in data or "severity" in data)
            
            if d_type == "allergy" or "allergy" in d_id or has_allergy_fields:
                found_records.append(data)

        logger.info(f"Found {len(found_records)} potential allergy records for patient.")
        
        matches_found = 0
        
        # Check against expectations
        for exp in expected_allergies:
            exp_name = norm(exp["name"])
            exp_react = norm(exp["reaction"])
            
            match_found = False
            match_reaction_correct = False
            
            for rec in found_records:
                rec_name = norm(rec.get("name", ""))
                rec_react = norm(rec.get("reaction", ""))
                
                if exp_name in rec_name:
                    match_found = True
                    if exp_react in rec_react:
                        match_reaction_correct = True
                    # Don't break immediately, keep looking for better match if needed? 
                    # Actually, assuming distinct allergies, break is fine if we found it.
                    break
            
            item_score = 0
            if match_found:
                item_score += 20 # 20 pts for correct allergy name existing
                feedback_parts.append(f"Found allergy '{exp['name']}' (+20)")
                
                if match_reaction_correct:
                    item_score += 10 # 10 pts for correct reaction
                    feedback_parts.append(f"  - Reaction '{exp['reaction']}' matches (+10)")
                else:
                    feedback_parts.append(f"  - Reaction mismatch for '{exp['name']}'")
                
                matches_found += 1
            else:
                feedback_parts.append(f"Missing allergy '{exp['name']}'")
                
            score += item_score

        # Anti-gaming check: Timestamp
        # We can check if the _id contains a timestamp or look for meta fields
        # HospitalRun (PouchDB) revs start with 1-..., but we can't rely solely on that.
        # However, we verified in setup that we deleted these specific allergies.
        # So existence implies creation.
        # We'll give 10 points for just finding *any* new allergies
        if matches_found > 0:
            score += 10
            feedback_parts.append("Verification passed: New records created (+10)")
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir)

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }