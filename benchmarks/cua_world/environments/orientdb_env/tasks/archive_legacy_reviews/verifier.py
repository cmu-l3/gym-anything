#!/usr/bin/env python3
"""
Verifier for archive_legacy_reviews task.

Verifies that:
1. 'ArchivedReviews' class exists.
2. Legacy reviews (Date < 2015) are gone from 'Reviews' class.
3. 'ArchivedReviews' contains the correct number of records.
4. 'ArchivedReviews' records have correct fields (AuthorEmail, HotelName).
5. Modern reviews (Date >= 2015) are preserved in 'Reviews'.
"""

import json
import os
import urllib.request
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# OrientDB Configuration
ORIENTDB_URL = "http://localhost:2480"
ORIENTDB_USER = "root"
ORIENTDB_PASS = "GymAnything123!"
DB_NAME = "demodb"

def orientdb_sql(command):
    """Execute SQL command against OrientDB."""
    auth = base64.b64encode(f"{ORIENTDB_USER}:{ORIENTDB_PASS}".encode()).decode()
    url = f"{ORIENTDB_URL}/command/{DB_NAME}/sql"
    data = json.dumps({"command": command}).encode()
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Basic {auth}",
            "Content-Type": "application/json"
        },
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except Exception as e:
        logger.error(f"SQL Error: {e}")
        return {}

def verify_archive_legacy_reviews(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load initial state (expected counts)
    initial_legacy_count = 0
    initial_modern_count = 0
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
            initial_legacy_count = result_data.get('legacy_count', 0)
            initial_modern_count = result_data.get('modern_count', 0)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Verify 'ArchivedReviews' class exists (20 pts)
    schema_res = orientdb_sql("SELECT name FROM (SELECT expand(classes) FROM metadata:schema)")
    classes = [c.get('name') for c in schema_res.get('result', [])]
    
    if "ArchivedReviews" in classes:
        score += 20
        feedback.append("Class 'ArchivedReviews' exists.")
    else:
        return {"passed": False, "score": 0, "feedback": "Class 'ArchivedReviews' NOT found."}

    # 3. Verify Legacy Data Migration (30 pts)
    # Count records in Archive
    archive_count_res = orientdb_sql("SELECT COUNT(*) as cnt FROM ArchivedReviews")
    current_archive_count = archive_count_res.get('result', [{}])[0].get('cnt', 0)
    
    if current_archive_count == initial_legacy_count:
        score += 30
        feedback.append(f"Archive count matches expected legacy count ({current_archive_count}).")
    elif current_archive_count > 0:
        score += 15
        feedback.append(f"Partial archive: found {current_archive_count} records, expected {initial_legacy_count}.")
    else:
        feedback.append("No records found in 'ArchivedReviews'.")

    # 4. Verify Context Preservation (20 pts)
    # Check if AuthorEmail and HotelName are populated in the archive
    # We'll sample 5 records
    sample_res = orientdb_sql("SELECT AuthorEmail, HotelName FROM ArchivedReviews LIMIT 5")
    samples = sample_res.get('result', [])
    
    if samples:
        valid_samples = 0
        for s in samples:
            if s.get('AuthorEmail') and s.get('HotelName'):
                valid_samples += 1
        
        if valid_samples == len(samples):
            score += 20
            feedback.append("Archived records contain 'AuthorEmail' and 'HotelName'.")
        else:
            score += 5
            feedback.append("Some archived records are missing 'AuthorEmail' or 'HotelName'.")
    else:
        feedback.append("Cannot verify fields - no records in archive.")

    # 5. Verify Legacy Cleanup (20 pts)
    # Count remaining reviews with Date < 2015
    cleanup_res = orientdb_sql("SELECT COUNT(*) as cnt FROM Reviews WHERE Date < '2015-01-01'")
    remaining_legacy = cleanup_res.get('result', [{}])[0].get('cnt', 0)
    
    if remaining_legacy == 0:
        score += 20
        feedback.append("Legacy reviews successfully removed from active graph.")
    else:
        feedback.append(f"Cleanup incomplete: {remaining_legacy} legacy reviews remain in 'Reviews'.")

    # 6. Safety Check: Modern Data Preservation (10 pts)
    modern_res = orientdb_sql("SELECT COUNT(*) as cnt FROM Reviews WHERE Date >= '2015-01-01'")
    current_modern_count = modern_res.get('result', [{}])[0].get('cnt', 0)
    
    # Allow small fluctuations if agent added data, but surely shouldn't lose data
    if current_modern_count >= initial_modern_count:
        score += 10
        feedback.append("Modern reviews preserved.")
    else:
        lost = initial_modern_count - current_modern_count
        feedback.append(f"DATA LOSS DETECTED: {lost} modern reviews were accidentally deleted.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }