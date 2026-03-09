# Build Visual Search Experiment

## Domain Context
Visual search is one of the most studied paradigms in cognitive psychology. Researchers (psychology teachers, grad students) routinely build T-among-L search experiments to study attentional selection. A complete experiment requires practice trials with feedback, counterbalanced conditions across set sizes, and proper timing.

## Goal
Build a complete visual search experiment from scratch in PsychoPy Builder, including a conditions CSV file with set sizes (4, 8, 12, 16) crossed with target presence (present/absent), and the full experiment with instructions, practice block with feedback, break, main block, and debrief.

## Success Criteria
- Conditions CSV exists with required columns (set_size, target_present, corrAns)
- All 4 set sizes and both target-present/absent conditions
- Correct response mapping (space=present, n=absent)
- Experiment has 5+ routines (instructions, practice, trial, feedback, break, debrief)
- Practice block uses Code component for trial-by-trial feedback
- Loop references the conditions file
- Structural complexity matches Builder-generated output

## Verification Strategy
1. CSV content validation (columns, set sizes, target presence, response mapping)
2. Routine presence checks (instructions, practice, trial, feedback, break, debrief)
3. Loop with conditions reference
4. Code component presence (for feedback)
5. Structural complexity gates

## Edge Cases
- Agent may name routines differently (e.g., "welcome" instead of "instructions")
- Feedback may be in Code component or separate routine
- Practice conditions may be a subset of main conditions
