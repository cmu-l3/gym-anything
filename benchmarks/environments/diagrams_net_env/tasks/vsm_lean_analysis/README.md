# Task: vsm_lean_analysis

**ID**: vsm_lean_analysis@1
**Difficulty**: hard
**Occupation**: Industrial Engineers ($758M GDP impact) + Industrial Engineering Technologists ($73M GDP)
**Timeout**: 900 seconds | **Max Steps**: 90

## Domain Context

Value Stream Mapping (VSM) is the foundational lean manufacturing tool for visualizing production flow and identifying waste. Introduced by Toyota and popularized by Rother & Shook ("Learning to See", 1998, Lean Enterprise Institute), VSM uses a standardized notation for process boxes, inventory triangles, push/pull arrows, information flows, and kaizen bursts. Industrial engineers create current-state VSMs as the first step of any lean transformation project. draw.io includes a dedicated lean mapping shape library for this purpose.

## Data Source

**Real case study**: Toyota Steering Bracket manufacturing, Acme Stamping
**Reference**: Rother, M. & Shook, J. (1998). *Learning to See: Value Stream Mapping to Create Value and Eliminate Muda*. Lean Enterprise Institute, Brookline, MA. (ISBN 0-9667843-0-8)
This is the canonical VSM teaching example, with data from an actual Toyota tier-1 supplier.

## Task Goal

Create a complete current-state Value Stream Map from scratch using production metrics from `~/Desktop/production_metrics.csv` (Toyota steering bracket real data) and mapping requirements from `~/Desktop/vsm_guide.txt`. The VSM must be saved at `~/Diagrams/current_state_vsm.drawio` using draw.io's lean mapping shape library.

## What Makes This Hard

1. **Specialized shape library**: Must discover and use draw.io's lean mapping library (not default shapes)
2. **VSM notation knowledge**: Must correctly apply VSM conventions (push arrows, inventory triangles, information flows)
3. **Data interpretation**: Must read CSV metrics and translate to diagram data labels
4. **Waste identification**: Must independently identify the 3 highest-waste steps for kaizen bursts
5. **Create from scratch**: No starting diagram — must create a new file and design the full layout

## Production Line Data (5 Process Steps — Toyota Steering Bracket)

| Step | Cycle Time | C/O | Uptime | WIP After |
|------|-----------|-----|--------|-----------|
| PC Press | 1s | 3600s | 85% | 4,600 units |
| Spot Weld I | 39s | 600s | 100% | 4,700 units |
| Spot Weld II | 46s | 600s | 80% | 1,100 units |
| Assembly I | 62s | 0 | 100% | 1,600 units |
| Assembly II | 40s | 0 | 100% | 1,200 units |

Customer demand: 920 brackets/day | Takt time: 60 sec/bracket
Total lead time: ~23.6 days | Total value-added time: 188 seconds

## Success Criteria

| Criterion | Points |
|-----------|--------|
| File created during task | 10 |
| Process boxes ≥ 5 (all production steps) | 25 |
| Inventory triangles ≥ 5 (between steps) | 15 |
| Supplier and Customer icons | 15 |
| Timeline/lead time section | 15 |
| Kaizen bursts ≥ 3 (worst-waste steps) | 10 |
| PDF exported | 10 |

**Pass threshold**: 60 points

## Highest Waste Steps (for Kaizen Bursts)

1. PC Press → Spot Weld I: 4,600 + 4,700 = 9,300 units WIP (batch scheduling, EPE=1 week)
2. Spot Weld I → Spot Weld II: 4,700 units WIP (Spot Weld II only 80% uptime)
3. Assembly I: C/T=62s exceeds takt time of 60s (line bottleneck)
