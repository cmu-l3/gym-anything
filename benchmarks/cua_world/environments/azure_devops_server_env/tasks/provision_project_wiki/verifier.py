#!/usr/bin/env python3
"""
Verifier for provision_project_wiki task.

Criteria:
1. Wiki provisioned (8 pts)
2. Content verification for specific pages (84 pts total distributed)
   - Home, Architecture/*, Development Guide/*, Runbooks/*
3. Hierarchy verification (8 pts)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_provision_project_wiki(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define Requirements (can also pull from task_info metadata)
    REQUIREMENTS = {
        "/": {
            "name": "Home",
            "score": 12,
            "min_words": 50,
            "keywords": ["TailwindTraders", "e-commerce"]
        },
        "/Architecture/System Overview": {
            "name": "System Overview",
            "score": 15,
            "min_words": 80,
            "keywords": ["microservices"], # + check for headers
            "check_headers": True
        },
        "/Architecture/API Design": {
            "name": "API Design",
            "score": 15,
            "min_words": 60,
            "keywords": ["REST", "200", "404"], # + check for method
            "check_api_example": True
        },
        "/Development Guide/Getting Started": {
            "name": "Getting Started",
            "score": 15,
            "min_words": 80,
            "keywords": ["Prerequisites", "git clone"]
        },
        "/Development Guide/Coding Standards": {
            "name": "Coding Standards",
            "score": 12,
            "min_words": 60,
            "keywords": ["naming"],
            "check_code_block": True
        },
        "/Runbooks/Incident Response": {
            "name": "Incident Response",
            "score": 15,
            "min_words": 80,
            "keywords": ["severity", "escalation"]
        }
    }

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Path in Azure DevOps environment is C:\Users\Docker\task_results...
        # We need to map this path correctly. The environment uses Windows paths.
        copy_from_env("C:\\Users\\Docker\\task_results\\provision_project_wiki_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Wiki Existence
    if result.get("wiki_exists"):
        score += 8
        feedback_parts.append("Project Wiki provisioned (+8)")
    else:
        return {"passed": False, "score": 0, "feedback": "No project wiki found. Did you click 'Create project wiki'?"}

    # Normalization helper for paths (case insensitive comparison)
    found_pages_map = {p.lower(): p for p in result.get("pages_found", [])}
    page_contents = result.get("page_contents", {})
    page_word_counts = result.get("page_word_counts", {})

    # 2. Verify Pages
    pages_passed = 0
    
    for req_path, req_data in REQUIREMENTS.items():
        # Fuzzy match path
        matched_path = found_pages_map.get(req_path.lower())
        
        if not matched_path:
            feedback_parts.append(f"Missing page: {req_path}")
            continue

        content = page_contents.get(matched_path, "")
        word_count = page_word_counts.get(matched_path, 0)
        
        # Content Checks
        content_passed = True
        missed_criteria = []

        # Word count check
        if word_count < req_data["min_words"]:
            content_passed = False
            missed_criteria.append(f"too short ({word_count}/{req_data['min_words']} words)")

        # Keyword checks
        for kw in req_data.get("keywords", []):
            if kw.lower() not in content.lower():
                content_passed = False
                missed_criteria.append(f"missing keyword '{kw}'")

        # Special checks
        if req_data.get("check_headers") and not re.search(r'^#{2,}\s', content, re.MULTILINE):
            content_passed = False
            missed_criteria.append("missing markdown headers")
            
        if req_data.get("check_api_example") and not (re.search(r'GET\s+/', content) or re.search(r'POST\s+/', content)):
            content_passed = False
            missed_criteria.append("missing API endpoint example")
            
        if req_data.get("check_code_block") and "