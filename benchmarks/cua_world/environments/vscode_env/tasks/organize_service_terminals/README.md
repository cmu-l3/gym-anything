# Organize Service Terminals Task

**Difficulty**: 🟡 Medium  
**Skills**: Terminal management, workspace organization, multi-service development  
**Duration**: 240 seconds  
**Steps**: ~30

## Objective

Set up an organized multi-terminal workspace in VSCode for running concurrent microservices. Create three separate integrated terminal tabs with meaningful names to monitor backend API, frontend dev server, and background worker services independently.

## Scenario

You're a full-stack developer working on a microservices application. The project requires running three services locally (backend, frontend, worker), and you need to monitor them simultaneously. Instead of juggling separate terminal windows or having interleaved logs in one terminal, you'll organize them using VSCode's integrated terminal with named tabs.

## Expected Workflow

1. Open VSCode integrated terminal (Ctrl+`)
2. Rename first terminal to "Backend API" (or similar)
3. Create second terminal (click + button or Ctrl+Shift+`)
4. Rename second terminal to "Frontend Dev" (or similar)
5. Create third terminal (click + again)
6. Rename third terminal to "Worker" (or similar)
7. Verify all three terminals are visible with meaningful names

## Terminal Renaming

To rename a terminal:
- Right-click on terminal tab
- Select "Rename" from context menu
- Enter new name
- Press Enter

Alternative:
- Click terminal tab to focus it
- Open Command Palette (Ctrl+Shift+P)
- Type "Terminal: Rename"
- Enter new name

## Verification

Checks for:
1. Exactly 3 integrated terminals exist
2. All terminals have custom names (not default "bash"/"zsh")
3. Terminal names are semantically meaningful (relate to services like "backend", "frontend", "worker", "api", etc.)
4. Terminal panel is visible
5. Terminals are organized as separate tabs

**Pass Threshold**: 75% (4/5 criteria)

## Tips

- Terminal panel is typically at bottom of VSCode window
- You can create new terminals with the "+" button in terminal panel
- Right-click terminal tab for rename option
- Focus matters: make sure terminal panel is visible when task completes