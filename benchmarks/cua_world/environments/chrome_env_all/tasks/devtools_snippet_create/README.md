# Chrome DevTools Code Snippets Creation Task (`devtools_snippet_create@1`)

## Overview

This task challenges an agent to use Chrome DevTools' Snippets feature to create, save, and execute reusable JavaScript code. The agent must navigate DevTools' Sources panel, create a new snippet, write JavaScript code that modifies the page, and execute it to verify functionality.

## Task Description

**Goal**: Create a JavaScript snippet named "PageTitleChanger" that changes the document title and logs a success message.

**Starting State**: Chrome with a test page loaded showing instructions

**Expected Actions**:
1. Press F12 to open DevTools
2. Navigate to Sources panel
3. Open Snippets pane (may need to click '>>' menu)
4. Click "+ New snippet"
5. Rename to "PageTitleChanger"
6. Write JavaScript code: