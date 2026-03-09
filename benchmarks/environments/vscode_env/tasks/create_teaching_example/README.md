# Create Teaching Example Task

**Difficulty**: 🟡 Medium  
**Skills**: Content creation, technical writing, async JavaScript, documentation  
**Duration**: 480 seconds (8 minutes)  
**Steps**: ~40

## Objective

Create a self-contained, beginner-friendly JavaScript teaching example that demonstrates the evolution from callbacks to Promises to async/await. This tests your ability to synthesize knowledge into educational content.

## Scenario

You're preparing teaching material for a coding bootcamp session tomorrow. Students have just learned basic Promises and need to understand async/await through a realistic, runnable example.

## Expected Output

A file at `/home/ga/workspace/teaching-materials/async-await-demo.js` containing:

1. **Header comment block** explaining the file's purpose and how to run it
2. **Three implementations** of the SAME task (fetching user data from JSONPlaceholder API):
   - Version 1: Callback-based (showing callback hell)
   - Version 2: Promise-based with `.then()`
   - Version 3: Async/await (modern approach)
3. **Educational inline comments** explaining WHY, not just WHAT
4. **Console logging** to demonstrate execution flow
5. **Error handling** examples
6. **No external dependencies** - only Node.js built-ins (http/https)
7. **Runnable** with `node async-await-demo.js`
8. **Length**: 150-300 lines (comprehensive but not overwhelming)

## Expected Workflow

1. Review the README context in teaching-materials/
2. Create new file: `async-await-demo.js`
3. Write header comment block with title and usage
4. Implement callback-based version
5. Implement Promise-based version
6. Implement async/await version
7. Add educational comments throughout
8. Add console.log statements to show execution
9. Include error handling
10. Save the file (Ctrl+S)

## Verification

Checks for:
1. File exists at correct path
2. Appropriate length (150-300 lines)
3. Has comprehensive header comment
4. Contains callback implementation
5. Contains Promise implementation
6. Contains async/await implementation
7. Has educational comments (explaining "why")
8. Includes console logging (6+ statements)
9. Self-contained (no external dependencies)
10. Has error handling (try/catch or .catch)

**Pass Threshold**: 70% (7/10 criteria)