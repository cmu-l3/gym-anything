# Integrate Custom Linter Task

**Difficulty**: 🟡 Medium  
**Skills**: VSCode tasks, problem matchers, regex patterns, IDE integration  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Integrate a custom security linter (`medscan`) into VSCode by creating a task with a problem matcher that parses the linter's output format and displays errors in the Problems panel.

## Real-World Context

You're on a medical device software team that uses a proprietary security scanner called `medscan`. The tool outputs security violations in a custom format. Your task is to integrate it into VSCode so violations appear as clickable problems in the IDE.

## Custom Linter Output Format

The `medscan` tool outputs errors like: