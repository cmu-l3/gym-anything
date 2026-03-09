# Replicate Posner Cueing Paradigm

## Domain Context
Posner's spatial cueing paradigm (1980) is foundational in cognitive neuroscience and clinical neuropsychology. It measures the efficiency of attentional orienting by comparing response times to validly vs. invalidly cued targets. Building this experiment requires precise temporal control across multiple trial phases (fixation→cue→ISI→target), which maps to multiple Builder routines within a loop.

## Goal
Implement the complete Posner spatial cueing paradigm in PsychoPy Builder. The agent must create a conditions CSV with valid, invalid, and neutral cue trials for left/right targets, and build the experiment with proper temporal structure: fixation (500ms) → cue (200ms) → target (until response). The experiment needs instructions and debrief routines, and a trial loop wrapping the fixation-cue-target sequence.

## Success Criteria
- Conditions CSV with columns: cue_location, target_location, cue_validity, corrAns
- All 3 validity types (valid, invalid, neutral)
- Both left and right target locations
- Correct response keys (left/right)
- Separate routines for fixation, cue, and target (temporal structure)
- Timed durations on fixation and cue routines
- Keyboard response collection on target routine
- Loop with conditions file reference
- Instructions and debrief routines

## Verification Strategy
1. Conditions CSV validity types and column presence
2. Paradigm-specific routines (fixation, cue, target)
3. Temporal structure verification (timed fixation, timed cue)
4. Keyboard response on target routine
5. Loop with conditions reference
6. Instructions and debrief presence
7. Structural complexity

## Edge Cases
- Agent may implement ISI as separate routine or as timing gap
- Cue display may be text, shape, or highlight
- Agent may add additional routines (e.g., feedback, practice)
