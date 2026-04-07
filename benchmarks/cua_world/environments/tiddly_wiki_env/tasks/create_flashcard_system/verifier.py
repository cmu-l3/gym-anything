#!/usr/bin/env python3
"""
Verifier for Create Spaced Repetition Flashcard System task.

Verification Strategy:
- Programmatic checks for card existence, custom fields, tags, and widget structure.
- Programmatic checks for the deck overview filtering properties.
- Hybrid checks utilizing VLM Trajectory to confirm proper interaction in the UI.

Scores total exactly 100 points.
Pass threshold: 60 points with key criteria met.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def fuzzy_match(expected, actual):
    """Checks if the actual text contains a substantial portion of the expected text."""
    if not expected or not actual:
        return False
    
    def clean(s):
        # Remove punctuation and convert to lowercase words
        return set(re.sub(r'[^\w\s]', '', s.lower()).split())
    
    exp_words = clean(expected)
    act_words = clean(actual)
    
    if not exp_words:
        return True
    
    overlap = len(exp_words.intersection(act_words))
    # Passing if at least 40% of the key words overlap (to account for manual typing)
    return overlap / len(exp_words) >= 0.4


VLM_VERIFICATION_PROMPT = """You are analyzing screenshots from an agent creating a TiddlyWiki flashcard system.
Look at these chronological frames sampled from the agent's work.

1. FLASHCARD_UI_SEEN: Does the agent ever interact with or show a flashcard UI? (e.g., configuring custom fields like 'question', 'answer', 'difficulty', or interacting with a 'Show Answer' button)
2. DECK_OVERVIEW_SEEN: Does the agent view or edit the 'Pharmacology Deck' overview page that lists flashcards?

Respond in JSON format:
{
    "flashcard_ui_seen": true/false,
    "deck_overview_seen": true/false,
    "confidence": "high"/"medium"/"low",
    "reasoning": "Brief explanation of what is visible across the frames"
}
"""


def verify_flashcard_system(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cards = metadata.get('cards', [])

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
    
    # ---------------------------------------------------------
    # Anti-Gaming Check
    # ---------------------------------------------------------
    new_tiddlers = result.get('current_count', 0) - result.get('initial_count', 0)
    if new_tiddlers <= 0:
        return {"passed": False, "score": 0, "feedback": "No new tiddlers created."}

    gui_save_detected = result.get('gui_save_detected', False)

    # ---------------------------------------------------------
    # Criterion 1: Individual Flashcards (50 points, 10 per card)
    # ---------------------------------------------------------
    cards_data = result.get('cards', [])
    valid_cards_count = 0
    
    for expected, actual in zip(expected_cards, cards_data):
        card_score = 0
        title = expected['title']
        
        if not actual.get('exists', False):
            feedback_parts.append(f"Card '{title}' missing.")
            continue
            
        card_score += 2  # Exists
        
        # Tags check
        tags = actual.get('tags', '').lower()
        if 'flashcard' in tags and 'pharmacology' in tags:
            card_score += 2
            
        # Fields check
        if fuzzy_match(expected['question'], actual.get('question', '')):
            card_score += 1
        if fuzzy_match(expected['answer'], actual.get('answer', '')):
            card_score += 1
        if actual.get('difficulty', '').lower() == expected['difficulty'].lower():
            card_score += 1
            
        # Widget logic check (reveal + transclusions/text)
        body = actual.get('body', '').lower()
        has_reveal = '<$reveal' in body or '$reveal' in body
        has_button = '<$button' in body or '$button' in body
        
        if has_reveal:
            card_score += 2
        if has_button:
            card_score += 1
            
        score += card_score
        if card_score >= 6:
            valid_cards_count += 1
            
    feedback_parts.append(f"{valid_cards_count}/5 Flashcards configured")

    # ---------------------------------------------------------
    # Criterion 2: Deck Overview Tiddler (20 points)
    # ---------------------------------------------------------
    deck = result.get('deck', {})
    deck_score = 0
    
    if deck.get('exists', False):
        deck_score += 5
        
        # Tags Check
        if 'deck' in deck.get('tags', '').lower():
            deck_score += 2
            
        body = deck.get('body', '').lower()
        # Has list widget filtering for flashcards
        if ('<$list' in body or '$list' in body) and ('flashcard' in body or 'pharmacology' in body):
            deck_score += 8
            
        # Shows count
        if '<$count' in body or '$count' in body:
            deck_score += 5
            
    score += deck_score
    if deck_score > 0:
        feedback_parts.append(f"Deck scored {deck_score}/20")
    else:
        feedback_parts.append("Deck Overview missing or invalid")

    # ---------------------------------------------------------
    # Criterion 3: GUI interaction & Workflow VLM (30 points)
    # ---------------------------------------------------------
    process_score = 0
    if gui_save_detected:
        process_score += 10
        feedback_parts.append("GUI Save Detected")
    
    # Run VLM trajectory verification
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        
        if frames:
            try:
                vlm_res = query_vlm(images=frames, prompt=VLM_VERIFICATION_PROMPT)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('flashcard_ui_seen'):
                        process_score += 10
                    if parsed.get('deck_overview_seen'):
                        process_score += 10
            except Exception as e:
                logger.warning(f"VLM failure: {e}")
                # Fallback credit if VLM fails but logic indicates success
                if gui_save_detected and valid_cards_count >= 3:
                    process_score += 20
    else:
        # Fallback if VLM isn't loaded
        if gui_save_detected and valid_cards_count >= 3:
            process_score += 20

    score += process_score

    # ---------------------------------------------------------
    # Finalize
    # ---------------------------------------------------------
    # Make sure we don't accidentally exceed 100
    score = min(score, 100)
    key_criteria_met = valid_cards_count >= 3 and deck.get('exists', False)
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }