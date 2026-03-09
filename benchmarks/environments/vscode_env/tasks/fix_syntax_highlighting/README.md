# Fix Syntax Highlighting Task

**Task ID**: `fix_syntax_highlighting@1`  
**Difficulty**: 🟡 Medium  
**Skills**: VSCode configuration, file associations, settings management  
**Duration**: 300 seconds  
**Steps**: ~50

## Overview

Configure VSCode to recognize `.tpl` template files as HTML, enabling proper syntax highlighting. This is a common real-world scenario when working with custom file extensions in web development projects.

## Problem Statement

The workspace contains a web project using `.tpl` files for HTML templates with embedded template expressions (similar to Handlebars or Mustache). Currently, VSCode treats these files as **plain text** because it doesn't recognize the `.tpl` extension, resulting in:

- ❌ No syntax highlighting for HTML tags
- ❌ No color coding for attributes  
- ❌ No IntelliSense autocomplete for HTML
- ❌ No bracket matching or tag closing
- ❌ Harder to spot syntax errors

## Objective

Add a file association in VSCode settings to map `*.tpl` files to the `html` language mode, enabling full HTML syntax highlighting and editor features.

## Workspace Contents
