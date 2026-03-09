#!/usr/bin/env python3
"""
Verifier for generate_parameterized_fixtures@1
Checks that generated user fixtures meet all diversity and correctness requirements
"""

import sys
import os
import json
import re
import logging
import tempfile
import shutil
from datetime import datetime
from collections import Counter
from typing import Dict, List, Tuple, Any

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fixture_generation(traj, env_info, task_info):
    """
    Verify the generated user fixtures meet all requirements.
    
    Scoring breakdown (total 100 points):
    - User count (10 points)
    - User IDs uniqueness and sequence (10 points)
    - Email uniqueness and format (15 points)
    - Name diversity (15 points)
    - Age constraints (10 points)
    - Membership tier distribution (15 points)
    - City variety (10 points)
    - Date spread (10 points)
    - Account balance range (5 points)
    
    Pass threshold: 85/100
    
    Returns:
        dict with keys: passed (bool), score (int), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    temp_dir = tempfile.mkdtemp(prefix='fixture_verify_')
    
    try:
        # Copy the generated fixture file
        container_path = "/tmp/fixture_task_output/users_fixture.json"
        local_path = os.path.join(temp_dir, "users_fixture.json")
        
        try:
            copy_from_env(container_path, local_path)
        except Exception as e:
            logger.error(f"Failed to copy fixture file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ users_fixture.json not found or could not be copied: {str(e)}"
            }
        
        # Check file exists and has content
        if not os.path.exists(local_path) or os.path.getsize(local_path) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ users_fixture.json not found or is empty"
            }
        
        # Load and parse JSON
        try:
            with open(local_path, 'r', encoding='utf-8') as f:
                users = json.load(f)
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Invalid JSON format: {str(e)}"
            }
        
        # Verify it's a list
        if not isinstance(users, list):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ JSON must be an array of user objects"
            }
        
        feedback_parts = []
        score_components = {}
        
        # 1. Check count (10 points)
        user_count = len(users)
        if user_count == 20:
            score_components['count'] = 10
        elif 18 <= user_count <= 22:
            score_components['count'] = 7
            feedback_parts.append(f"⚠️ Expected 20 users, got {user_count}")
        else:
            score_components['count'] = 0
            feedback_parts.append(f"❌ Wrong user count: {user_count} (expected 20)")
        
        # 2. Check user IDs (10 points)
        user_ids = [u.get('userId') for u in users if isinstance(u, dict)]
        expected_ids = set(range(1001, 1021))
        actual_ids = set(user_ids)
        
        if actual_ids == expected_ids and len(user_ids) == len(actual_ids):
            score_components['user_ids'] = 10
        elif len(user_ids) == len(actual_ids):  # No duplicates but wrong sequence
            score_components['user_ids'] = 5
            feedback_parts.append(f"⚠️ User IDs not sequential 1001-1020")
        else:
            score_components['user_ids'] = 0
            duplicates = len(user_ids) - len(actual_ids)
            feedback_parts.append(f"❌ User ID issues: {duplicates} duplicates or missing IDs")
        
        # 3. Check unique emails (15 points)
        emails = [
            u.get('profile', {}).get('email') 
            for u in users 
            if isinstance(u, dict) and isinstance(u.get('profile'), dict)
        ]
        email_pattern = re.compile(r'^[a-z]+\.[a-z]+@example\.com$', re.IGNORECASE)
        
        valid_emails = sum(1 for e in emails if e and email_pattern.match(e))
        unique_emails = len(set(e for e in emails if e))
        
        if unique_emails == user_count and valid_emails == user_count:
            score_components['emails'] = 15
        elif unique_emails >= user_count - 2 and valid_emails >= user_count - 2:
            score_components['emails'] = 10
            feedback_parts.append(
                f"⚠️ Email issues: {user_count-unique_emails} duplicates, "
                f"{user_count-valid_emails} invalid format"
            )
        else:
            score_components['emails'] = 0
            feedback_parts.append(
                f"❌ Email problems: {unique_emails}/{user_count} unique, "
                f"{valid_emails}/{user_count} valid format"
            )
        
        # 4. Check name diversity (15 points)
        first_names = [
            u.get('profile', {}).get('firstName') 
            for u in users 
            if isinstance(u, dict) and isinstance(u.get('profile'), dict)
        ]
        first_names = [n for n in first_names if n]
        unique_first_names = len(set(first_names))
        
        if unique_first_names >= 15:
            score_components['name_diversity'] = 15
        elif unique_first_names >= 12:
            score_components['name_diversity'] = 10
            feedback_parts.append(
                f"⚠️ Name diversity: {unique_first_names}/20 unique first names (need 15+)"
            )
        elif unique_first_names >= 8:
            score_components['name_diversity'] = 5
            feedback_parts.append(
                f"❌ Low name diversity: {unique_first_names} unique first names (need 15+)"
            )
        else:
            score_components['name_diversity'] = 0
            feedback_parts.append(
                f"❌ Very low name diversity: only {unique_first_names} unique first names"
            )
        
        # 5. Check age range (10 points)
        ages = [
            u.get('profile', {}).get('age') 
            for u in users 
            if isinstance(u, dict) and isinstance(u.get('profile'), dict)
        ]
        valid_ages = [a for a in ages if isinstance(a, (int, float)) and 18 <= a <= 65]
        
        if len(valid_ages) == user_count:
            score_components['ages'] = 10
        elif len(valid_ages) >= user_count - 2:
            score_components['ages'] = 7
            feedback_parts.append(f"⚠️ {user_count-len(valid_ages)} ages out of range 18-65")
        else:
            score_components['ages'] = 0
            feedback_parts.append(
                f"❌ Many invalid ages: {len(valid_ages)}/{user_count} in valid range"
            )
        
        # 6. Check membership distribution (15 points)
        tiers = [
            u.get('membership', {}).get('tier') 
            for u in users 
            if isinstance(u, dict) and isinstance(u.get('membership'), dict)
        ]
        tier_counts = Counter(tiers)
        
        bronze = tier_counts.get('bronze', 0)
        silver = tier_counts.get('silver', 0)
        gold = tier_counts.get('gold', 0)
        
        # Target: bronze=8, silver=7, gold=5 (±1 tolerance)
        distribution_score = 0
        bronze_ok = 7 <= bronze <= 9
        silver_ok = 6 <= silver <= 8
        gold_ok = 4 <= gold <= 6
        
        if bronze_ok:
            distribution_score += 5
        if silver_ok:
            distribution_score += 5
        if gold_ok:
            distribution_score += 5
        
        score_components['membership'] = distribution_score
        
        if distribution_score < 15:
            feedback_parts.append(
                f"⚠️ Membership distribution off: bronze={bronze} (target:8±1), "
                f"silver={silver} (target:7±1), gold={gold} (target:5±1)"
            )
        
        # 7. Check city variety (10 points)
        cities = [
            u.get('location', {}).get('city') 
            for u in users 
            if isinstance(u, dict) and isinstance(u.get('location'), dict)
        ]
        valid_cities = {"New York", "London", "Tokyo", "Berlin", "Toronto", "Sydney"}
        cities_used = set(c for c in cities if c in valid_cities)
        
        if len(cities_used) >= 4:
            score_components['cities'] = 10
        elif len(cities_used) >= 3:
            score_components['cities'] = 6
            feedback_parts.append(
                f"⚠️ City variety: {len(cities_used)} different cities (need 4+)"
            )
        else:
            score_components['cities'] = 0
            feedback_parts.append(
                f"❌ Low city variety: only {len(cities_used)} different cities"
            )
        
        # 8. Check date spread (10 points)
        dates = [
            u.get('membership', {}).get('registeredDate') 
            for u in users 
            if isinstance(u, dict) and isinstance(u.get('membership'), dict)
        ]
        
        unique_months = 0
        try:
            parsed_dates = []
            for d in dates:
                if d:
                    try:
                        parsed_dates.append(datetime.fromisoformat(str(d)))
                    except:
                        pass
            
            if parsed_dates:
                unique_months = len(set((d.year, d.month) for d in parsed_dates))
            
            if unique_months >= 6:
                score_components['dates'] = 10
            elif unique_months >= 4:
                score_components['dates'] = 6
                feedback_parts.append(
                    f"⚠️ Date spread: {unique_months} unique months (need 6+)"
                )
            elif unique_months >= 2:
                score_components['dates'] = 3
                feedback_parts.append(
                    f"❌ Low date diversity: {unique_months} unique months (need 6+)"
                )
            else:
                score_components['dates'] = 0
                feedback_parts.append(f"❌ Very low date diversity: {unique_months} unique months")
        except Exception as e:
            score_components['dates'] = 0
            feedback_parts.append(f"❌ Invalid date formats: {str(e)}")
        
        # 9. Check account balance range (5 points)
        balances = [u.get('accountBalance') for u in users if isinstance(u, dict)]
        valid_balances = [
            b for b in balances 
            if isinstance(b, (int, float)) and 0 <= b <= 500
        ]
        
        if len(valid_balances) == user_count:
            score_components['balances'] = 5
        elif len(valid_balances) >= user_count - 2:
            score_components['balances'] = 3
            feedback_parts.append(
                f"⚠️ {user_count-len(valid_balances)} balances out of $0-$500 range"
            )
        else:
            score_components['balances'] = 0
            feedback_parts.append(
                f"❌ Balance issues: {len(valid_balances)}/{user_count} in valid range $0-$500"
            )
        
        # Calculate total score
        total_score = sum(score_components.values())
        max_score = 100
        
        # Success if score >= 85%
        success = total_score >= 85
        
        if success:
            feedback = "✅ All requirements met! Fixtures generated successfully."
        else:
            feedback = " | ".join(feedback_parts) if feedback_parts else "Some requirements not met"
        
        result = {
            "passed": success,
            "score": total_score,
            "feedback": feedback,
            "metadata": {
                "score_breakdown": score_components,
                "total_score": total_score,
                "max_score": max_score,
                "user_count": user_count,
                "unique_first_names": unique_first_names,
                "unique_emails": unique_emails,
                "tier_distribution": {
                    "bronze": bronze,
                    "silver": silver,
                    "gold": gold
                },
                "unique_cities": len(cities_used),
                "unique_months": unique_months
            }
        }
        
        logger.info(f"Verification result: {result}")
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
