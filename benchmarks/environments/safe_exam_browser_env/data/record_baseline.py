#!/usr/bin/env python3
"""Record baseline state from SEB Server database for anti-gaming verification."""

import json
import os
import time
import subprocess
import sys


def db_query(query):
    """Execute a MySQL query against the SEB Server database."""
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()


def main():
    if len(sys.argv) < 2:
        print("Usage: record_baseline.py <task_name>")
        sys.exit(1)

    task_name = sys.argv[1]
    output_file = f"/tmp/seb_task_baseline_{task_name}.json"

    # Remove stale file if it exists (may have been created by different user)
    try:
        os.remove(output_file)
    except (OSError, FileNotFoundError):
        pass

    baseline = {
        'timestamp': time.time(),
        'task': task_name,
        'exam_config_count': int(db_query("SELECT COUNT(*) FROM configuration_node WHERE type='EXAM_CONFIG'") or 0),
        'connection_config_count': int(db_query("SELECT COUNT(*) FROM seb_client_configuration") or 0),
        'user_count': int(db_query("SELECT COUNT(*) FROM user") or 0),
        'exam_count': int(db_query("SELECT COUNT(*) FROM exam") or 0),
        'exam_template_count': int(db_query("SELECT COUNT(*) FROM exam_template") or 0),
        'indicator_count': int(db_query("SELECT COUNT(*) FROM indicator") or 0),
    }

    with open(output_file, 'w') as f:
        json.dump(baseline, f, indent=2)

    print(f"Baseline recorded for {task_name}: {json.dumps(baseline, indent=2)}")


if __name__ == "__main__":
    main()
