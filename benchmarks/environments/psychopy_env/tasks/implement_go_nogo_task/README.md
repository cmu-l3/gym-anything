# Implement Go/No-Go Task

## Domain Context
The Go/No-Go paradigm is a core neuropsychological assessment for response inhibition. Clinical neuropsychologists use it to evaluate impulse control in patients with ADHD, traumatic brain injury, and executive function disorders. A proper implementation requires correct go/nogo trial ratios (75/25), color-coded stimuli, practice with feedback, and Code components for dynamic response evaluation.

## Goal
Build a complete Go/No-Go inhibitory control experiment in PsychoPy Builder. The agent must create both a conditions CSV with proper go/nogo ratio (green=go at 75%, red=nogo at 25%) and the full experiment with instructions, practice block with accuracy feedback via Code component, break, main block, and debrief.

## Success Criteria
- Conditions CSV with columns: stimColor, trial_type, corrAns
- Green go trials (~75%) and red nogo trials (~25%)
- Correct response mapping (space for go, None/no response for nogo)
- Practice block with Code component providing trial-by-trial feedback
- 5+ routines (instructions, practice, trial, feedback, break, debrief)
- Loop referencing conditions file

## Verification Strategy
1. CSV go/nogo ratio validation (more go than nogo)
2. Color-trial type mapping (green=go, red=nogo)
3. Routine presence checks
4. Code component for feedback
5. Loop with conditions reference
6. Structural complexity

## Edge Cases
- Agent may use different column names (e.g., "color" vs "stimColor")
- Feedback may be handled entirely in Code component without separate routine
- Go/nogo ratio need not be exactly 75/25 but go must outnumber nogo
