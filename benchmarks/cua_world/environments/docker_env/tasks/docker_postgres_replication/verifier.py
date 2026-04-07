#!/usr/bin/env python3
"""
Verifier for docker_postgres_replication task.

Scoring (100 points):
- Containers Running (15 pts): 'primary' and 'replica' are up.
- Replication Configured (15 pts): Primary reports active streaming replication.
- Initial Data Sync (20 pts): Replica contains seed data.
- Real-time Replication (25 pts): New data written to Primary appears in Replica.
- Read-Only Enforcement (15 pts): Replica rejects write operations.
- Persistence (10 pts): Named volumes are used.

Pass Threshold: 75 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_postgres_replication(traj, env_info, task_info):
    """Verify PostgreSQL Primary-Replica Cluster configuration."""
    
    # 1. Setup & Read Result JSON
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/db_replication_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)

    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read verification result: {str(e)}. Did you run the export script?"
        }

    score = 0
    feedback_parts = []
    
    # 2. Evaluate Criteria
    
    # Criterion 1: Containers Running (15 pts)
    primary_up = result.get("primary_running", 0)
    replica_up = result.get("replica_running", 0)
    if primary_up and replica_up:
        score += 15
        feedback_parts.append("Both containers running (+15)")
    elif primary_up or replica_up:
        score += 5
        feedback_parts.append("Only one container running (5/15)")
    else:
        feedback_parts.append("No containers running (0/15)")

    # Criterion 2: Replication Configured (15 pts)
    if result.get("replication_active", 0):
        score += 15
        feedback_parts.append("Streaming replication active (+15)")
    else:
        feedback_parts.append("Replication not active in pg_stat_replication (0/15)")

    # Criterion 3: Initial Data Sync (20 pts)
    if result.get("seed_data_present", 0):
        score += 20
        feedback_parts.append("Seed data present in Replica (+20)")
    else:
        cnt = result.get("seed_data_count", 0)
        feedback_parts.append(f"Replica missing seed data (found {cnt} rows) (0/20)")

    # Criterion 4: Real-time Replication (25 pts)
    canary_success = result.get("canary_replicated", 0)
    write_success = result.get("canary_write_success", 0)
    
    if canary_success:
        score += 25
        feedback_parts.append("Real-time replication verified (+25)")
    elif write_success:
        feedback_parts.append("Primary write success but Replica did not receive data (0/25)")
    else:
        feedback_parts.append("Could not write to Primary to test replication (0/25)")

    # Criterion 5: Read-Only Enforcement (15 pts)
    if result.get("read_only_enforced", 0):
        score += 15
        feedback_parts.append("Replica enforces read-only mode (+15)")
    else:
        feedback_parts.append("Replica allows writes or write test failed unexpectedly (0/15)")

    # Criterion 6: Persistence (10 pts)
    if result.get("volumes_exist", 0):
        score += 10
        feedback_parts.append("Named volumes exist (+10)")
    else:
        feedback_parts.append("Named volumes not found (0/10)")

    # 3. Final Result
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }