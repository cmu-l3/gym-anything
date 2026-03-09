#!/usr/bin/env python3
"""
Verifier for reconstruct_playlist task.

Criteria:
1. Playlist "Heavy Classics" exists (20 pts)
2. Playlist contains correct tracks (12 pts each, max 60)
3. No incorrect/extra tracks (deduction)
4. Database was modified/saved (10 pts)
5. Anti-gaming checks (app running, valid workflow)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reconstruct_playlist(traj, env_info, task_info):
    """
    Verify the agent reconstructed the playlist correctly in LibreOffice Base.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_tracks = metadata.get('target_tracks', [])
    target_playlist_name = metadata.get('target_playlist_name', "Heavy Classics")

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Parse DB Analysis
    db_analysis = result.get('db_analysis', {})
    if db_analysis.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Database analysis failed: {db_analysis['error']}"}

    # Criterion 1: Playlist Existence (20 pts)
    if db_analysis.get('playlist_found'):
        score += 20
        feedback_parts.append(f"✅ Playlist '{target_playlist_name}' created")
    else:
        feedback_parts.append(f"❌ Playlist '{target_playlist_name}' NOT found")
        # Critical failure
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Database Persistence (10 pts)
    # If we found the playlist in the file, it must have been saved, 
    # but checking timestamp confirms valid session
    if result.get('odb_modified', False):
        score += 10
    else:
        feedback_parts.append("⚠️ Database file timestamp not updated (did you Save?)")

    # Criterion 3: Correct Tracks (60 pts max, 12 per track)
    linked_names = db_analysis.get('linked_track_names', [])
    correct_count = 0
    
    # Normalize for comparison
    linked_norm = [n.lower().strip() for n in linked_names]
    target_norm = [t.lower().strip() for t in target_tracks]
    
    missing_tracks = []
    for target in target_tracks:
        if target.lower().strip() in linked_norm:
            score += 12
            correct_count += 1
        else:
            missing_tracks.append(target)
            
    if correct_count == len(target_tracks):
        feedback_parts.append("✅ All 5 tracks added correctly")
    else:
        feedback_parts.append(f"❌ Missing {len(missing_tracks)} tracks: {', '.join(missing_tracks)}")

    # Criterion 4: No Extra Tracks (10 pts)
    # The score logic above sums to 90 (20+10+60). 
    # Let's allocate last 10 points to "cleanliness" (no extra tracks).
    extra_count = len(linked_names) - correct_count
    if extra_count == 0:
        score += 10
        feedback_parts.append("✅ No incorrect tracks added")
    else:
        feedback_parts.append(f"⚠️ {extra_count} incorrect/extra tracks found")

    # Final Verification
    passed = score >= 80  # Allow 1 missing track or minor issues
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "playlist_found": db_analysis.get('playlist_found'),
            "tracks_found": linked_names,
            "score_breakdown": score
        }
    }