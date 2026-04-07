#!/usr/bin/env python3
"""
Verifier for create_reusable_patterns task.

Evaluates if the agent successfully created WordPress reusable blocks (synced patterns)
and utilized them in a newly published post.

Criteria (Programmatic - 80 pts):
1. 'Breaking News Alert' block exists (10 pts) + has correct keywords (10 pts)
2. 'Newsletter Signup' block exists (10 pts) + has correct keywords (10 pts)
3. 'Editorial Disclaimer' block exists (10 pts) + has correct keywords (10 pts)
4. Article "City Council..." exists and was published (10 pts)
5. Article references at least 2 reusable blocks (10 pts, or 5 if just inline text copied)

Criteria (VLM - 20 pts):
6. Agent's trajectory demonstrates opening the block editor, creating/managing patterns,
   and composing a post.

Pass threshold: 60 points AND at least 2 patterns created correctly AND article exists.
"""

import json
import os
import base64
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, images=None):
    """Run VLM query with multiple images for trajectory checking."""
    if not query_vlm or not images:
        return None
    try:
        result = query_vlm(prompt=prompt, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent completing a WordPress task. 
The agent needs to create "Reusable Blocks" (also called Synced Patterns) and then use them in a new Blog Post.

Observe the sequence of images chronologically and assess the following:
1. Did the agent interact with the Pattern/Reusable Block creation UI? (This might be in the Site Editor -> Patterns, or by creating a block in a post and selecting "Create pattern" / "Add to Reusable blocks").
2. Did the agent use the WordPress post editor to create a new post titled something like "City Council Approves New Budget Plan"?
3. Did the agent use the block inserter (the '+' button) to add their custom reusable blocks into the post content?

Respond in JSON format:
{
    "created_patterns": true/false,
    "edited_post": true/false,
    "inserted_blocks_via_ui": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "Briefly describe the agent's workflow seen in the screenshots"
}
"""

def verify_create_reusable_patterns(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract metadata expectations
    metadata = task_info.get('metadata', {})
    expected_blocks_meta = metadata.get('expected_blocks', [])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start_ts = result.get('task_start_ts', 0)
    blocks_data = result.get('blocks', [])
    article_data = result.get('article', {})

    # Helper to decode base64 robustly
    def decode_b64(b64_str):
        if not b64_str:
            return ""
        try:
            # Remove any whitespace that might have crept in
            clean_b64 = ''.join(b64_str.split())
            return base64.b64decode(clean_b64).decode('utf-8', errors='ignore').lower()
        except Exception as e:
            logger.warning(f"Base64 decode error: {e}")
            return ""

    # 1. Check Blocks (60 points total)
    valid_blocks_found = 0
    created_block_ids = []

    for expected in expected_blocks_meta:
        target_name = expected['name'].lower()
        keywords = expected['keywords']
        
        block_found = False
        content_correct = False
        
        for b in blocks_data:
            b_title = b.get('title', '').lower()
            b_ts = b.get('created_ts', 0)
            
            # Anti-gaming: Ensure it was created during the task
            # Provide a 60-second leniency window for clock skew
            if b_ts < (task_start_ts - 60):
                continue
                
            # Check for title match (partial or full)
            if target_name in b_title or b_title in target_name:
                block_found = True
                b_content = decode_b64(b.get('content_b64', ''))
                
                # Check for keywords in content
                if all(kw.lower() in b_content for kw in keywords):
                    content_correct = True
                    created_block_ids.append(b.get('id'))
                    break

        if block_found:
            score += 10
            feedback_parts.append(f"Found block: '{expected['name']}'")
            if content_correct:
                score += 10
                valid_blocks_found += 1
                feedback_parts.append(f"Content correct for '{expected['name']}'")
            else:
                feedback_parts.append(f"Content missing keywords for '{expected['name']}'")
        else:
            feedback_parts.append(f"Missing block: '{expected['name']}'")

    # 2. Check Article (20 points total)
    if article_data.get('found', False):
        art_ts = article_data.get('created_ts', 0)
        
        # Anti-gaming timestamp check
        if art_ts >= (task_start_ts - 60):
            score += 10
            feedback_parts.append("Article post published")
            
            art_content = decode_b64(article_data.get('content_b64', ''))
            
            # Look for block references: <!-- wp:block {"ref":ID} /-->
            # Note: We must check if the agent referenced the *newly created* blocks
            refs_found = 0
            for b_id in created_block_ids:
                if b_id and f'"ref":{b_id}' in art_content:
                    refs_found += 1
                elif b_id and f'"ref":"{b_id}"' in art_content:
                    refs_found += 1
            
            if refs_found >= 2:
                score += 10
                feedback_parts.append(f"Article uses {refs_found} reusable block references via WP UI")
            else:
                # Partial credit: Did they just paste the raw text instead of inserting the block properly?
                text_matches = 0
                for expected in expected_blocks_meta:
                    if all(kw.lower() in art_content for kw in expected['keywords']):
                        text_matches += 1
                
                if text_matches >= 2:
                    score += 5
                    feedback_parts.append("Article contains pattern text, but blocks not inserted via wp:block refs (Partial credit)")
                else:
                    feedback_parts.append("Article does not contain required block patterns")
        else:
            feedback_parts.append("Article found but was created before task started")
    else:
        feedback_parts.append("Article not found or not published")

    # 3. VLM Trajectory Verification (20 points)
    # Check if we have the VLM available
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # Import the framework's trajectory sampler
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=6)
            
            vlm_result = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
            
            if vlm_result:
                vlm_score = 0
                if vlm_result.get("created_patterns", False):
                    vlm_score += 10
                if vlm_result.get("edited_post", False) and vlm_result.get("inserted_blocks_via_ui", False):
                    vlm_score += 10
                
                score += vlm_score
                feedback_parts.append(f"VLM Verification (+{vlm_score} pts)")
            else:
                feedback_parts.append("VLM query failed or returned no data")
        except Exception as e:
            logger.error(f"Failed to process VLM verification: {e}")
            feedback_parts.append("VLM framework execution failed")
    else:
        # If VLM is not provided, gracefully award points or skip
        feedback_parts.append("VLM not available, skipping visual workflow verification")
        # Scale score up to account for missing VLM (80 max -> 100 max equivalent)
        score = int(score * 1.25)

    # 4. Final Assessment
    passed = False
    if score >= 60 and valid_blocks_found >= 2 and article_data.get('found', False):
        passed = True
        
    # Cap score at 100
    score = min(100, score)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "valid_blocks_found": valid_blocks_found,
            "article_found": article_data.get('found', False)
        }
    }