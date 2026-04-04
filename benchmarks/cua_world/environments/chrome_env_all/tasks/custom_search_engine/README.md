# Chrome Custom Search Engine Task (`custom_search_engine@1`)

## Overview

This task tests an agent's ability to navigate Chrome's settings interface and add a custom search engine with a keyword shortcut. The agent must access the search engine management interface, add a new search engine entry with specific parameters (name, keyword, URL pattern), and ensure the configuration is properly saved.

## Task Requirements

Add a custom search engine to Chrome with these exact specifications:
- **Search engine name:** Wikipedia
- **Keyword:** wiki  
- **URL:** https://en.wikipedia.org/wiki/Special:Search?search=%s

## Expected Agent Behavior

1. Navigate to Chrome settings (`chrome://settings`)
2. Go to "Search engine" section
3. Click "Manage search engines and site search"
4. Click "Add" to add a new search engine
5. Fill in the three required fields
6. Save the configuration

## Verification Method

The verifier parses Chrome's `Preferences` file to check for the custom search engine entry. It validates:
- Search engine name contains "Wikipedia"
- Keyword is exactly "wiki"
- URL contains wikipedia.org domain with proper search placeholder (%s)
- URL pattern is functional for Wikipedia searches

## Success Criteria

- **Score 100:** Custom search engine properly configured with all correct parameters
- **Score 50:** Entry exists but URL is invalid
- **Score 0:** Entry not found or verification failed

## Files

- `task.json` - Task configuration
- `setup_task.sh` - Ensures Chrome is ready
- `close_chrome.sh` - Closes Chrome to save preferences
- `verifier.py` - Validates the custom search engine configuration
- `README.md` - This file

## Testing

After completion, the search engine can be used by:
1. Clicking the address bar (Ctrl+L)
2. Typing `wiki` followed by Space or Tab
3. Typing a search query (e.g., "machine learning")
4. Pressing Enter to search Wikipedia

## Technical Notes

- Chrome stores search engines in `~/.config/google-chrome/Default/Preferences`
- The JSON structure varies slightly between Chrome versions
- The verifier checks multiple possible storage locations
- URL placeholder can be `%s`, `{searchTerms}`, or URL-encoded variants