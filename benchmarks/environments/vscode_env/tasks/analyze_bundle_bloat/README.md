# Bundle Size Analysis Task

**Difficulty**: 🟡 Medium  
**Skills**: Terminal usage, npm package management, bundle analysis, technical documentation  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Analyze a React application's production bundle to identify the largest dependencies contributing to bundle bloat, then document findings in a markdown report.

## Scenario

A React application's production bundle has grown from 250KB to 850KB over the past month, significantly impacting page load times. Your task is to investigate which dependencies are contributing most to the bundle size and create a technical report with optimization recommendations.

## Expected Workflow

1. Open the integrated terminal (Ctrl+`)
2. Install a bundle analysis tool: `npm install --save-dev webpack-bundle-analyzer` (or similar: `source-map-explorer`, `rollup-plugin-visualizer`)
3. Add an analysis script to `package.json` (optional - can run directly)
4. Run bundle analysis command to generate statistics
5. Review the analysis output (may open in browser or generate JSON/text report)
6. Create a file named `BUNDLE_ANALYSIS.md` in the project root
7. Document findings including:
   - At least 3 specific dependency names with size information
   - Quantitative data (sizes in KB/MB or percentages)
   - At least one actionable optimization recommendation

## Verification

Checks for:
1. Bundle analyzer tool installed in `package.json` devDependencies
2. `BUNDLE_ANALYSIS.md` file exists in project root
3. Report identifies at least 3 specific dependencies by name
4. Report includes quantitative size data (numbers with KB/MB or percentages)
5. Report contains optimization recommendations

**Pass Threshold**: 75% (4/5 criteria)

## Example Report Structure
