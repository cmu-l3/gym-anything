# Fear Conditioning Coder

## Domain Context

Differential fear conditioning is the foundational laboratory model for anxiety disorder research (LeDoux, 2000). The paradigm requires precise CS–US timing and a calibrated US intensity — too weak and conditioning fails; too strong and the paradigm becomes unethical. Lonsdorf et al. (2017, Psychophysiology) validated the use of PsychoPy's `data.StairHandler` to adaptively titrate US amplitude to a consistent subjective aversiveness rating across participants, addressing a major source of individual-difference confounding. Experimental psychologists and postdoctoral researchers in anxiety labs implement this paradigm in PsychoPy Coder rather than Builder to maintain full programming control over the staircase logic and data output structure.

## Goal

Write a complete fear conditioning Python script using PsychoPy Coder (not Builder). The script must implement habituation and acquisition phases, a differential CS+/CS− design with colored square stimuli, correct CS/US timing overlap, an adaptive `data.StairHandler` for US amplitude, a visual rating scale for aversiveness, and data saving via `ExperimentHandler`. The output is a single `.py` file.

## Success Criteria

The script (`fear_conditioning.py`) must:
- Be valid Python with no syntax errors
- Import from psychopy: `core`, `visual`, `data`, `event`
- Instantiate a `data.StairHandler` with `startVal=0.8`, `stepSizes=[0.1, 0.05]`, `nReversals≥4`, `stepType='lin'`
- Define habituation and acquisition phases with CS+ and CS− stimuli
- Include US delivery in the acquisition phase
- Include a visual rating scale for US aversiveness
- Implement staircase adjustment logic (using the rating to call `staircase.addData()` or adjust amplitude)
- Use `data.ExperimentHandler` and save to `/home/ga/PsychoPyExperiments/data/`
- Include CS timing of ~4s and US onset at ~3.5s into the CS

## Verification Strategy

7 independent criteria assessed by AST parsing and regex on the Python source. The verifier independently copies and re-parses the script. Scoring: 100 pts total, pass threshold 60 pts.

1. Valid Python, newly created (10 pts)
2. Required imports: core, visual, data, event (10 pts)
3. StairHandler with correct parameters: startVal=0.8, nReversals≥4 (20 pts)
4. Phase structure: habituation + acquisition + CS+ + CS− + US (20 pts)
5. Rating scale + staircase adjustment logic (15 pts)
6. ExperimentHandler + data saving to correct directory (15 pts)
7. CS/US timing + counterbalancing (10 pts)

## Schema Reference

- Output script: `/home/ga/PsychoPyExperiments/fear_conditioning.py`
- Data output directory: `/home/ga/PsychoPyExperiments/data/`
- StairHandler required params: `startVal=0.8`, `stepSizes=[0.1, 0.05]`, `nReversals=4`, `stepType='lin'`, `minVal=0.0`, `maxVal=1.0`

## Edge Cases

- Script may use `psychopy.sound.Sound` for white noise or define a noise stimulus any other way
- Rating scale may use `psychopy.visual.RatingScale`, `Slider`, or custom key-response rating — all detected
- Counterbalancing may be implemented as `participant % 2` or `expInfo['participant'] % 2` — both detected
- `ExperimentHandler` must be used (not just `csv.writer`); partial credit awarded if data saving to correct directory without ExperimentHandler
