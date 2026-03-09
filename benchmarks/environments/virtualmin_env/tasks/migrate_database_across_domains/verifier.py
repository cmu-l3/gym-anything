#!/usr/bin/env python3
"""Verifier for migrate_database_across_domains task.

Scoring (100 points):
- Correct domain: prerequisite (score=0 if wrong)
- Catalog database created under brightstar.test: 20 points
- Sakila grant given to brightstar user: 20 points
- video_categories table exists with correct schema: 25 points
- Table has 5+ rows with real genre categories: 20 points
- Categories match known Sakila genres: 15 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

# Real Sakila categories for cross-reference
SAKILA_CATEGORIES = {
    'action', 'animation', 'children', 'classics', 'comedy',
    'documentary', 'drama', 'family', 'foreign', 'games',
    'horror', 'music', 'new', 'sci-fi', 'sports', 'travel'
}


def verify_migrate_database_across_domains(traj, env_info, task_info):
    """Verify database migration and creation for brightstar.test."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_domain = metadata.get('target_domain', 'brightstar.test')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/migrate_database_across_domains_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # CRITICAL: Check correct domain
        if result.get('domain') != expected_domain:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"CRITICAL: Wrong domain! Expected {expected_domain}, got {result.get('domain')}"
            }

        # Subtask 1: Catalog database created (20 points)
        if result.get('catalog_db_exists'):
            db_name = result.get('catalog_db_name', '')
            if 'catalog' in db_name.lower():
                score += 20
                subscores["catalog_db"] = True
                feedback_parts.append(f"Catalog database created: {db_name}")
            else:
                score += 10
                feedback_parts.append(f"Database created but name doesn't contain 'catalog': {db_name}")
        else:
            feedback_parts.append("Catalog database NOT found")

        # Subtask 2: Sakila grant (20 points)
        if result.get('sakila_grant'):
            score += 20
            subscores["sakila_grant"] = True
            feedback_parts.append("Brightstar user has access to sakila database")
        else:
            feedback_parts.append("Brightstar user does NOT have sakila access")

        # Subtask 3: video_categories table with correct schema (25 points)
        if result.get('table_exists'):
            schema_score = 0
            has_cols = []
            missing_cols = []
            for col in ['id', 'name', 'description', 'created_at']:
                key = f'has_{col}_column'
                if result.get(key):
                    schema_score += 1
                    has_cols.append(col)
                else:
                    missing_cols.append(col)

            if schema_score == 4:
                score += 25
                subscores["table_schema"] = True
                feedback_parts.append("video_categories table has all required columns")
            elif schema_score >= 2:
                score += 15
                feedback_parts.append(f"video_categories table has {schema_score}/4 columns (missing: {missing_cols})")
            else:
                score += 5
                feedback_parts.append(f"video_categories table exists but missing columns: {missing_cols}")
        else:
            feedback_parts.append("video_categories table NOT found")

        # Subtask 4: At least 5 rows (20 points)
        row_count = result.get('row_count', 0)
        if row_count >= 5:
            score += 20
            subscores["row_count"] = True
            feedback_parts.append(f"Table has {row_count} rows (≥5 required)")
        elif row_count > 0:
            partial = int(20 * row_count / 5)
            score += partial
            feedback_parts.append(f"Table has {row_count} rows (need 5+, partial credit: {partial} pts)")
        else:
            feedback_parts.append("Table has 0 rows")

        # Subtask 5: Categories match Sakila genres (15 points)
        category_names = result.get('category_names', '')
        if category_names:
            inserted = set(c.strip().lower() for c in category_names.split('|') if c.strip())
            matches = inserted & SAKILA_CATEGORIES
            if len(matches) >= 3:
                score += 15
                subscores["real_categories"] = True
                feedback_parts.append(f"Categories match Sakila genres: {sorted(matches)}")
            elif len(matches) >= 1:
                score += 7
                feedback_parts.append(f"Some categories match Sakila: {sorted(matches)} ({len(matches)}/3+ needed)")
            else:
                feedback_parts.append(f"No categories match Sakila genres: {sorted(inserted)}")
        else:
            feedback_parts.append("No category names found")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No database work done",
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
