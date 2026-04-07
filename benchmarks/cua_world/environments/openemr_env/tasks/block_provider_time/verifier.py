#!/usr/bin/env python3
"""
Verifier for Block Provider Time task in OpenEMR

Verifies that a calendar block/event was created for the provider with:
- Correct provider (Administrator, id=1)
- Correct date (3 business days from task execution)
- Correct time (around 14:00-15:30)
- No patient linked (blocked time, not appointment)
- Appropriate description/title

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
import re
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_block_provider_time(traj, env_info, task_info):
    """
    Verify that a provider schedule block was correctly created.

    Scoring (100 points total):
    - Event created (new event exists): 25 points
    - Correct provider (pc_aid = 1): 20 points
    - Correct date (3 business days ahead): 20 points
    - Correct time window (13:00-15:30): 15 points
    - No patient linked (pc_pid = 0): 10 points
    - Description present with keywords: 10 points

    Passing threshold: 70 points with event_created + correct_provider + correct_date
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_provider_id = metadata.get('provider_id', 1)
    expected_start_time = metadata.get('target_start_time', '14:00')
    business_days_ahead = metadata.get('business_days_ahead', 3)
    description_keywords = metadata.get('expected_description_keywords', 
        ['compliance', 'training', 'meeting', 'block', 'unavailable'])

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/block_provider_time_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "event_created": False,
            "correct_provider": False,
            "correct_date": False,
            "correct_time": False,
            "no_patient": False,
            "description_present": False
        }

        # Extract data from result
        provider_id = result.get('provider_id', 0)
        target_date = result.get('target_date', '')
        initial_count = result.get('initial_event_count', 0)
        current_count = result.get('current_event_count', 0)
        event_found = result.get('event_found', False)
        event = result.get('event', {})
        validation = result.get('validation', {})

        logger.info(f"Result data: provider={provider_id}, target_date={target_date}")
        logger.info(f"Event counts: initial={initial_count}, current={current_count}")
        logger.info(f"Event found: {event_found}")
        logger.info(f"Event details: {event}")

        # CRITERION 1: Event Created (25 points)
        # Must have more events now than before task started
        new_event_created = current_count > initial_count and event_found
        
        if new_event_created:
            score += 25
            subscores["event_created"] = True
            feedback_parts.append(f"✅ New calendar event created (count: {initial_count} → {current_count})")
        else:
            feedback_parts.append(f"❌ No new event created (count: {initial_count} → {current_count})")
            # If no event created, we can't verify much else
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Correct Provider (20 points)
        event_provider_id = event.get('provider_id', '')
        try:
            event_provider_id_int = int(event_provider_id) if event_provider_id else 0
        except ValueError:
            event_provider_id_int = 0

        if event_provider_id_int == expected_provider_id:
            score += 20
            subscores["correct_provider"] = True
            feedback_parts.append(f"✅ Correct provider (id={expected_provider_id})")
        else:
            feedback_parts.append(f"❌ Wrong provider (expected id={expected_provider_id}, got {event_provider_id})")

        # CRITERION 3: Correct Date (20 points)
        event_date = event.get('date', '')
        
        if event_date and target_date:
            if event_date == target_date:
                score += 20
                subscores["correct_date"] = True
                feedback_parts.append(f"✅ Correct date ({target_date})")
            else:
                # Check if date is close (within 1-2 days tolerance for weekend calculation differences)
                try:
                    event_date_obj = datetime.strptime(event_date, '%Y-%m-%d').date()
                    target_date_obj = datetime.strptime(target_date, '%Y-%m-%d').date()
                    date_diff = abs((event_date_obj - target_date_obj).days)
                    
                    if date_diff <= 2:
                        # Partial credit for close date
                        score += 10
                        feedback_parts.append(f"⚠️ Date close but not exact (expected {target_date}, got {event_date}, diff={date_diff} days)")
                    else:
                        feedback_parts.append(f"❌ Wrong date (expected {target_date}, got {event_date})")
                except ValueError:
                    feedback_parts.append(f"❌ Invalid date format ({event_date})")
        else:
            feedback_parts.append("❌ Date not found or target date missing")

        # CRITERION 4: Correct Time Window (15 points)
        event_start_time = event.get('start_time', '')
        
        if event_start_time:
            try:
                # Parse time (formats: HH:MM:SS or HH:MM)
                time_parts = event_start_time.split(':')
                start_hour = int(time_parts[0])
                start_minute = int(time_parts[1]) if len(time_parts) > 1 else 0
                
                # Expected: around 14:00 (2 PM)
                # Accept 13:00 - 15:00 as reasonable range
                if 13 <= start_hour <= 15:
                    score += 15
                    subscores["correct_time"] = True
                    feedback_parts.append(f"✅ Correct time window ({event_start_time})")
                elif 12 <= start_hour <= 16:
                    # Partial credit for close time
                    score += 7
                    feedback_parts.append(f"⚠️ Time close but not exact (expected ~14:00, got {event_start_time})")
                else:
                    feedback_parts.append(f"❌ Wrong time (expected ~14:00, got {event_start_time})")
            except (ValueError, IndexError):
                feedback_parts.append(f"❌ Invalid time format ({event_start_time})")
        else:
            feedback_parts.append("❌ Start time not found")

        # CRITERION 5: No Patient Linked (10 points)
        event_patient_id = event.get('patient_id', '')
        
        # Blocked time should have no patient (pid = 0 or empty)
        try:
            patient_id_int = int(event_patient_id) if event_patient_id else 0
        except ValueError:
            patient_id_int = 0
            
        if patient_id_int == 0 or event_patient_id == '' or event_patient_id is None:
            score += 10
            subscores["no_patient"] = True
            feedback_parts.append("✅ No patient linked (blocked time)")
        else:
            feedback_parts.append(f"⚠️ Patient linked (pid={event_patient_id}) - this is an appointment, not blocked time")

        # CRITERION 6: Description Present (10 points)
        event_title = event.get('title', '') or ''
        event_description = event.get('description', '') or ''
        combined_text = (event_title + ' ' + event_description).lower()

        # Check for any relevant keywords
        keywords_found = []
        for keyword in description_keywords:
            if keyword.lower() in combined_text:
                keywords_found.append(keyword)

        if keywords_found:
            score += 10
            subscores["description_present"] = True
            feedback_parts.append(f"✅ Relevant description (found: {', '.join(keywords_found)})")
        elif event_title or event_description:
            # Partial credit if any description provided
            score += 5
            feedback_parts.append(f"⚠️ Description provided but no keywords found: '{event_title}' / '{event_description}'")
        else:
            feedback_parts.append("❌ No description provided")

        # Calculate final result
        # Must have: event created + correct provider + correct/close date to pass
        key_criteria = (
            subscores["event_created"] and 
            subscores["correct_provider"] and 
            (subscores["correct_date"] or score >= 10)  # At least partial date credit
        )
        
        passed = score >= 70 and key_criteria

        # VLM verification as secondary check (if available)
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            try:
                # Try to get trajectory frames
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(traj, n=3)
                final = get_final_screenshot(traj)
                
                if frames or final:
                    vlm_prompt = """You are verifying if an agent blocked time on a calendar in OpenEMR.

Look at these screenshots and determine:
1. Is this the OpenEMR Calendar view?
2. Did the agent create/add a new calendar entry?
3. Does the entry appear to be a blocked time (not a patient appointment)?
4. Is there any indication of "Compliance Training" or similar meeting text?

Respond in JSON:
{
    "is_calendar_view": true/false,
    "event_created": true/false,
    "appears_blocked_time": true/false,
    "training_text_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
                    images = (frames or []) + ([final] if final else [])
                    if images:
                        vlm_result = query_vlm(prompt=vlm_prompt, images=images[:4])
                        
                        if vlm_result.get('success'):
                            parsed = vlm_result.get('parsed', {})
                            vlm_confidence = parsed.get('confidence', 'low')
                            vlm_event_created = parsed.get('event_created', False)
                            vlm_reasoning = parsed.get('reasoning', '')
                            
                            if vlm_confidence == 'high' and vlm_event_created:
                                feedback_parts.append(f"✅ VLM confirms event creation: {vlm_reasoning}")
                            elif vlm_confidence in ['medium', 'high']:
                                feedback_parts.append(f"ℹ️ VLM observation: {vlm_reasoning}")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")

        return {
            "passed": passed,
            "score": min(score, 100),  # Cap at 100
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "event": event,
                "target_date": target_date,
                "expected_provider_id": expected_provider_id
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
            "subscores": {
                "event_created": False,
                "correct_provider": False,
                "correct_date": False,
                "correct_time": False,
                "no_patient": False,
                "description_present": False
            }
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}",
            "subscores": {
                "event_created": False,
                "correct_provider": False,
                "correct_date": False,
                "correct_time": False,
                "no_patient": False,
                "description_present": False
            }
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {
                "event_created": False,
                "correct_provider": False,
                "correct_date": False,
                "correct_time": False,
                "no_patient": False,
                "description_present": False
            }
        }