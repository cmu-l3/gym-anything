# Technical Debt Catalog Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-file search, regex patterns, documentation, code navigation  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Systematically discover and catalog all technical debt markers (TODO, FIXME, HACK, XXX) scattered across a codebase using VSCode's search capabilities. Create a structured markdown document organizing findings by severity.

## Scenario

You're a tech lead preparing for sprint planning. The previous team left scattered TODO/FIXME/HACK/XXX comments throughout the code. Stakeholders need to know: "What technical debt exists, where is it, and what's critical?" You must create a comprehensive inventory document.

## Expected Workflow

1. Open Search panel (Ctrl+Shift+F)
2. Enable regex mode (click .* button)
3. Enter search pattern: `(TODO|FIXME|HACK|XXX):`
4. Apply file filters:
   - Include: `*.py, *.js, *.ts, *.jsx, *.tsx`
   - Exclude: `**/node_modules/**, **/venv/**, **/dist/**`
5. Execute search and review results (~10 matches)
6. Create `TECHNICAL_DEBT.md` in workspace root
7. Document findings with:
   - File paths (relative to workspace)
   - Line numbers
   - Comment descriptions
   - Categorization by severity (Critical/Deferred/Security)
8. Save file

## Expected Output Format
