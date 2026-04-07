#!/usr/bin/env python3
"""Verifier for Create Glossary with Entries task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_glossary_with_entries(traj, env_info, task_info):
    """
    Verify that the glossary was created with correct settings and entries.

    Scoring (100 points total):
    1. Glossary Activity (45 pts):
       - Exists in BIO101 (15 pts)
       - Name contains "Medical Terminology" (10 pts)
       - Created after task start (5 pts)
       - Default approval = Yes (10 pts)
       - Duplicate entries = No (5 pts)

    2. Entries (55 pts):
       - "Mitochondria" entry exists (10 pts) + definition content check (5 pts)
       - "Homeostasis" entry exists (10 pts) + definition content check (5 pts)
       - "Pathogen" entry exists (10 pts) + definition content check (5 pts)
       - Total entry count >= 3 (10 pts)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_glossary_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. GLOSSARY VERIFICATION
        # -------------------------
        glossary_found = result.get('glossary_found', False)
        
        if not glossary_found:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Glossary 'Medical Terminology' not found in BIO101 course."
            }
        
        # Exists in BIO101 (15 pts)
        score += 15
        feedback_parts.append("Glossary found")

        # Name check (10 pts)
        name = result.get('glossary_name', '')
        if "medical terminology" in name.lower():
            score += 10
            feedback_parts.append("Name correct")
        else:
            feedback_parts.append(f"Name mismatch ('{name}')")

        # Timestamp check (5 pts)
        task_start = int(result.get('task_start_time', 0))
        timemodified = int(result.get('timemodified', 0))
        if timemodified > task_start:
            score += 5
        else:
            feedback_parts.append("Glossary not modified during task")

        # Settings check
        # Default approval: 1 = Yes (10 pts)
        if int(result.get('default_approval', 0)) == 1:
            score += 10
            feedback_parts.append("Auto-approval enabled")
        else:
            feedback_parts.append("Auto-approval disabled (expected enabled)")

        # Allow duplicates: 0 = No (5 pts)
        if int(result.get('allow_duplicates', 1)) == 0:
            score += 5
            feedback_parts.append("Duplicates disallowed")
        else:
            feedback_parts.append("Duplicates allowed (expected disallowed)")

        # 2. ENTRIES VERIFICATION
        # -----------------------
        entries = result.get('entries', [])
        entry_count = len(entries)
        
        # Check count (10 pts if >= 3)
        if entry_count >= 3:
            score += 10
            feedback_parts.append(f"Found {entry_count} entries")
        else:
            feedback_parts.append(f"Only {entry_count} entries found (expected 3+)")

        # Verify specific entries
        expected_entries = metadata.get('entries', [])
        
        # Helper to find entry
        def find_entry(concept_key):
            for e in entries:
                if concept_key.lower() in e.get('concept', '').lower():
                    return e
            return None

        # Helper to check definition keywords
        def check_definition(text, keywords):
            text_lower = text.lower()
            return any(k.lower() in text_lower for k in keywords)

        for target in expected_entries:
            concept = target['concept']
            keywords = target['keywords']
            
            match = find_entry(concept)
            if match:
                score += 10
                feedback_parts.append(f"'{concept}' entry found")
                
                # Check definition content (5 pts)
                defi = match.get('definition', '')
                if check_definition(defi, keywords):
                    score += 5
                else:
                    feedback_parts.append(f"'{concept}' definition incomplete")
            else:
                feedback_parts.append(f"'{concept}' entry missing")

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON in result file"}
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}