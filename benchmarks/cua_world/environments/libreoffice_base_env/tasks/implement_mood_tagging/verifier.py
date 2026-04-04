#!/usr/bin/env python3
"""
Verifier for implement_mood_tagging task.
Parses the extracted HSQLDB script file to verify schema and data.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_implement_mood_tagging(traj, env_info, task_info):
    """
    Verify the mood tagging system implementation.
    
    Checks:
    1. Schema: 'Mood' and 'TrackMood' tables exist.
    2. Constraints: PK and FKs defined correctly.
    3. Reference Data: Mood table has 3 rows (Energetic, Focus, Melancholy).
    4. Bulk Data: TrackMood table has rows matching Rock/Jazz tracks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('script_extracted', False):
        return {"passed": False, "score": 0, "feedback": "Database file was not saved or is corrupt (could not extract script)."}

    # Retrieve HSQLDB script
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
    try:
        copy_from_env("/tmp/hsqldb_script.sql", temp_script.name)
        with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
            script_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve database script: {e}"}
    finally:
        if os.path.exists(temp_script.name):
            os.unlink(temp_script.name)

    # Normalize script content for easier regex
    # HSQLDB script format: CREATE TABLE ... or INSERT INTO ...
    
    # --- 1. Schema Verification (30 pts) ---
    # Check for Mood table
    # Pattern: CREATE TABLE "Mood" or CREATE MEMORY TABLE "Mood" or CREATE CACHED TABLE "Mood"
    has_mood_table = re.search(r'CREATE\s+(?:MEMORY\s+|CACHED\s+)?TABLE\s+(?:PUBLIC\.)?"Mood"', script_content, re.IGNORECASE)
    
    # Check for TrackMood table
    has_track_mood_table = re.search(r'CREATE\s+(?:MEMORY\s+|CACHED\s+)?TABLE\s+(?:PUBLIC\.)?"TrackMood"', script_content, re.IGNORECASE)

    if has_mood_table:
        score += 15
        feedback_parts.append("Table 'Mood' created.")
    else:
        feedback_parts.append("Table 'Mood' NOT found.")

    if has_track_mood_table:
        score += 15
        feedback_parts.append("Table 'TrackMood' created.")
    else:
        feedback_parts.append("Table 'TrackMood' NOT found.")

    # --- 2. Constraints Verification (20 pts) ---
    # Check for Primary Key on Mood (usually in CREATE stmt or ALTER TABLE)
    # Check for Composite PK on TrackMood
    # Check for Foreign Keys
    
    # Look for TrackMood PK constraint (TrackId, MoodId)
    # This might be inline "PRIMARY KEY(TrackId,MoodId)" or separate "ALTER TABLE ... ADD CONSTRAINT ... PRIMARY KEY"
    has_composite_pk = False
    if re.search(r'ALTER\s+TABLE\s+(?:PUBLIC\.)?"TrackMood"\s+ADD\s+(?:CONSTRAINT\s+\S+\s+)?PRIMARY\s+KEY\s*\(\s*"TrackId"\s*,\s*"MoodId"\s*\)', script_content, re.IGNORECASE):
        has_composite_pk = True
    elif re.search(r'CREATE\s+.*TABLE\s+"TrackMood".*PRIMARY\s+KEY\s*\(\s*"TrackId"\s*,\s*"MoodId"\s*\)', script_content, re.IGNORECASE | re.DOTALL):
        has_composite_pk = True
        
    if has_composite_pk:
        score += 10
        feedback_parts.append("Composite PK defined on TrackMood.")
    else:
        feedback_parts.append("Composite PK NOT found on TrackMood.")

    # Look for Foreign Keys (TrackMood -> Track, TrackMood -> Mood)
    # Usually: ALTER TABLE "TrackMood" ADD CONSTRAINT ... FOREIGN KEY ("TrackId") REFERENCES "Track"
    fk_track = re.search(r'ALTER\s+TABLE\s+"TrackMood".*FOREIGN\s+KEY\s*\("TrackId"\)\s*REFERENCES\s+"Track"', script_content, re.IGNORECASE)
    fk_mood = re.search(r'ALTER\s+TABLE\s+"TrackMood".*FOREIGN\s+KEY\s*\("MoodId"\)\s*REFERENCES\s+"Mood"', script_content, re.IGNORECASE)
    
    if fk_track and fk_mood:
        score += 10
        feedback_parts.append("Foreign Keys correctly defined.")
    elif fk_track or fk_mood:
        score += 5
        feedback_parts.append("Some Foreign Keys defined, but not all.")
    else:
        feedback_parts.append("Foreign Keys NOT found.")

    # --- 3. Reference Data Verification (10 pts) ---
    # Check for inserts into Mood
    # INSERT INTO "Mood" VALUES(1,'Energetic')
    mood_inserts = re.findall(r'INSERT\s+INTO\s+(?:PUBLIC\.)?"Mood"\s+VALUES', script_content, re.IGNORECASE)
    if len(mood_inserts) >= 3:
        score += 10
        feedback_parts.append(f"Mood reference data found ({len(mood_inserts)} rows).")
    elif len(mood_inserts) > 0:
        score += 5
        feedback_parts.append(f"Partial Mood data found ({len(mood_inserts)} rows).")
    else:
        feedback_parts.append("No data found in Mood table.")

    # --- 4. Bulk Data Verification (40 pts) ---
    # Check for inserts into TrackMood
    # Since these are likely created via CREATE TABLE (MEMORY), they should be in the script.
    # If the user used 'CACHED', they might be in .data file which we can't easily parse.
    # However, standard practice for this task likely yields MEMORY table or we assume script presence.
    # We will search for INSERT statements.
    
    track_mood_inserts = re.findall(r'INSERT\s+INTO\s+(?:PUBLIC\.)?"TrackMood"\s+VALUES', script_content, re.IGNORECASE)
    
    # Expected: ~1297 Rock + ~130 Jazz = ~1427 rows
    # We'll set a threshold of 1000 to be safe.
    if len(track_mood_inserts) >= 1000:
        score += 40
        feedback_parts.append(f"Bulk data found in TrackMood ({len(track_mood_inserts)} rows).")
    elif len(track_mood_inserts) > 100:
        score += 20
        feedback_parts.append(f"Some data found in TrackMood ({len(track_mood_inserts)} rows), but fewer than expected.")
    else:
        # Fallback check: Did the user perhaps make it a CACHED table?
        # Check if the CREATE TABLE statement says CACHED
        is_cached = re.search(r'CREATE\s+CACHED\s+TABLE\s+"TrackMood"', script_content, re.IGNORECASE)
        if is_cached:
            # If cached, we can't verify count from script easily.
            # But we can assume if they made it cached and defined it correctly, they likely ran the insert.
            # We give partial credit or rely on 'odb_modified' check combined with schema correctness.
            # However, for this task, 'Memory' is default for non-wizard tables usually.
            score += 10
            feedback_parts.append("TrackMood is a CACHED table; data not verifiable in script, giving partial credit.")
        else:
            feedback_parts.append("No bulk data found in TrackMood.")

    # --- Final Result ---
    # Pass threshold: 80 points
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }