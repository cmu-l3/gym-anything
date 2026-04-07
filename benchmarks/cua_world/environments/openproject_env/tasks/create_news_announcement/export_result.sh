#!/bin/bash
echo "=== Exporting create_news_announcement results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query OpenProject database via Rails runner to find the news item
# We look for the most recent news item in the project created after task start
echo "Querying OpenProject for news items..."

RUBY_QUERY="
require 'json'
begin
  project = Project.find_by(identifier: 'mobile-banking-app')
  if project.nil?
    puts JSON.generate({found: false, error: 'Project not found'})
    exit
  end

  # Find news items created after task start
  # Note: Ruby Time.at takes seconds
  task_start = Time.at($TASK_START)
  
  # Get the most recent news item in this project
  news = News.where(project: project)
             .where('created_on >= ?', task_start)
             .order(created_on: :desc)
             .first

  if news
    puts JSON.generate({
      found: true,
      id: news.id,
      title: news.title,
      summary: news.summary,
      description: news.description,
      created_on: news.created_on.to_i,
      author: news.author.name
    })
  else
    # Fallback: check if ANY news exists with similar title, even if timestamp is off 
    # (to give specific feedback about anti-gaming or time issues)
    similar = News.where(project: project)
                  .where('title LIKE ?', '%Security Compliance%')
                  .order(created_on: :desc)
                  .first
    
    if similar
      puts JSON.generate({
        found: false, 
        error: 'News found but timestamp too old (anti-gaming)',
        found_timestamp: similar.created_on.to_i,
        task_start: $TASK_START
      })
    else
      puts JSON.generate({found: false, error: 'No matching news item found'})
    end
  end
rescue => e
  puts JSON.generate({found: false, error: e.message})
end
"

# Run the query and save to JSON
# We use docker exec directly to ensure we capture stdout cleanly
docker exec openproject bash -c "cd /app && bundle exec rails runner \"$RUBY_QUERY\"" > /tmp/task_result.json 2>/dev/null

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json

echo "=== Export complete ==="