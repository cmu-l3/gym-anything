#!/usr/bin/env python3
"""
Verifier for Jam Session Chord Chart task

Verifies that a properly transposed chord chart was created for a jazz song,
transposing from G major to E♭ major with proper formatting and structure.
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_jam_session_chord_chart(traj, env_info, task_info):
    """
    Verify that a properly transposed chord chart was created.
    
    Checks:
    1. File exists and is valid DOCX (25%)
    2. Contains transposed chords in E♭ major (35%)
    3. Does NOT contain original G major chords as primary content (15%)
    4. Has structured layout - table or clear organization (15%)
    5. Contains song title, key indication, and metadata (10%)
    
    Pass threshold: 75%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/autumn_groove_chart.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_chord_')

    try:
        # Criterion 1: File exists and valid (25%)
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
        
        if not success or doc is None:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ File not found or invalid: {error}"
            }
        
        score = 0.25
        feedback_parts = ["✅ File exists and is valid DOCX"]
        
        # Extract text (lowercase for easier matching)
        text = get_document_text(doc).lower()
        
        # Remove common instruction phrases to avoid false positives
        text_no_instructions = text.replace("original progression", "")
        text_no_instructions = text_no_instructions.replace("reference", "")
        text_no_instructions = text_no_instructions.replace("you recorded this", "")
        
        # Criterion 5: Song metadata (10%)
        metadata_score = 0.0
        
        # Check for song title
        has_title = "autumn groove" in text
        if has_title:
            metadata_score += 0.04
            feedback_parts.append("✅ Song title 'Autumn Groove' present")
        else:
            feedback_parts.append("❌ Missing song title 'Autumn Groove'")
        
        # Check for key indication (E♭ Major)
        has_key_eb = (("eb" in text or "e♭" in text or "e-flat" in text) and "major" in text)
        if has_key_eb:
            metadata_score += 0.04
            feedback_parts.append("✅ Key (E♭ Major) indicated")
        else:
            feedback_parts.append("❌ Missing key indication (E♭ Major)")
        
        # Check for tempo marking
        has_tempo = any(word in text for word in ["120", "swing", "tempo", "medium"])
        if has_tempo:
            metadata_score += 0.02
            feedback_parts.append("✅ Tempo marking present")
        else:
            feedback_parts.append("⚠️ No tempo marking found (minor issue)")
        
        score += metadata_score
        
        # Criterion 2: Transposed chords present (35%)
        # Define E♭ major chords to look for
        eb_chord_patterns = {
            "ebmaj7": ("ebmaj7", "e♭maj7"),
            "cm7": ("cm7",),
            "fm7": ("fm7",),
            "bb7": ("bb7", "b♭7"),
            "abmaj7": ("abmaj7", "a♭maj7"),
            "gm7": ("gm7",),
            "c7": ("c7",),
            "abm7": ("abm7", "a♭m7")
        }
        
        # Count occurrences of each chord type
        chord_found = {}
        for chord_name, patterns in eb_chord_patterns.items():
            found = False
            for pattern in patterns:
                if pattern in text_no_instructions:
                    found = True
                    break
            chord_found[chord_name] = found
        
        # Count unique transposed chords found
        total_eb_chords_found = sum(chord_found.values())
        
        # Check for essential chords (must have these)
        has_ebmaj7 = chord_found["ebmaj7"]
        has_cm7 = chord_found["cm7"]
        has_fm7 = chord_found["fm7"]
        has_bb7 = chord_found["bb7"]
        has_abmaj7 = chord_found["abmaj7"]
        
        essential_chords_count = sum([has_ebmaj7, has_cm7, has_fm7, has_bb7, has_abmaj7])
        
        # Scoring based on transposition completeness
        if essential_chords_count >= 5 and total_eb_chords_found >= 5:
            # Perfect transposition
            score += 0.35
            feedback_parts.append(f"✅ Correct transposition to E♭ major ({total_eb_chords_found} chord types found)")
        elif essential_chords_count >= 4 and total_eb_chords_found >= 4:
            # Good transposition with minor gaps
            score += 0.28
            feedback_parts.append(f"✅ Good transposition ({total_eb_chords_found} chord types, minor gaps)")
        elif essential_chords_count >= 3 or total_eb_chords_found >= 3:
            # Partial transposition
            score += 0.20
            feedback_parts.append(f"⚠️ Partial transposition ({total_eb_chords_found} chord types, need 5+)")
        else:
            feedback_parts.append(f"❌ Missing transposed chords (only {total_eb_chords_found} found, need 5+)")
        
        # Criterion 3: NOT in original key (15%)
        # Check for untransposed G major chords as primary content
        # We need to be careful not to penalize mentions in reference/instructions
        
        # Look for G major chords in the main content (not in reference section)
        # Split text to try to identify main content vs instructions
        main_content_indicators = ["begin your chord chart", "=" * 10, "your task"]
        
        # Try to isolate main content (everything after instructions)
        main_content = text
        for indicator in main_content_indicators:
            if indicator in text:
                parts = text.split(indicator)
                if len(parts) > 1:
                    main_content = parts[-1]
                    break
        
        # Count G major chord occurrences in what we think is main content
        g_major_chords = ["gmaj7", "em7", "am7", "d7", "cmaj7", "bm7", "e7"]
        g_chord_count = 0
        
        for chord in g_major_chords:
            # Count occurrences, but weight less if it's also mentioned in full text
            # (could be in reference section)
            main_count = main_content.count(chord)
            full_count = text.count(chord)
            
            # If appears more in main content than total, it's likely primary
            if main_count > 0:
                g_chord_count += main_count
        
        # Also check for pipe-delimited progression patterns typical of the original
        has_original_pattern = "| gmaj7" in text or "gmaj7  |" in text or "| gmaj7 |" in text
        
        # Scoring: penalize if G major chords are prominent in main content
        if g_chord_count <= 3 and not has_original_pattern:
            # Good - minimal or no original key in main content
            score += 0.15
            feedback_parts.append("✅ Not using original G major progression")
        elif g_chord_count <= 6:
            # Some original chords present but may be acceptable
            score += 0.08
            feedback_parts.append("⚠️ Some original key chords present (should be fully transposed)")
        else:
            # Too many original chords - likely not transposed
            feedback_parts.append("❌ Still in original key (G major) - transposition incomplete")
        
        # Criterion 4: Structured layout (15%)
        table_count = count_tables(doc)
        
        # Check for structural markers
        has_structure_markers = any(marker in text for marker in [
            "[a]", "[b]", "section a", "section b", "intro", "bridge"
        ])
        
        # Check for table-like organization (pipes or cell structure)
        has_measure_structure = "|" in text or table_count > 0
        
        if table_count > 0:
            score += 0.10
            feedback_parts.append(f"✅ Table structure present ({table_count} table(s))")
        elif has_measure_structure:
            score += 0.05
            feedback_parts.append("⚠️ Measure structure present but no formal table")
        else:
            feedback_parts.append("❌ No table structure found")
        
        if has_structure_markers:
            score += 0.05
            feedback_parts.append("✅ Section labels present")
        else:
            feedback_parts.append("⚠️ No section labels found (e.g., [A], [B])")
        
        # Additional quality checks for feedback
        # Check if instructions were removed (good practice)
        instructions_removed = "instructions:" not in text or "delete these instructions" not in text
        if instructions_removed:
            feedback_parts.append("✅ Instructions cleaned up")
        
        # Check for reasonable document length (chord chart should be concise)
        word_count = len(text.split())
        if word_count > 500:
            feedback_parts.append("⚠️ Document very long - may contain unnecessary content")
        
        # Final scoring
        score = float(min(score, 1.0))  # Cap at 100%
        passed = score >= 0.75
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete. Score: {score:.2f}, Passed: {passed}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
