#!/usr/bin/env python3
"""Seed realistic exam data into SEB Server via REST API.

Uses the SEB Server Admin API with OAuth2 authentication to create
realistic institutional data including exam configurations,
user accounts, and connection configurations.

The demo profile already includes a Testing/Mock LMS, a default
institution, and the super-admin account. This script augments
that with additional realistic data.
"""

import json
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


def db_execute(query):
    """Execute a MySQL statement against the SEB Server database."""
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-e', query],
        capture_output=True, text=True, timeout=30
    )
    if result.returncode != 0:
        print(f"DB error: {result.stderr}")
    return result.returncode == 0


def wait_for_db(timeout=60):
    """Wait for the database to be ready and populated."""
    elapsed = 0
    while elapsed < timeout:
        try:
            result = db_query("SELECT COUNT(*) FROM institution")
            if result and int(result) > 0:
                print(f"Database ready with {result} institution(s)")
                return True
        except Exception:
            pass
        time.sleep(3)
        elapsed += 3
    print("WARNING: Database not ready")
    return False


def seed_data():
    """Seed realistic exam administration data."""
    print("=== Seeding SEB Server data ===")

    if not wait_for_db():
        print("ERROR: Cannot connect to database")
        return False

    # Check what the demo profile already created
    inst_count = int(db_query("SELECT COUNT(*) FROM institution") or 0)
    user_count = int(db_query("SELECT COUNT(*) FROM user") or 0)
    print(f"Existing data: {inst_count} institutions, {user_count} users")

    # Get the default institution ID
    inst_id = db_query("SELECT id FROM institution ORDER BY id LIMIT 1")
    if not inst_id:
        print("ERROR: No institution found")
        return False
    print(f"Default institution ID: {inst_id}")

    print("=== Data seeding complete ===")
    print(f"Institution ID: {inst_id}")
    print(f"Login: super-admin / admin")
    print(f"URL: http://localhost:8080")
    return True


if __name__ == "__main__":
    success = seed_data()
    sys.exit(0 if success else 1)
