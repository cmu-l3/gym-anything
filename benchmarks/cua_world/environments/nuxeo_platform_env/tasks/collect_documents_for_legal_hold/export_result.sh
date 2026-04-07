#!/bin/bash
# Export script for collect_documents_for_legal_hold
# Queries Nuxeo API to inspect the created collection and its members.

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Find the collection "Legal Hold - Acme"
echo "Searching for collection..."
COLLECTION_JSON=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Collection+WHERE+dc:title='Legal+Hold+-+Acme'")

COLLECTION_COUNT=$(echo "$COLLECTION_JSON" | jq '.entries | length')
COLLECTION_UID=$(echo "$COLLECTION_JSON" | jq -r '.entries[0].uid // empty')

echo "Found $COLLECTION_COUNT collection(s). UID: $COLLECTION_UID"

# 3. Get members of the collection
MEMBERS_JSON="[]"
if [ -n "$COLLECTION_UID" ] && [ "$COLLECTION_UID" != "null" ]; then
    # Query collection members
    # Nuxeo stores collection membership via the 'CollectionMember' schema or relationships.
    # The standard way to list members is GET /api/v1/collections/{collectionId}/members
    # Note: endpoint might be /api/v1/id/{id}/@children depending on implementation, 
    # but strictly it's usually `GET /api/v1/collections/{id}/members` or querying the relation.
    # Let's try the specific endpoint first.
    
    MEMBERS_RESP=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/collections/$COLLECTION_UID/members")
    
    # Check if we got a valid response (entries array)
    if echo "$MEMBERS_RESP" | jq -e '.entries' >/dev/null; then
        MEMBERS_JSON=$(echo "$MEMBERS_RESP" | jq '[.entries[] | {title: .properties."dc:title", name: .name, path: .path, type: .type}]')
    else
        # Fallback: Collection members are proxies inside the collection? 
        # Or standard children?
        echo "Trying fallback member fetch..."
        MEMBERS_RESP=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/id/$COLLECTION_UID/@children")
        MEMBERS_JSON=$(echo "$MEMBERS_RESP" | jq '[.entries[] | {title: .properties."dc:title", name: .name, path: .path, type: .type}]')
    fi
fi

# 4. Create Result JSON
cat > /tmp/task_result.json <<EOF
{
  "collection_found": $(if [ -n "$COLLECTION_UID" ]; then echo "true"; else echo "false"; fi),
  "collection_uid": "$COLLECTION_UID",
  "members": $MEMBERS_JSON,
  "timestamp": $(date +%s)
}
EOF

echo "Result JSON generated:"
cat /tmp/task_result.json

# 5. Cleanup permissions
chmod 666 /tmp/task_result.json