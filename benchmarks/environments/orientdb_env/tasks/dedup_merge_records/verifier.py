#!/usr/bin/env python3
"""
Verifier for Data Deduplication Task.
"""

import json
import tempfile
import os
import base64

def verify_dedup_merge_records(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    db_state = result.get('db_state', {})
    
    # Criterion 1: Deduplication (30 pts)
    # Goal: 0 duplicate groups
    hotel_dups = db_state.get('hotel_dup_groups', -1)
    profile_dups = db_state.get('profile_dup_groups', -1)
    
    if hotel_dups == 0:
        score += 15
        feedback.append("Hotel duplicates removed (15/15)")
    elif hotel_dups > 0:
        feedback.append(f"Hotel duplicates remaining: {hotel_dups} (0/15)")
    else:
        feedback.append("Could not verify hotel duplicates (0/15)")
        
    if profile_dups == 0:
        score += 15
        feedback.append("Profile duplicates removed (15/15)")
    else:
        feedback.append(f"Profile duplicates remaining: {profile_dups} (0/15)")

    # Criterion 2: Edge Preservation (40 pts)
    # Goal: All edges must have been moved to the originals
    # Edges from setup: 
    #   Luca->Artemide, Anna->Artemide
    #   James->Savoy
    #   Emma->Copacabana
    #   Carlos->John, Emma->Yuki, Yuki->James
    
    edges_found = 0
    total_edges = 7
    edge_checks = [
        ('edge_luca_artemide', "Luca->Artemide"),
        ('edge_anna_artemide', "Anna->Artemide"),
        ('edge_james_savoy', "James->Savoy"),
        ('edge_emma_copacabana', "Emma->Copacabana"),
        ('edge_carlos_john', "Carlos->John"),
        ('edge_emma_yuki', "Emma->Yuki"),
        ('edge_yuki_james', "Yuki->James")
    ]
    
    for key, name in edge_checks:
        if db_state.get(key, False):
            edges_found += 1
        else:
            feedback.append(f"Missing edge: {name}")

    edge_score = int((edges_found / total_edges) * 40)
    score += edge_score
    feedback.append(f"Edges preserved: {edges_found}/{total_edges} ({edge_score}/40)")

    # Criterion 3: Index Restoration (10 pts)
    if db_state.get('index_restored', False):
        score += 10
        feedback.append("Profiles.Email unique index restored (10/10)")
    else:
        feedback.append("Profiles.Email unique index NOT found (0/10)")

    # Criterion 4: Report File (20 pts)
    if result.get('report_exists') and result.get('report_created_during_task'):
        try:
            content = base64.b64decode(result.get('report_content_b64', '')).decode()
            if "Hotels deduplicated: 3" in content and "Profiles deduplicated: 2" in content:
                score += 20
                feedback.append("Report file correct (20/20)")
            else:
                score += 10
                feedback.append("Report file exists but content mismatch (10/20)")
        except:
            score += 10
            feedback.append("Report file exists but unreadable (10/20)")
    else:
        feedback.append("Report file missing or not created during task (0/20)")

    passed = (score >= 70) and (hotel_dups == 0) and (profile_dups == 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }