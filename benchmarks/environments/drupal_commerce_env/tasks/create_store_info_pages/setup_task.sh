# Record initial node count
INITIAL_NODE_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM node_field_data WHERE type='page'")
echo "$INITIAL_NODE_COUNT" > /tmp/initial_page_count.txt

# Record initial footer menu link count
INITIAL_MENU_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM menu_link_content_data WHERE menu_name='footer'")
echo "$INITIAL_MENU_COUNT" > /tmp/initial_footer_menu_count.txt

# Record task start timestamp
date +%s > /tmp/task_start_time.txt