# P300 Auditory Oddball

## Domain Context

The P300 auditory oddball is one of the most replicated paradigms in cognitive neuroscience (Sutton et al., 1965; Polich, 2007). Clinical neuropsychologists use P300 amplitude and latency as EEG biomarkers for cognitive decline, ADHD, schizophrenia, and disorders of consciousness. Correct implementation requires precise stimulus probability ratios (80/20 standard/deviant), specific tone frequencies (1000/2000 Hz), and EEG trigger codes at stimulus onset. Errors in any of these elements invalidate the paradigm.

## Goal

Build a complete P300 auditory oddball paradigm from scratch using PsychoPy Builder. Create both the Builder experiment and a conditions file with exactly 300 rows (240 standard + 60 deviant) at the correct frequencies and with correct trigger codes. Include a Sound component, a code component for trigger output, multiple blocks with a rest screen, and an accuracy feedback screen.

## Success Criteria

The experiment (`p300_oddball.psyexp`) and conditions file (`p300_conditions.csv`) must together satisfy:
- Conditions file has exactly 300 rows (not approximately)
- Exactly 240 rows with standard tone (1000 Hz) and exactly 60 deviant rows (2000 Hz)
- A frequency column with values 1000 and 2000; a trigger code column with values 1 and 2
- A Sound component present in the experiment
- A code component implementing trigger/marker output logic
- At least 2 blocks with a rest screen between them
- An accuracy feedback screen at the end

## Verification Strategy

9 independent criteria. Verifier independently re-parses both the conditions CSV and the psyexp XML. Scoring: 100 pts total, pass threshold 60 pts.

1. File valid (10 pts)
2. Conditions file: 300 rows (10 pts)
3. Exact 240 standard + 60 deviant split (20 pts)
4. Correct frequency values (1000/2000 Hz) (15 pts)
5. Trigger codes 1 and 2 present (10 pts)
6. Sound component in psyexp (10 pts)
7. Code component with trigger logic (10 pts)
8. ≥2 blocks with rest screen (10 pts)
9. Accuracy feedback screen (5 pts)

## Schema Reference

- Output experiment: `/home/ga/PsychoPyExperiments/p300_oddball.psyexp`
- Output conditions: `/home/ga/PsychoPyExperiments/conditions/p300_conditions.csv`
- Required conditions columns: tone frequency (Hz), trigger code (1 or 2), is_target (0 or 1)

## Edge Cases

- Column names for frequency/trigger are flexible; verifier searches for numeric values 1000/2000 in any numeric column
- Rest screen may appear in any routine with `rest`, `break`, or `pause` in its name
- Feedback screen detected by keywords: `feedback`, `accuracy`, `score`, `result`, `hit`
- Agent may use one large block or split into 2; verifier requires at least 2 LoopInitiators in the Flow
