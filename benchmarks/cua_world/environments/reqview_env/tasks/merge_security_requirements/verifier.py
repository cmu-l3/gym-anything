#!/usr/bin/env python3
"""Verifier for merge_security_requirements task.

Criteria:
1. ASVS document is removed from the project structure (project.json).
2. SRS document contains a section "Security Requirements".
3. SRS document contains the content from the original ASVS document (verified via fingerprint).
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Paths inside the container
PROJECT_BASE = "/home/ga/Documents/ReqView/merge_security_project"
PROJECT_JSON_PATH = f"{PROJECT_BASE}/project.json"
SRS_JSON_PATH = f"{PROJECT_BASE}/documents/SRS.json"
FINGERPRINT_PATH = "/tmp/asvs_fingerprint.txt"


def _strip_html(text):
    """Remove HTML tags/entities for cleaner comparison."""
    if not text:
        return ""
    text = re.sub(r'<[^>]+>', ' ', str(text))  # Replace tags with space
    text = re.sub(r'\s+', ' ', text).strip()   # Normalize whitespace
    return text


def _find_section_recursive(items, title_pattern):
    """Recursively search for a section with a matching heading."""
    for item in items:
        # Check heading
        heading = _strip_html(item.get('heading', ''))
        if re.search(title_pattern, heading, re.IGNORECASE):
            return True
        
        # Recurse
        if 'children' in item:
            if _find_section_recursive(item['children'], title_pattern):
                return True
    return False


def _find_text_recursive(items, search_text):
    """Recursively search for specific text in requirement description/text."""
    search_norm = _strip_html(search_text).lower()
    if not search_norm or len(search_norm) < 10:
        return False # Fingerprint too short/invalid to rely on
        
    for item in items:
        # Check text fields
        content = _strip_html(item.get('text', '') + " " + item.get('description', '')).lower()
        if search_norm in content:
            return True
            
        # Recurse
        if 'children' in item:
            if _find_text_recursive(item['children'], search_text):
                return True
    return False


def verify_merge_security_requirements(traj, env_info, task_info):
    """Verify the consolidation of security requirements."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Fingerprint
    fingerprint_text = ""
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        try:
            copy_from_env(FINGERPRINT_PATH, tmp.name)
            with open(tmp.name, 'r') as f:
                fingerprint_text = f.read().strip()
        except Exception:
            # If fingerprint file is missing, we can't verify content, but can verify structure
            logger.warning("Could not read fingerprint file from container.")
        finally:
            os.unlink(tmp.name)

    # 2. Check Project Structure (ASVS Removal)
    # We check project.json to see if 'ASVS' is still listed in 'documents'
    asvs_removed = False
    with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
        try:
            copy_from_env(PROJECT_JSON_PATH, tmp.name)
            with open(tmp.name, 'r') as f:
                project_data = json.load(f)
            
            # project_data['documents'] is usually a list of strings (doc IDs) or dicts
            documents = project_data.get('documents', [])
            
            # Check if ASVS is in the list
            if "ASVS" not in documents:
                score += 30
                asvs_removed = True
                feedback_parts.append("ASVS document successfully removed from project")
            else:
                feedback_parts.append("ASVS document still exists in project")
                
        except Exception as e:
            feedback_parts.append(f"Failed to check project.json: {e}")
        finally:
            os.unlink(tmp.name)

    # 3. Check SRS Content (Section + Fingerprint)
    srs_valid = False
    with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
        try:
            copy_from_env(SRS_JSON_PATH, tmp.name)
            with open(tmp.name, 'r') as f:
                srs_data = json.load(f)
            
            items = srs_data.get('data', [])
            
            # Check 3a: Section Creation (20 pts)
            if _find_section_recursive(items, r"Security\s*Requirements"):
                score += 20
                feedback_parts.append("'Security Requirements' section found")
            else:
                feedback_parts.append("'Security Requirements' section missing")

            # Check 3b: Content Transfer (50 pts)
            # We look for the fingerprint text inside SRS
            if fingerprint_text and "ERROR" not in fingerprint_text:
                if _find_text_recursive(items, fingerprint_text):
                    score += 50
                    feedback_parts.append("ASVS content verified inside SRS")
                else:
                    feedback_parts.append("ASVS content NOT found in SRS")
            else:
                # Fallback if fingerprint failed: check for generic security terms
                if _find_text_recursive(items, "Application Security Verification Standard") or \
                   _find_text_recursive(items, "OWASP") or \
                   _find_text_recursive(items, "Authentication"):
                    score += 50
                    feedback_parts.append("Generic security content found in SRS (Fingerprint fallback)")
                else:
                    feedback_parts.append("No security requirements found in SRS")

        except Exception as e:
            feedback_parts.append(f"Failed to check SRS.json: {e}")
        finally:
            os.unlink(tmp.name)

    # Final Pass Determination
    # Must remove old doc AND have moved content. 
    # Partial credit allowed, but 'passed' requires significant completion.
    passed = (score >= 80) # Requires removal (30) + content (50) OR section (20) + content (50) + part of removal?
                           # Actually, strictly: 30+20+50 = 100.
                           # Let's say 80 is pass (allows maybe section title typo but content is there, or similar).
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }