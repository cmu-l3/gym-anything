#!/usr/bin/env python3
"""
Verifier for consolidate_misspelled_dive_site task.

Verification Strategy:
1. Verify the XML file was successfully modified/saved.
2. Ensure there are NO dives pointing to a site named 'Yelow House'.
3. Verify there is EXACTLY ONE site entity named 'Yellow House' to ensure 
   the agent didn't merely rename the typo site (which leaves two disconnected site UUIDs).
4. Verify all expected dives are associated with that single 'Yellow House' UUID.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_site(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    # Retrieve and parse task_result.json for anti-gaming checks
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_result.close()
    
    file_modified = False
    try:
        copy_from_env('/tmp/task_result.json', tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result_data = json.load(f)
            file_modified = result_data.get('file_modified_during_task', False)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    if not file_modified:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Dive log file was not modified. You must save your changes (Ctrl+S)."
        }

    # Retrieve and parse the saved dive log
    tmp_ssrf = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    tmp_ssrf.close()
    
    try:
        try:
            copy_from_env('/home/ga/Documents/dives.ssrf', tmp_ssrf.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not extract dives.ssrf: {e}"}

        try:
            tree = ET.parse(tmp_ssrf.name)
            root = tree.getroot()
        except ET.ParseError as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse XML: {e}"}

        # Scan for Site Entities
        yellow_house_uuids = []
        yelow_house_uuids = []
        
        for site in root.iter('site'):
            name = site.get('name', '').strip()
            site_uuid = site.get('uuid')
            
            if name == 'Yellow House':
                yellow_house_uuids.append(site_uuid)
            elif name == 'Yelow House':
                yelow_house_uuids.append(site_uuid)

        # Scan Dives
        dives_at_yellow = 0
        dives_at_yelow = 0
        
        for dive in root.iter('dive'):
            siteid = dive.get('siteid')
            loc_elem = dive.find('location')
            loc_text = loc_elem.text.strip() if loc_elem is not None and loc_elem.text else ''
            
            # Check if dive points to correct site UUID or has the correct legacy location text
            if siteid in yellow_house_uuids or loc_text == 'Yellow House':
                dives_at_yellow += 1
            elif siteid in yelow_house_uuids or loc_text == 'Yelow House':
                dives_at_yelow += 1

        # Calculate score based on criteria
        score = 10  # 10 pts for modifying the file
        feedback_parts = ["File saved successfully"]
        
        # Criterion 1: Misspelled site abandoned (30 pts)
        if dives_at_yelow == 0:
            score += 30
            feedback_parts.append("Misspelled site 'Yelow House' correctly abandoned")
        else:
            feedback_parts.append(f"FAILED: Found {dives_at_yelow} dive(s) still assigned to 'Yelow House'")

        # Criterion 2: No ghost renaming - exactly 1 site entity for "Yellow House" (30 pts)
        if len(yellow_house_uuids) == 1:
            score += 30
            feedback_parts.append("Exactly 1 'Yellow House' site entity exists (proper consolidation)")
        elif len(yellow_house_uuids) > 1:
            feedback_parts.append(f"FAILED: Found {len(yellow_house_uuids)} site entities named 'Yellow House' - you likely renamed the typo site instead of merging/reassigning.")
        else:
            feedback_parts.append("FAILED: No site entity named 'Yellow House' found.")

        # Criterion 3: Dives successfully pooled under the single correct UUID (30 pts)
        if dives_at_yellow >= 2 and len(yellow_house_uuids) == 1:
            score += 30
            feedback_parts.append(f"All dives successfully consolidated ({dives_at_yellow} dives total)")
        elif dives_at_yellow < 2:
            feedback_parts.append(f"FAILED: Only {dives_at_yellow} dive(s) found at 'Yellow House' - expected multiple dives after consolidation.")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        if os.path.exists(tmp_ssrf.name):
            os.unlink(tmp_ssrf.name)