# Evidence: create_blog_post Task

This folder contains evidence from actual agent test runs demonstrating the WordPress environment works correctly.

## Evidence Screenshots

| File | Description | Verification |
|------|-------------|--------------|
| 01_initial_dashboard.png | WordPress admin dashboard at task start | Firefox open, admin logged in, dashboard visible |
| 02_posts_list.png | Posts list page after clicking Posts menu | Successfully navigated to Posts section |
| 03_new_post_editor.png | Gutenberg block editor for new post | Editor loads correctly with title field, content area, Categories/Tags sidebar |

## What This Evidence Shows

1. **Environment starts correctly**: WordPress admin dashboard is accessible
2. **Navigation works**: Click actions successfully navigate between pages
3. **Editor functionality**: The Gutenberg block editor loads with all required UI elements:
   - "Add title" field for post title
   - Content area with "Type / to choose a block"
   - Right sidebar with Post settings (Categories, Tags, Status, etc.)
   - Publish button visible

## Test Date

Generated: 2026-02-02

## How Evidence Was Generated

Evidence was generated using the gym_anything framework with:
- QEMU-Apptainer runner
- pyautogui for mouse interactions
- VNC for screen capture

Action format used:
```python
env.step([{'mouse': {'left_click': (x, y)}}])
```

## Task Requirements

For the create_blog_post task to pass, an agent must:
1. Navigate to Posts → Add New Post
2. Enter title: "The Future of Artificial Intelligence in Healthcare"
3. Add content with keywords: artificial intelligence, healthcare, diagnostics, treatment, patient care
4. Select category: Technology
5. Add ALL 4 tags: AI, healthcare, technology, featured
6. Click Publish
