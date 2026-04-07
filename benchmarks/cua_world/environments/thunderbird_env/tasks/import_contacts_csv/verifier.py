#!/usr/bin/env python3
"""
Verifier for the import_contacts_csv task.

Verifies that the agent successfully imported a list of 12 referring physicians
into Thunderbird's Address Book.

Uses both database verification and VLM trajectory analysis to ensure
robustness and prevent gaming.
"""

import os
import json
import sqlite3
import tempfile
import tarfile
import logging
from typing import List, Dict

# Gym-anything VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback/mock for standalone testing if needed
    def sample_trajectory_frames(*args, **kwargs): return []
    def query_vlm(*args, **kwargs): return {"success": False, "error": "Not imported"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for analyzing trajectory frames
TRAJECTORY_PROMPT = """You are analyzing trajectory screenshots of an agent importing contacts into Thunderbird.

Determine if the agent performed the workflow to import a CSV into the Address Book. Look for:
1. ADDRESS_BOOK_OPENED: Is the Thunderbird Address Book window visible in any frame?
2. IMPORT_DIALOG_VISIBLE: Is there a file selection dialog or a Thunderbird "Import" wizard/mapping dialog visible?

Respond strictly in JSON format:
{
    "address_book_opened": true/false,
    "import_dialog_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is visible"
}
"""

def extract_emails_from_db(db_path: str) -> set:
    """Extracts all PrimaryEmail values from the Thunderbird abook.sqlite."""
    emails = set()
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT value FROM properties WHERE name='PrimaryEmail'")
        for row in cursor.fetchall():
            if row[0]:
                emails.add(row[0].strip().lower())
        conn.close()
    except Exception as e:
        logger.error(f"Failed to read sqlite DB at {db_path}: {e}")
    return emails

def verify_contacts_imported(traj, env_info, task_info):
    """
    Verification strategy:
    1. Retrieve exported address book DB and metadata.
    2. Check if DB was modified after task started (Anti-gaming).
    3. Check how many of the 12 expected emails exist in the database.
    4. Check for 3 specific sentinel emails.
    5. VLM evaluation of trajectory to confirm workflow was followed.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_emails = set(e.lower() for e in metadata.get('all_expected_emails', []))
    sentinel_emails = [e.lower() for e in metadata.get('sentinel_emails', [])]

    feedback_parts = []
    score = 0
    max_score = 100

    temp_dir = tempfile.mkdtemp()
    tar_path = os.path.join(temp_dir, "export.tar.gz")
    json_path = os.path.join(temp_dir, "task_result.json")

    try:
        # Copy export data from the container
        try:
            copy_from_env("/tmp/task_result.json", json_path)
            copy_from_env("/tmp/thunderbird_export.tar.gz", tar_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}

        # Read JSON metadata
        with open(json_path, 'r') as f:
            result_data = json.load(f)

        # Unpack the tar archive containing the abook.sqlite files
        with tarfile.open(tar_path, "r:gz") as tar:
            tar.extractall(path=temp_dir)

        # Identify all databases
        found_emails = set()
        db_files = [f for f in os.listdir(temp_dir) if f.startswith('abook') and f.endswith('.sqlite')]
        
        if not db_files:
            feedback_parts.append("Address book database not found")
        else:
            # Aggregate all emails from all potential address book files
            for db_file in db_files:
                emails = extract_emails_from_db(os.path.join(temp_dir, db_file))
                found_emails.update(emails)

        # Count matches
        matched_emails = expected_emails.intersection(found_emails)
        match_count = len(matched_emails)

        # Anti-gaming: Check if database was actually modified during task
        initial_mtime = result_data.get('initial_abook_mtime', 0)
        final_mtime = result_data.get('final_abook_mtime', 0)
        
        if final_mtime > initial_mtime or len(db_files) > 1:
            score += 5
            feedback_parts.append("Database modified during task")
        else:
            feedback_parts.append("Database mtime unchanged (potential zero-action)")

        # Evaluate contacts found
        if match_count >= 1:
            score += 10
            feedback_parts.append(f"Imported {match_count} contacts")
        if match_count >= 6:
            score += 15
        if match_count >= 10:
            score += 15
        if match_count == 12:
            score += 10
            feedback_parts.append("All 12 contacts imported successfully")

        # Sentinel checks
        for sentinel in sentinel_emails:
            if sentinel in found_emails:
                score += 10
                feedback_parts.append(f"Sentinel '{sentinel}' found")
            else:
                feedback_parts.append(f"Sentinel '{sentinel}' MISSING")

        # VLM Trajectory Verification
        vlm_score = 0
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_result = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("address_book_opened", False):
                    vlm_score += 5
                    feedback_parts.append("VLM confirmed Address Book opened")
                if parsed.get("import_dialog_visible", False):
                    vlm_score += 10
                    feedback_parts.append("VLM confirmed Import dialog usage")
            else:
                feedback_parts.append("VLM evaluation failed or returned negative")
        else:
            feedback_parts.append("No trajectory frames available for VLM")

        score += min(vlm_score, 15)

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        feedback_parts.append(f"Error during verification: {e}")
    finally:
        # Cleanup
        for f in os.listdir(temp_dir):
            os.unlink(os.path.join(temp_dir, f))
        os.rmdir(temp_dir)

    # Consider passed if they got a majority of the contacts and VLM verifies workflow
    # Pass threshold: 60 points (e.g., modified db + 6 contacts + some sentinel/vlm)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }