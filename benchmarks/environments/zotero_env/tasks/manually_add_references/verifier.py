#!/usr/bin/env python3
"""
Verifier for manually_add_references task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manually_add_references(traj, env_info, task_info):
    """
    Verify creation of 3 specific bibliographic items.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check item delta
    initial_count = result.get("initial_count", 0)
    final_count = result.get("final_count", 0)
    delta = final_count - initial_count
    
    if delta >= 3:
        score += 8
        feedback_parts.append(f"Item count increased by {delta} (>=3)")
    elif delta > 0:
        score += 4
        feedback_parts.append(f"Item count increased by {delta} (expected 3)")
    else:
        feedback_parts.append("No new items detected")

    # Helper for substring matching case-insensitive
    def check_contains(text, substring):
        return substring.lower() in str(text).lower()

    items_found = result.get("items_found", {})

    # === BOOK VERIFICATION (30 points total) ===
    book_res = items_found.get("book", {})
    if book_res.get("found"):
        details = book_res.get("details", {})
        score += 10 # Title match (implied by found status from export script)
        feedback_parts.append("Book title found")
        
        # Type
        if details.get("type") == "book":
            score += 5
        else:
            feedback_parts.append(f"Book type mismatch: {details.get('type')}")

        # Author (Kuhn)
        creators = details.get("creators", [])
        if any("Kuhn" in c.get("last", "") for c in creators):
            score += 5
        else:
            feedback_parts.append("Book author 'Kuhn' missing")

        # Date
        if "1962" in details.get("date", ""):
            score += 3

        # Publisher
        if "University of Chicago" in details.get("publisher", ""):
            score += 2
            
        # Place (implicit bonus or part of full metadata check, sticking to rubric)
        # Rubric: 10(title)+5(type)+5(auth)+3(date)+2(pub) = 25 pts + delta share
        # Wait, rubric says Book is worth 25 points total specific + 8 global delta share
    else:
        feedback_parts.append("Book 'Structure of Scientific Revolutions' NOT found")

    # === ARTICLE VERIFICATION (32 points total) ===
    art_res = items_found.get("article", {})
    if art_res.get("found"):
        details = art_res.get("details", {})
        score += 10 # Title
        feedback_parts.append("Article title found")
        
        # Type
        if details.get("type") == "journalArticle":
            score += 5
        else:
            feedback_parts.append(f"Article type mismatch: {details.get('type')}")
            
        # Author (Granovetter)
        creators = details.get("creators", [])
        if any("Granovetter" in c.get("last", "") for c in creators):
            score += 5

        # Date
        if "1973" in details.get("date", ""):
            score += 3
            
        # Publication Title
        if "American Journal of Sociology" in details.get("publicationTitle", ""):
            score += 4
            
        # Volume
        if details.get("volume") == "78":
            score += 3
            
        # Pages (check 1360)
        if "1360" in details.get("pages", ""):
            score += 2
    else:
        feedback_parts.append("Article 'Strength of Weak Ties' NOT found")

    # === CONFERENCE VERIFICATION (30 points total) ===
    conf_res = items_found.get("conference", {})
    if conf_res.get("found"):
        details = conf_res.get("details", {})
        score += 10 # Title
        feedback_parts.append("Conference paper title found")
        
        # Type
        if details.get("type") == "conferencePaper":
            score += 5
        else:
            feedback_parts.append(f"Conf paper type mismatch: {details.get('type')}")
            
        # Authors (Brin AND Page)
        creators = details.get("creators", [])
        has_brin = any("Brin" in c.get("last", "") for c in creators)
        has_page = any("Page" in c.get("last", "") for c in creators)
        
        if has_brin: score += 5
        else: feedback_parts.append("Author Brin missing")
        
        if has_page: score += 5
        else: feedback_parts.append("Author Page missing")
        
        # Date
        if "1998" in details.get("date", ""):
            score += 3
            
        # Proceedings
        # Field name can be proceedingsTitle or publicationTitle depending on Zotero version schema mapping
        proc = details.get("proceedingsTitle", details.get("publicationTitle", ""))
        if "World Wide Web" in proc:
            score += 5
            
        # Pages
        if "107" in details.get("pages", ""):
            score += 2
    else:
        feedback_parts.append("Conf paper 'Anatomy of a Large-Scale' NOT found")

    # Final Check
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }