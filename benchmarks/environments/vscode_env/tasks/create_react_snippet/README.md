# Create React Snippet Task

**Difficulty**: 🟡 Medium  
**Skills**: VSCode configuration, snippet creation, JSON editing, developer productivity  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Create a custom VSCode user snippet for React functional components to eliminate repetitive boilerplate when creating new components.

## Context

You're a React developer tired of typing the same component boilerplate repeatedly. You want to create a snippet that triggers with `rfc` and generates a complete TypeScript React functional component template with props interface, useState hook, and JSX return.

## Expected Workflow

1. Open Command Palette (`Ctrl+Shift+P`)
2. Type and select "Snippets: Configure User Snippets" or "Preferences: Configure User Snippets"
3. Choose "typescriptreact.json" or "javascriptreact.json" for React files
4. Define snippet with:
   - Prefix: `rfc`
   - Description: "React Functional Component with TypeScript and hooks"
   - Body containing: TypeScript interface, functional component, useState hook, JSX return, export default
5. Save the snippet file

## Verification

Checks for:
1. Snippet file exists at correct location
2. Valid JSON syntax
3. Snippet with prefix `rfc` exists
4. Contains description
5. Body includes: interface/type, component declaration, useState, return statement, export

**Pass Threshold**: 95% (7.6/8.0 points)

## Tips

- VSCode snippet syntax uses `$1`, `$2`, etc. for tab stops
- Body should be an array of strings (one per line)
- Component name placeholders help with customization