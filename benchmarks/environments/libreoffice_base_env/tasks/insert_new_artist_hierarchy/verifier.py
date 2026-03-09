#!/usr/bin/env python3
"""
Verifier for insert_new_artist_hierarchy task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insert_new_artist_hierarchy(traj, env_info, task_info):
    """
    Verify the insertion of Artist, Album, and Tracks with correct relationships.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    # Parsing results
    db_data = result.get('db_parsing', {})
    file_modified = result.get('file_modified', False)
    
    score = 0
    feedback_parts = []
    
    # 1. Check if file was modified (Anti-gaming)
    if not file_modified:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Database file was not saved/modified. Remember to save your changes."
        }
    
    # 2. Verify Artist (20 pts)
    if db_data.get('artist_found'):
        score += 20
        feedback_parts.append("Artist 'Dua Lipa' created.")
    else:
        feedback_parts.append("Artist 'Dua Lipa' NOT found.")
        
    # 3. Verify Album (20 pts)
    if db_data.get('album_found'):
        score += 20
        feedback_parts.append("Album 'Future Nostalgia' created.")
    else:
        feedback_parts.append("Album 'Future Nostalgia' NOT found.")

    # 4. Verify Artist-Album Link (20 pts)
    if db_data.get('album_linked_correctly'):
        score += 20
        feedback_parts.append("Album correctly linked to Artist.")
    elif db_data.get('album_found'):
        feedback_parts.append("Album exists but NOT linked to correct Artist ID.")

    # 5. Verify Tracks (15 pts)
    found_tracks = db_data.get('tracks_found', [])
    score += len(found_tracks) * 5  # 5 pts per track (max 15)
    
    if len(found_tracks) == 3:
        feedback_parts.append("All 3 tracks found.")
    else:
        feedback_parts.append(f"Found {len(found_tracks)}/3 tracks.")

    # 6. Verify Album-Track Link (15 pts)
    linked_tracks = [t for t in found_tracks if t.get('linked')]
    score += len(linked_tracks) * 5 # 5 pts per correctly linked track
    
    if len(linked_tracks) == 3:
        feedback_parts.append("All tracks correctly linked to Album.")
    elif len(found_tracks) > 0:
        feedback_parts.append(f"Only {len(linked_tracks)} tracks correctly linked to Album.")
        
    # 7. Metadata/Constraint logic (10 pts)
    # Implicitly checked if regex matched the lines, as regex included context.
    # We award these points if full hierarchy is perfect.
    if score == 90: # 20+20+20+15+15
        score += 10
        feedback_parts.append("Metadata and structure perfect.")

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }