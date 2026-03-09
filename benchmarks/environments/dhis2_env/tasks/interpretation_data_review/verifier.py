#!/usr/bin/env python3
"""
Verifier for interpretation_data_review task.

Scoring (100 points total):
- At least 1 interpretation created after task start (30 pts) [MANDATORY]
- First interpretation is substantive (>= 100 chars) (15 pts)
- At least 2 interpretations created (25 pts)
- Second interpretation is substantive (>= 100 chars) (15 pts)
- Second interpretation is on a DIFFERENT visualization than the first (checked implicitly in count if distinct, explicitly logic below)
- Interpretations reference health keywords (10 pts)
- User logged in/API accessible (5 pts)

Pass threshold: 60 points
Mandatory: At least 1 interpretation created
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_interpretation_data_review(traj, env_info, task_info):
    """Verify interpretations were created on different visualizations."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/interpretation_review_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        subscores = {}
        
        # Access metadata for keywords
        metadata = task_info.get('metadata', {})
        health_keywords = metadata.get('health_keywords', ['coverage', 'cases', 'malaria'])

        # Data from export script
        data = result.get('result_data', {})
        new_interps = data.get('interpretations', [])
        count = len(new_interps)

        # 1. Login/Access check (implied by script running successfully)
        score += 5
        subscores["login"] = True

        # 2. Mandatory: At least 1 interpretation
        if count < 1:
            return {
                "passed": False,
                "score": 5,
                "feedback": "No new interpretations found. You must create an interpretation on a dashboard item.",
                "subscores": subscores
            }
        
        score += 30
        subscores["created_one"] = True
        feedback_parts.append(f"Created {count} interpretation(s) (+30)")

        # Analyze interpretations
        # We need to find distinct visualizations
        # Group by viz_id
        viz_map = {}
        for interp in new_interps:
            viz_id = interp.get('viz_id', 'unknown')
            if viz_id not in viz_map:
                viz_map[viz_id] = []
            viz_map[viz_id].append(interp)
        
        distinct_viz_count = len([v for v in viz_map.keys() if v and v != 'unknown'])
        
        # Check text quality of best interpretation
        # Sort by length to give benefit of the doubt
        all_texts = [i.get('text', '') for i in new_interps]
        all_texts.sort(key=len, reverse=True)
        
        best_text_len = len(all_texts[0]) if all_texts else 0
        
        if best_text_len >= 100:
            score += 15
            subscores["first_substantive"] = True
            feedback_parts.append("Primary interpretation is substantive (>=100 chars) (+15)")
        else:
            subscores["first_substantive"] = False
            feedback_parts.append(f"Interpretation too short ({best_text_len} chars, need 100)")

        # 3. Two interpretations on different visualizations
        if distinct_viz_count >= 2:
            score += 25
            subscores["created_two_distinct"] = True
            feedback_parts.append(f"Interpretations found on {distinct_viz_count} different visualizations (+25)")
            
            # Check quality of second interpretation (find the longest text from a DIFFERENT viz group)
            # Identify the viz_id of the longest text
            primary_viz_id = None
            longest_len = -1
            
            for vid, interps in viz_map.items():
                for i in interps:
                    if i['length'] > longest_len:
                        longest_len = i['length']
                        primary_viz_id = vid
            
            # Now find best text in OTHER viz groups
            second_best_len = 0
            for vid, interps in viz_map.items():
                if vid != primary_viz_id:
                    for i in interps:
                        if i['length'] > second_best_len:
                            second_best_len = i['length']
            
            if second_best_len >= 100:
                score += 15
                subscores["second_substantive"] = True
                feedback_parts.append("Second interpretation is substantive (+15)")
            else:
                subscores["second_substantive"] = False
                feedback_parts.append(f"Second interpretation too short ({second_best_len} chars)")
                
        elif count >= 2:
            feedback_parts.append("Multiple interpretations created, but on the SAME visualization (need different ones)")
        else:
            feedback_parts.append("Only one visualization commented on")

        # 4. Keyword check
        combined_text = " ".join(all_texts).lower()
        found_keywords = [k for k in health_keywords if k.lower() in combined_text]
        
        if found_keywords:
            score += 10
            subscores["keywords"] = True
            feedback_parts.append(f"Health keywords used: {', '.join(found_keywords[:3])} (+10)")
        else:
            subscores["keywords"] = False
            feedback_parts.append("No health domain keywords found in text")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}