#!/usr/bin/env python3
"""
Verifier for USDA Crop Market Research task.

Scoring (100 points):
- Brief file exists & created during task: 10 points
- Brief mentions 3 commodities (corn, soybean, wheat): 15 points
- Brief contains price figures ($X.XX or cents): 20 points
- Brief contains USDA citations: 10 points
- Brief contains recommendation: 10 points
- Browser history shows USDA visits: 20 points
- File downloaded from USDA (or just exists in Downloads): 15 points

Pass Threshold: 65 points
"""

import json
import os
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_crop_market_research(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    brief = result.get('brief', {})
    history = result.get('history', {})
    downloads = result.get('downloads', {})

    # Criterion 1: Brief Existence (10 pts)
    if brief.get('exists') and brief.get('created_during_task'):
        score += 10
        feedback_parts.append("Brief created")
    elif brief.get('exists'):
        score += 5
        feedback_parts.append("Brief exists but not new")
    else:
        feedback_parts.append("Brief not found")

    # Content Analysis
    content = brief.get('content_snippet', '').lower()
    
    # Criterion 2: Commodities (15 pts)
    commodities = ["corn", "wheat"]
    soy_terms = ["soybean", "soybeans", "soy"]
    
    has_corn = "corn" in content
    has_wheat = "wheat" in content
    has_soy = any(t in content for t in soy_terms)
    
    comm_count = sum([has_corn, has_wheat, has_soy])
    if comm_count == 3:
        score += 15
        feedback_parts.append("All commodities found")
    elif comm_count > 0:
        score += 5 * comm_count
        feedback_parts.append(f"Found {comm_count}/3 commodities")
    else:
        feedback_parts.append("No commodities mentioned")

    # Criterion 3: Price Figures (20 pts)
    # Regex for $X.XX or X.XX cents or X.XX/bu
    price_pattern = re.compile(r'(\$\d+\.?\d*|\d+\.?\d*\s*cents|\d+\.?\d*\s*per\s*bu|\d+\.?\d*\s*\/bu)')
    prices_found = price_pattern.findall(content)
    
    if len(prices_found) >= 3:
        score += 20
        feedback_parts.append("Price figures found")
    elif len(prices_found) > 0:
        score += 10
        feedback_parts.append("Some price figures found")
    else:
        feedback_parts.append("No price figures found")

    # Criterion 4: USDA Citations (10 pts)
    citations = ["usda", "ers", "nass", "wasde", "market news", "gov"]
    if any(c in content for c in citations):
        score += 10
        feedback_parts.append("USDA citations found")
    else:
        feedback_parts.append("No citations found")

    # Criterion 5: Recommendation (10 pts)
    rec_terms = ["recommend", "allocate", "plant", "suggest", "acreage", "strategy"]
    if any(r in content for r in rec_terms):
        score += 10
        feedback_parts.append("Recommendation found")
    else:
        feedback_parts.append("No recommendation found")

    # Criterion 6: Browser History (20 pts)
    usda_visits = history.get('usda_visits_count', 0)
    if usda_visits >= 2:
        score += 20
        feedback_parts.append("USDA sites visited")
    elif usda_visits == 1:
        score += 10
        feedback_parts.append("Minimal USDA visits")
    else:
        feedback_parts.append("No USDA visits detected")

    # Criterion 7: Downloads (15 pts)
    dl_count = downloads.get('count', 0)
    if dl_count > 0:
        score += 15
        feedback_parts.append("Data file downloaded")
    else:
        feedback_parts.append("No file downloaded")

    # Final tally
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }