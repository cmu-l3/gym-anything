# Locate Safe Edit Zones Task

**Difficulty**: 🟡 Medium  
**Skills**: Code navigation, reading documentation, pattern recognition, technical writing  
**Duration**: 300 seconds  
**Steps**: ~80

## Objective

Identify safe locations to add custom error handling in a project with mixed generated and hand-written code. A bug report describes crashes on 429 rate limit errors. You need to determine which files are auto-generated (unsafe to edit) and which are designated extension points (safe to edit).

## Scenario

You've inherited a full-stack project using code generation tools (OpenAPI client generator). The previous developer left, and there's a bug in how the API client handles error responses. You need to fix it, but you must avoid editing generated code that will be overwritten when generators are re-run.

## Expected Workflow

1. Read the `bug-report.txt` to understand the problem
2. Explore the project structure to identify generated vs. custom code
3. Locate code generation configuration files (e.g., `codegen.yml`)
4. Find files with "DO NOT EDIT" warnings or similar markers
5. Identify extension points (custom/ directory, wrapper files)
6. Create `SAFE_EDIT_GUIDE.md` documenting:
   - Which files are auto-generated (unsafe)
   - Which files are safe to edit
   - Where to add the 429 error handling
   - Evidence from source files (quotes, line numbers)

## Verification

Checks for:
1. `SAFE_EDIT_GUIDE.md` exists in workspace root
2. Identifies `base.ts` as generated/unsafe
3. Identifies `api-client-wrapper.ts` as safe to edit
4. References code generation configuration
5. Includes evidence (quotes or line numbers from files)
6. Suggests correct fix location (wrapper file)

**Pass Threshold**: 70% (structured scoring across 5 criteria + bonus)