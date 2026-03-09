#!/usr/bin/env python3
"""
Verifier for implement_room_migration task.

Scoring Criteria (100 points total):
1. Entity Updated (20 pts): `Task.kt` has `priority` field.
2. Database Version (10 pts): Version incremented to 2.
3. Migration Defined (25 pts): `Migration` object exists with SQL.
4. Valid SQL (20 pts): `ALTER TABLE ... ADD COLUMN ...` correct syntax.
5. Migration Registered (15 pts): `.addMigrations` called.
6. Tests Passed (10 pts): Unit tests passed successfully.
"""

import json
import logging
import re
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_room_migration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    score = 0
    feedback = []
    
    task_content = result.get("task_kt_content", "")
    db_content = result.get("db_file_content", "")
    
    # 1. Check Entity (20 pts)
    # Looking for: val priority: Int ... = 0
    # Allow vars, spaces, newlines
    priority_pattern = r"(val|var)\s+priority\s*:\s*Int"
    if re.search(priority_pattern, task_content):
        score += 20
        feedback.append("Entity updated with priority field (20/20)")
    else:
        feedback.append("Entity missing 'priority: Int' field (0/20)")

    # 2. Check DB Version (10 pts)
    # version = 2
    if re.search(r"version\s*=\s*2", db_content):
        score += 10
        feedback.append("Database version incremented to 2 (10/10)")
    else:
        feedback.append("Database version not updated to 2 (0/10)")

    # 3. Migration Object (25 pts)
    # val MIGRATION_1_2 = object : Migration(1, 2)
    # or just Migration(1, 2) inside a variable
    if re.search(r"Migration\s*\(\s*1\s*,\s*2\s*\)", db_content):
        score += 25
        feedback.append("Migration(1, 2) defined (25/25)")
    else:
        feedback.append("Migration object (1 to 2) not found (0/25)")

    # 4. Valid SQL (20 pts)
    # ALTER TABLE tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 0
    # Be flexible with whitespace and casing
    sql_pattern = r"ALTER\s+TABLE\s+tasks\s+ADD\s+COLUMN\s+priority\s+INTEGER\s+NOT\s+NULL\s+DEFAULT\s+0"
    if re.search(sql_pattern, db_content, re.IGNORECASE):
        score += 20
        feedback.append("Correct SQL statement found (20/20)")
    else:
        feedback.append("SQL statement missing or incorrect (0/20)")

    # 5. Migration Registered (15 pts)
    # .addMigrations(...)
    if ".addMigrations" in db_content:
        score += 15
        feedback.append("Migration added to database builder (15/15)")
    else:
        feedback.append("Migration not added to builder (0/15)")

    # 6. Tests Passed (10 pts)
    if result.get("tests_passed", False):
        score += 10
        feedback.append("Unit tests passed (10/10)")
    else:
        feedback.append("Unit tests did not pass (0/10)")

    # Anti-gaming check
    if not result.get("files_modified", False):
        score = 0
        feedback = ["Files were not modified during the task."]

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback)
    }