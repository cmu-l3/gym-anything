#!/usr/bin/env python3
"""
Verifier for Compare Voice Takes task
"""

import sys
import os
import logging
import tempfile
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compare_voice_takes(traj, env_info, task_info):
    """
    Verify compare voice takes task completion.
    
    Checks:
    1. Selection file exists at correct path
    2. File contains meaningful content (>100 bytes)
    3. File correctly identifies take 3 as best/selected take
    4. File mentions/evaluates all 4 takes
    5. File contains quality reasoning (mentions quality factors)
    
    Bonus:
    - Identifies the flaw in take 2 (mouth click/artifact)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Copy selection document from container
    temp_selection = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        # Criterion 1: File exists and is accessible
        try:
            copy_from_env("/tmp/vlc_voice_takes_selection.txt", temp_selection.name)
        except Exception as e:
            logger.error(f"Error copying selection document: {e}", exc_info=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Selection document not found or inaccessible: {str(e)}"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Selection document exists")
        
        # Read the selection document content
        with open(temp_selection.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        content_lower = content.lower()
        
        # Check if file contains the "MISSING" indicator
        if "MISSING" in content and "was not created" in content:
            os.unlink(temp_selection.name)
            return {
                "passed": False,
                "score": 20,
                "feedback": "Selection document was not created by agent"
            }
        
        # Criterion 2: Meaningful content (>100 bytes, not trivial)
        file_size = len(content)
        if file_size > 100:
            criteria_met += 1
            feedback_parts.append(f"✅ Meaningful content ({file_size} bytes)")
        else:
            feedback_parts.append(f"❌ Insufficient content ({file_size} bytes, need >100)")
        
        # Criterion 3: Identifies take 3 as best/selected
        # Look for patterns like "take 3", "take3", "third take", paired with "best", "selected", "chosen", etc.
        take3_patterns = [
            r'\btake[\s\-_]*3\b',
            r'\b3rd\s+take\b',
            r'\bthird\s+take\b',
            r'\btake[\s\-_]*three\b'
        ]
        
        selection_keywords = [
            r'\bbest\b',
            r'\bselect(ed)?\b',
            r'\bchos(e|en)\b',
            r'\buse\b',
            r'\bfinal\b',
            r'\bprefer(red)?\b',
            r'\brecommend\b',
            r'\bwinner\b'
        ]
        
        # Check if take 3 is mentioned near selection keywords
        take3_found = False
        take3_selected = False
        
        for take3_pattern in take3_patterns:
            if re.search(take3_pattern, content_lower):
                take3_found = True
                # Check if selection keywords appear near take 3 mention
                matches = re.finditer(take3_pattern, content_lower)
                for match in matches:
                    # Get context around the match (50 chars before and after)
                    start = max(0, match.start() - 50)
                    end = min(len(content_lower), match.end() + 50)
                    context = content_lower[start:end]
                    
                    # Check if any selection keyword is in context
                    for keyword_pattern in selection_keywords:
                        if re.search(keyword_pattern, context):
                            take3_selected = True
                            break
                    
                    if take3_selected:
                        break
                
                if take3_selected:
                    break
        
        if take3_selected:
            criteria_met += 1
            feedback_parts.append("✅ Correctly identifies take 3 as best")
        elif take3_found:
            criteria_met += 0.5  # Partial credit
            feedback_parts.append("⚠️ Mentions take 3 but selection unclear")
        else:
            feedback_parts.append("❌ Does not identify take 3 as best")
        
        # Criterion 4: Mentions all 4 takes
        takes_mentioned = []
        for i in range(1, 5):
            patterns = [
                rf'\btake[\s\-_]*{i}\b',
                rf'\b{i}(?:st|nd|rd|th)\s+take\b'
            ]
            for pattern in patterns:
                if re.search(pattern, content_lower):
                    takes_mentioned.append(i)
                    break
        
        if len(takes_mentioned) >= 4:
            criteria_met += 1
            feedback_parts.append(f"✅ Evaluates all 4 takes")
        elif len(takes_mentioned) >= 3:
            criteria_met += 0.5  # Partial credit
            feedback_parts.append(f"⚠️ Mentions {len(takes_mentioned)} takes (need 4)")
        else:
            feedback_parts.append(f"❌ Only mentions {len(takes_mentioned)} takes")
        
        # Criterion 5: Quality reasoning (mentions at least 2 quality factors)
        quality_keywords = {
            'volume': [r'\bvolume\b', r'\bloud(ness)?\b', r'\bquiet\b', r'\blevel\b', r'\bsoft\b'],
            'noise': [r'\bclick\b', r'\bpop\b', r'\bnoise\b', r'\bartifact\b', r'\bmouth\b', r'\bsmack\b', r'\bglitch\b', r'\bdistortion\b'],
            'pacing': [r'\bfast\b', r'\bslow\b', r'\brush(ed)?\b', r'\bpac(e|ing)\b', r'\btiming\b', r'\btempo\b', r'\bspeed\b'],
            'clarity': [r'\bclear\b', r'\bclarity\b', r'\bclean\b', r'\bquality\b', r'\bcrisp\b', r'\bmuddy\b', r'\bmuffled\b']
        }
        
        quality_factors_found = []
        for category, patterns in quality_keywords.items():
            for pattern in patterns:
                if re.search(pattern, content_lower):
                    quality_factors_found.append(category)
                    break
        
        # Remove duplicates
        quality_factors_found = list(set(quality_factors_found))
        
        if len(quality_factors_found) >= 2:
            criteria_met += 1
            feedback_parts.append(f"✅ Quality reasoning present ({', '.join(quality_factors_found)})")
        elif len(quality_factors_found) == 1:
            criteria_met += 0.5  # Partial credit
            feedback_parts.append(f"⚠️ Limited reasoning (only {quality_factors_found[0]})")
        else:
            feedback_parts.append("❌ No quality reasoning found")
        
        # Bonus: Identifies the flaw in take 2 (mouth click/artifact)
        bonus_achieved = False
        take2_flaw_keywords = [
            r'\btake[\s\-_]*2.*(?:click|pop|artifact|mouth|smack)\b',
            r'\b(?:click|pop|artifact|mouth|smack).*take[\s\-_]*2\b',
            r'\btake[\s\-_]*2.*\bat\s*(?:3|three)\s*(?:second|sec|s)\b'
        ]
        
        for pattern in take2_flaw_keywords:
            if re.search(pattern, content_lower, re.DOTALL):
                bonus_achieved = True
                break
        
        if bonus_achieved:
            feedback_parts.append("⭐ BONUS: Identifies take 2 flaw (artifact)")
            criteria_met += 0.5  # Bonus points
        
        # Clean up temp file
        os.unlink(temp_selection.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_selection.name):
            os.unlink(temp_selection.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading selection document: {str(e)}"
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_voice_takes_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    # Max possible is 5.5 (5 criteria + 0.5 bonus)
    score = int((min(criteria_met, 5.5) / 5) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria_met": criteria_met,
        "total_criteria": total_criteria,
        "bonus_achieved": bonus_achieved
    }