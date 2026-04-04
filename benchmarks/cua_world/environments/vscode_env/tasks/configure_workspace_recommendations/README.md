# Configure Workspace Recommendations Task

**Difficulty**: 🟡 Medium  
**Skills**: Workspace configuration, team collaboration, extension management, JSON editing  
**Duration**: 120 seconds  
**Steps**: ~30

## Objective

Configure workspace-level extension recommendations for a team project by creating and populating the `.vscode/extensions.json` file. This ensures all team members receive prompts to install essential extensions when they open the project.

## Context

You're working on a full-stack Python + JavaScript project. New team members keep asking "What VSCode extensions should I install?" Some install incompatible formatters, others miss critical linting tools. You need to standardize the development environment by creating workspace extension recommendations.

## Expected Workflow

1. Create `.vscode/` directory in the workspace root (if it doesn't exist)
2. Create `extensions.json` file inside `.vscode/`
3. Add a JSON object with a `recommendations` array
4. Include at least 3-5 appropriate extension IDs for the project
5. Use proper extension ID format: `publisher.extension-name`
6. Save the file

## Example Structure
