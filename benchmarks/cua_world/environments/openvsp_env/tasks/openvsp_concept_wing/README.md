# openvsp_concept_wing

## Task Description

A junior aerospace engineer must build a parametric concept wing model in OpenVSP from a specification document written by the chief designer. The spec describes the wing geometry of a regional turboprop aircraft in metric units. The agent must discover the spec, read it, interpret the values, and correctly set each wing parameter in OpenVSP.

**Realistic context**: Spec-driven model creation is the standard workflow for new aircraft programs. Engineers receive a geometry specification sheet from the design authority and must implement it in the CAD/parametric tool without transcription errors. This tests the complete reading-to-implementation pipeline.

## Wing Specification (written by setup_task.sh to Desktop)

Based on a regional 9-seat turboprop concept:

| Parameter | Value |
|-----------|-------|
| Total Span | 12.40 m |
| Root Chord | 2.30 m |
| Tip Chord | 1.20 m (taper ratio 0.52) |
| Dihedral | 5.0° |
| LE Sweep | 3.0° |
| Twist (washout) | -2.0° at tip |

## Required OpenVSP Model

- WingGeom component with TotalSpan ≈ 12.40 m
- TaperRatio ≈ 0.52 (or root/tip chords approximately matching)
- Dihedral section parameter ≈ 5.0°
- A Fuselage (or Pod/BodyOfRevolution) component

## Scoring (100 pts)

- concept_wing.vsp3 exists and is valid XML: 10 pts
- WingGeom component present: 20 pts
- TotalSpan in [10.5, 14.5] m (±15% tolerance): 25 pts
- Any WingSect Dihedral in [2.0, 9.0]°: 25 pts
- Any non-wing geometry component (fuselage/pod): 20 pts

Pass threshold: 60.

## Files

- `setup_task.sh` — creates wing_spec.txt on Desktop, clears old concept files, launches OpenVSP blank
- `export_result.sh` — copies concept_wing.vsp3 for verification
- `verifier.py` — parses .vsp3 XML, checks WingGeom, TotalSpan, Dihedral, component count

## Difficulty Justification

**very_hard**: Agent must find the spec on the Desktop, parse textual parameter values, create a new model from scratch (not edit an existing one), correctly navigate OpenVSP's wing creation workflow (adding components, setting planform parameters in the Plan tab), add a fuselage component, and save — all without explicit GUI instructions.
