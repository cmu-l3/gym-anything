#!/usr/bin/env python3
"""Verifier for enrich_with_threat_intel task.

Scoring Breakdown (total = 100):
1. Lookup table file uploaded (must contain "threat" in name) - 20 pts
2. Lookup definition created (must contain "threat_intel" in name) - 20 pts
3. Saved search exists (must be named "Threat_Intel_Enriched_Events") - 20 pts
4. Saved search SPL uses the lookup command - 20 pts
5. Saved search SPL references security_logs index - 20 pts

Anti-gaming: Task duration must be > 10 seconds.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = 20
PASS_THRESHOLD = 60

def normalize_name(name):
    """Normalize name for comparison: lowercase, replace spaces/hyphens with underscores."""
    return name.lower().replace(' ', '_').replace('-', '_')

def verify_enrich_with_threat_intel(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_report_name = metadata.get('expected_report_name', 'Threat_Intel_Enriched_Events')
    expected_lookup_keyword = metadata.get('expected_lookup_keyword', 'threat')
    expected_def_keyword = metadata.get('expected_def_keyword', 'threat_intel')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/threat_intel_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    task_duration = data.get('task_duration_seconds', 0)
    
    new_lookups = analysis.get('new_lookups', [])
    new_defs = analysis.get('new_defs', [])
    new_searches = analysis.get('new_searches', [])

    score = 0
    feedback = []
    subscores = {}

    # Anti-gaming check
    if task_duration < 10:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Task completed suspiciously fast ({task_duration}s). Anti-gaming triggered.",
            "subscores": {}
        }

    # Criterion 1: Lookup table file uploaded
    lookup_file_found = any(expected_lookup_keyword in f.lower() for f in new_lookups)
    if lookup_file_found:
        score += POINTS_PER_CRITERION
        feedback.append(f"Lookup file created containing '{expected_lookup_keyword}'")
        subscores['lookup_file_created'] = True
    else:
        feedback.append(f"FAIL: No new lookup file found containing '{expected_lookup_keyword}'")
        subscores['lookup_file_created'] = False

    # Criterion 2: Lookup definition created
    lookup_def_found = any(expected_def_keyword in normalize_name(d) for d in new_defs)
    if lookup_def_found:
        score += POINTS_PER_CRITERION
        feedback.append(f"Lookup definition created containing '{expected_def_keyword}'")
        subscores['lookup_def_created'] = True
    else:
        feedback.append(f"FAIL: No new lookup definition found containing '{expected_def_keyword}'")
        subscores['lookup_def_created'] = False

    # Find the target saved search
    target_search_obj = None
    expected_normalized = normalize_name(expected_report_name)
    
    for s in new_searches:
        if normalize_name(s.get('name', '')) == expected_normalized:
            target_search_obj = s
            break
            
    # If exact name not found, try to see if ANY new search was created (partial credit/fallback)
    if not target_search_obj and new_searches:
        target_search_obj = new_searches[-1]

    # Criterion 3: Saved search exists and is named correctly
    if target_search_obj and normalize_name(target_search_obj.get('name', '')) == expected_normalized:
        score += POINTS_PER_CRITERION
        feedback.append(f"Saved report exactly matches '{expected_report_name}'")
        subscores['report_named_correctly'] = True
    elif target_search_obj:
        feedback.append(f"FAIL: Found new report '{target_search_obj.get('name')}', but expected '{expected_report_name}'")
        subscores['report_named_correctly'] = False
    else:
        feedback.append("FAIL: No new saved reports found")
        subscores['report_named_correctly'] = False

    # Criterion 4 & 5 logic
    search_query = target_search_obj.get('search', '').lower() if target_search_obj else ''

    # Criterion 4: Uses lookup command
    has_lookup = re.search(r'\b(lookup|inputlookup)\b', search_query) is not None
    if has_lookup and target_search_obj:
        score += POINTS_PER_CRITERION
        feedback.append("SPL query uses the 'lookup' or 'inputlookup' command")
        subscores['uses_lookup_cmd'] = True
    else:
        feedback.append("FAIL: SPL query must use the 'lookup' command to enrich data")
        subscores['uses_lookup_cmd'] = False

    # Criterion 5: References security_logs index
    refs_index = 'security_logs' in search_query
    if refs_index and target_search_obj:
        score += POINTS_PER_CRITERION
        feedback.append("SPL query targets the 'security_logs' index")
        subscores['references_index'] = True
    else:
        feedback.append("FAIL: SPL query must search the 'security_logs' index")
        subscores['references_index'] = False

    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "new_lookups": new_lookups,
            "new_defs": new_defs,
            "found_report_name": target_search_obj.get('name', '') if target_search_obj else None,
            "found_report_spl": search_query[:150] if target_search_obj else None
        }
    }