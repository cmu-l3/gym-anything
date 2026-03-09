# N-Back Adaptive Experiment

## Domain Context

The n-back task (Kirchner, 1958) is a foundational working memory paradigm used throughout cognitive neuroscience and clinical assessment. Adaptive variants that adjust difficulty based on performance (Jaeggi et al., 2008) are widely used in research with clinical populations including ADHD, schizophrenia, and mild cognitive impairment, where fixed n-levels produce ceiling or floor effects. Building an adaptive n-back requires chaining Builder's loop system with a custom code component and a correctly formatted stimulus conditions file.

## Goal

Build a complete adaptive n-back experiment from scratch in PsychoPy Builder. The experiment starts at 2-back and adjusts the n-level dynamically based on accuracy (increases at >85%, decreases at <55%). Create both the `.psyexp` Builder file and the `nback_conditions.csv` conditions file.

## Success Criteria

The experiment (`nback_experiment.psyexp`) must:
- Have a conditions file with ≥30 rows, `letter` and `is_target` columns, 25–45% target rate, consonants only
- Implement correct trial timing: fixation (200ms), letter (500ms), ISI (300ms)
- Include a keyboard response component during letter/ISI
- Contain a code component with adaptive logic using 85%/55% accuracy thresholds
- Have ≥3 loops/blocks in the Flow
- Have a between-block summary/feedback routine showing n-level and accuracy
- Be saved to the correct output path

## Verification Strategy

7 independent criteria scored via XML parsing of the `.psyexp` and CSV analysis of the conditions file. Verifier independently re-parses both files. Scoring: 100 pts total, pass threshold 60 pts.

1. File valid and newly created (10 pts)
2. Conditions: ≥30 rows, correct columns, 25–45% targets, consonants only (20 pts)
3. Trial timing: fixation ≤300ms, letter ≤700ms, ISI ≤500ms (15 pts)
4. Keyboard response component present (10 pts)
5. Code with 85%/55% adaptive thresholds (20 pts)
6. ≥3 loops in Flow (10 pts)
7. Summary/feedback routine between blocks (15 pts)

## Schema Reference

- Output experiment: `/home/ga/PsychoPyExperiments/nback_experiment.psyexp`
- Output conditions: `/home/ga/PsychoPyExperiments/conditions/nback_conditions.csv`

## Edge Cases

- Any reasonable consonant set is acceptable as long as no vowels
- Code component may implement accuracy differently (rolling window vs block-level) — any method referencing 85%/55% thresholds is acceptable
- Summary routine name is flexible; verifier uses keyword detection for `score`, `result`, `feedback`, `summary`, `level`
