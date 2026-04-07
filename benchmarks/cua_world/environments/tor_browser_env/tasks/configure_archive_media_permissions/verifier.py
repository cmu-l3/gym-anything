#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_archive_media_permissions(traj, env_info, task_info):
    """
    Verify the agent successfully blocked global media autoplay, explicitly 
    allowed it for two specified archive domains, and properly bookmarked them.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    score = 0
    feedback_parts = []
    
    # Criterion 1 (GATE): Autoplay default is 'Block Audio and Video' (val = 5)
    autoplay_default = result.get('autoplay_default', -1)
    if autoplay_default == 5:
        score += 20
        feedback_parts.append("Global autoplay blocked (20/20)")
        gate_passed = True
    else:
        feedback_parts.append(f"Global autoplay NOT blocked [val={autoplay_default}] (0/20)")
        gate_passed = False

    # Criterion 2: Wikimedia Autoplay Exception (Site info)
    if result.get('wikimedia_allowed'):
        score += 20
        feedback_parts.append("Wikimedia Commons autoplay allowed (20/20)")
    else:
        feedback_parts.append("Wikimedia Commons autoplay NOT allowed (0/20)")

    # Criterion 3: Archive.org Autoplay Exception (Site info)
    if result.get('archive_allowed'):
        score += 20
        feedback_parts.append("Internet Archive autoplay allowed (20/20)")
    else:
        feedback_parts.append("Internet Archive autoplay NOT allowed (0/20)")

    # Criterion 4: 'Trusted Archives' Folder Created
    if result.get('folder_exists'):
        score += 15
        feedback_parts.append("Folder 'Trusted Archives' exists (15/15)")
    else:
        feedback_parts.append("Folder 'Trusted Archives' NOT found (0/15)")

    # Criterion 5: Bookmark Validation
    wikimedia_bm = result.get('wikimedia_bookmarked')
    archive_bm = result.get('archive_bookmarked')
    
    if wikimedia_bm and archive_bm:
        score += 25
        feedback_parts.append("Both bookmarks found in folder (25/25)")
    elif wikimedia_bm or archive_bm:
        score += 12
        feedback_parts.append("One bookmark found in folder (12/25)")
    else:
        feedback_parts.append("Bookmarks NOT found in folder (0/25)")

    # Pass Threshold checking
    passed = score >= 60 and gate_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }