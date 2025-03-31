#!/bin/bash

set -e

# Configuration
PROJECT_NAME="innovationphilly"
DIRECTORY_TO_UPLOAD="./"

# Check environment variables
if [ -z "$CLOUDFLARE_ACCOUNT_ID" ] || [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "Missing CLOUDFLARE_ACCOUNT_ID or CLOUDFLARE_API_TOKEN"
    exit 1
fi

# Temp files
MANIFEST_JSON=$(mktemp)
FILES_JSON=$(mktemp)

echo "{}" > "$MANIFEST_JSON"
echo "{}" > "$FILES_JSON"

echo "Creating new deployment..."
CREATE_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$PROJECT_NAME/deployments")

UPLOAD_URL=$(echo "$CREATE_RESPONSE" | jq -r '.result.upload_url')
DEPLOYMENT_ID=$(echo "$CREATE_RESPONSE" | jq -r '.result.id')

if [ "$UPLOAD_URL" == "null" ] || [ -z "$UPLOAD_URL" ]; then
    echo "Error creating deployment:"
    echo "$CREATE_RESPONSE"
    exit 1
fi

echo "Uploading files to: $UPLOAD_URL"

# Upload all files individually
while IFS= read -r -d '' FILE; do
    RELATIVE_PATH="${FILE#$DIRECTORY_TO_UPLOAD}"
    RELATIVE_PATH="${RELATIVE_PATH#/}"

    HASH=$(openssl dgst -sha256 "$FILE" | awk '{print $2}')
    SIZE=$(stat -c %s "$FILE")

    # Upload the file
    DEST="$UPLOAD_URL/$RELATIVE_PATH"
    curl -s --fail -X PUT --data-binary @"$FILE" "$DEST" > /dev/null

    # Update manifest
    jq --arg path "/$RELATIVE_PATH" --arg hash "$HASH" --argjson size "$SIZE" \
        '. + {($path): {"etag": $hash, "size": $size}}' \
        "$MANIFEST_JSON" > "$MANIFEST_JSON.tmp" && mv "$MANIFEST_JSON.tmp" "$MANIFEST_JSON"

done < <(find "$DIRECTORY_TO_UPLOAD" -type f -print0)

# Finalize deployment with manifest
FINALIZE_URL="https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$PROJECT_NAME/deployments/$DEPLOYMENT_ID/finalize"

echo "Finalizing deployment..."
FINALIZE_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"manifest\": $(cat "$MANIFEST_JSON")}" \
    "$FINALIZE_URL")

echo "Deployment finalized:"
echo "$FINALIZE_RESPONSE"

# Cleanup
rm "$MANIFEST_JSON" "$FILES_JSON"