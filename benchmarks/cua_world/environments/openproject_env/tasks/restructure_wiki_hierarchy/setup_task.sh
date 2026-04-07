#!/bin/bash
echo "=== Setting up restructure_wiki_hierarchy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OpenProject is ready
wait_for_openproject

# Seed the initial "messy" state via Rails runner
# - Create two loose root pages
# - Ensure the target parent page does not exist
echo "Seeding wiki pages..."
op_rails "
  project = Project.find_by(identifier: 'mobile-banking-app')
  if project
    # Ensure wiki exists
    wiki = project.wiki || Wiki.create(project: project, status: 1)
    
    # 1. Create/Reset loose pages
    ['System Architecture', 'API Endpoints'].each do |title|
      slug = title.to_url
      page = WikiPage.find_by(wiki: wiki, slug: slug)
      
      # If page doesn't exist, create it
      if page.nil?
        page = WikiPage.new(wiki: wiki, title: title)
        page.save!
        
        # Create content
        author = User.find_by(login: 'admin')
        text = \"h1. #{title}\n\nThis is the official documentation for #{title}.\n\n* Section A\n* Section B\"
        WikiContent.create(page: page, author: author, text: text)
        puts \"Created page: #{title}\"
      else
        # If page exists, reset it to be a root page (no parent)
        page.parent_id = nil
        page.save!
        puts \"Reset page to root: #{title}\"
      end
    end
    
    # 2. Ensure target parent page is deleted (clean slate)
    target = WikiPage.find_by(wiki: wiki, title: 'Technical Documentation')
    if target
      target.destroy
      puts \"Removed existing target page\"
    end
  else
    puts \"ERROR: Project mobile-banking-app not found\"
  end
"

# Launch Firefox to the wiki index
echo "Launching Firefox..."
launch_firefox_to "http://localhost:8080/projects/mobile-banking-app/wiki" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="