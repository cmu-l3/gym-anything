# Task: indusengg_vsm_lean_design

## Domain Context

Industrial Engineers in manufacturing use Value Stream Mapping (VSM) as the primary lean assessment deliverable. A complete VSM package includes a Current State map (documenting the existing process) and a Future State map (showing planned improvements with kaizen bursts). EdrawMax provides a dedicated Lean Mapping / VSM shape library with supplier/customer icons, process boxes, inventory triangles, push arrows, and kaizen bursts.

## Occupation

**Industrial Engineers** (top EdrawMax user group by economic impact)

## Task Overview

Create a 2-page VSM document for a brake pad production line in EdrawMax, saved as `/home/ga/vsm_current_future.eddx`.

## Goal / End State

The completed file must contain 2 pages:

- **Page 1 — Current State VSM**: Full current-state value stream map including supplier and customer icons, Production Control/Planning box with information flow arrows, ≥4 sequential production process boxes (Stamping, Welding, Surface Treatment, Final Assembly & QC) each with data boxes showing process metrics, inventory triangles between process steps, push arrows, and a timeline bar at the bottom showing value-added vs. non-value-added time.
- **Page 2 — Future State VSM**: Improved future-state map with lean improvements (pull/kanban, waste elimination), kaizen burst shapes highlighting changes, and a summary of the top 3 improvements with expected impact on lead time and cycle time.
- Professional theme applied.

## Difficulty

**hard** — Task specifies the VSM structure and required elements in detail (agent knows what to build) but provides no UI navigation steps. Agent must independently find EdrawMax's VSM/Lean shape library and know how to construct both current and future state maps.

## Success Criteria

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| A: Valid EDDX archive | 15 | File at correct path, valid ZIP |
| B: Modified after task start | 10 | File mtime > start timestamp |
| C: Multi-page (≥ 2 pages) | 20 | ≥ 2 page XML files in archive |
| D: VSM content on page 1 | 20 | ≥ 6 VSM keywords (supplier, customer, inventory, cycle time, push, etc.) |
| E: Shape density | 20 | ≥ 12 Shape elements AND ≥ 6 ConnectLine elements |
| F: Future state content | 10 | Future/kaizen/improvement keywords on page 2 or ≥ 6 text elements |
| G: VSM shape library | 5 | NameU attributes match VSM library shape types |

**Pass threshold: 60/100**

## Verification Strategy

`verifier.py::verify_indusengg_vsm_lean_design` — copies EDDX, parses ZIP XML, searches for VSM-specific keywords in shape text labels (Chars elements) and NameU attributes, counts pages, shapes, and connectors.

## Anti-Gaming

- `setup_task.sh` deletes the output file and records start timestamp.

## Edge Cases

- Agent creates a generic flowchart instead of a proper VSM — criterion D (20 pts) fails if VSM-specific terms absent. Criterion G (5 pts) also fails if EdrawMax's VSM shape library is not used.
- Agent creates only one page — criteria C (20 pts) and F (10 pts) fail.
- Agent uses VSM shapes but omits text labels — criterion D depends on text content in Chars elements.
