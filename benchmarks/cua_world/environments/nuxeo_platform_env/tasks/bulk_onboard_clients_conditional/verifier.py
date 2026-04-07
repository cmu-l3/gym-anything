#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_onboard_clients(traj, env_info, task_info):
    """
    Verifies that the agent created the specific folders and applied tags correctly
    based on the conditional logic provided in the task description.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata (ground truth)
    metadata = task_info.get('metadata', {})
    expected_clients = metadata.get('expected_clients', [])
    
    # Files to retrieve
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    api_dump_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name

    try:
        # Retrieve files from container
        copy_from_env("/tmp/task_result.json", result_file)
        copy_from_env("/tmp/nuxeo_children.json", api_dump_file)

        with open(result_file, 'r') as f:
            task_result = json.load(f)
        
        with open(api_dump_file, 'r') as f:
            nuxeo_data = json.load(f)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(result_file): os.unlink(result_file)
        if os.path.exists(api_dump_file): os.unlink(api_dump_file)

    # Parse Nuxeo API data
    entries = nuxeo_data.get('entries', [])
    
    # Helper to find a document by title
    def find_doc_by_title(title):
        for doc in entries:
            doc_title = doc.get('properties', {}).get('dc:title', '')
            if doc_title.strip() == title.strip():
                return doc
        return None

    score = 0
    feedback = []
    task_start_ts = task_result.get('task_start', 0)

    # Verification Logic
    all_clients_handled = True
    
    for client in expected_clients:
        name = client['name']
        should_tag = client['should_tag']
        expected_tag = client.get('expected_tag')

        doc = find_doc_by_title(name)
        
        if not doc:
            feedback.append(f"❌ Missing folder for '{name}'")
            all_clients_handled = False
            continue

        # 1. Check Creation Time (Anti-gaming)
        created_str = doc.get('properties', {}).get('dc:created', '')
        created_ts = 0
        try:
            # ISO 8601 format: 2023-10-27T10:00:00.00Z
            dt = datetime.strptime(created_str.split('.')[0], "%Y-%m-%dT%H:%M:%S")
            created_ts = dt.timestamp()
        except:
            pass
        
        # Allow some clock skew, but ensure it wasn't created way before task start
        # Note: Nuxeo container time might differ slightly from host, verifying relative order is best
        # If created_ts is 0 or very old, fail.
        if created_ts < task_start_ts - 60: # 60s buffer
            feedback.append(f"⚠️ Folder '{name}' appears to be pre-existing (creation time mismatch)")
            # Penalize but allow checking other criteria
            score += 5 
        else:
            score += 10 # Points for creating the folder
            feedback.append(f"✅ Folder '{name}' created")

        # 2. Check Tags
        # Nuxeo API returns tags in 'contextParameters' -> 'tags' (list of objects)
        tags_context = doc.get('contextParameters', {}).get('tags', [])
        current_tags = [t.get('label') for t in tags_context]
        
        if should_tag:
            if expected_tag in current_tags:
                score += 20 # Points for correct conditional tagging
                feedback.append(f"  ✅ Correctly tagged with '{expected_tag}'")
            else:
                feedback.append(f"  ❌ Missing required tag '{expected_tag}'")
                all_clients_handled = False
        else:
            if not current_tags:
                score += 10 # Points for correctly NOT tagging
                feedback.append(f"  ✅ Correctly has no tags")
            elif "Corporate" in current_tags: # specifically check for the wrong tag
                feedback.append(f"  ❌ Incorrectly tagged with 'Corporate'")
                all_clients_handled = False
            else:
                # Has other tags? Acceptable if not the forbidden one, but strictly task said "do not tag"
                score += 5
                feedback.append(f"  ⚠️ Has unexpected tags: {current_tags}")

    # Total possible score logic:
    # 3 clients.
    # Client 1 (Riverfront): Create (10) + NoTag (10) = 20
    # Client 2 (TechGlobal): Create (10) + Tag (20) = 30
    # Client 3 (Sarah): Create (10) + NoTag (10) = 20
    # Base Total = 70. Scaling to 100.
    
    scaled_score = int((score / 70) * 100)
    
    # Cap at 100
    final_score = min(100, scaled_score)
    
    if final_score >= 80 and all_clients_handled:
        passed = True
    else:
        passed = False

    return {
        "passed": passed,
        "score": final_score,
        "feedback": "\n".join(feedback)
    }