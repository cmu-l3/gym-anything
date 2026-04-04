# Integrate Custom Build Tool Task

**Difficulty**: 🟡 Medium  
**Skills**: VSCode tasks configuration, problem matchers, regex patterns, build system integration  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Configure VSCode to integrate with a proprietary build tool called `fastbuild`. The tool works but errors don't appear in VSCode's Problems panel, forcing manual terminal inspection. Your goal is to create a VSCode task with a custom problem matcher that parses the tool's error format.

## Scenario

You've joined a company that uses a custom build tool. Every time the build fails, you have to:
1. Scroll through terminal output
2. Manually find errors
3. Note filename and line number
4. Use Ctrl+P to open the file
5. Use Ctrl+G to jump to the line

This happens 20+ times per day. Your team lead asked you to "make it work like a normal compiler" so errors are clickable.

## FastBuild Error Format

The tool outputs errors in this format: