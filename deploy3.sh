#!/bin/bash

# Configuration
PROJECT_NAME="innovationphilly"
DIRECTORY_TO_UPLOAD="./"  # Directory containing your static site content

# Validate environment variables
if [ -z "$CLOUDFLARE_ACCOUNT_ID" ] || [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "Error: CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN environment variables must be set."
    exit 1
fi

# Step 1: Create a new deployment
echo "Creating new deployment..."
CREATE_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$PROJECT_NAME/deployments")

UPLOAD_URL=$(echo "$CREATE_RESPONSE" | jq -r '.result.upload_url')
DEPLOYMENT_ID=$(echo "$CREATE_RESPONSE" | jq -r '.result.id')

if [ "$UPLOAD_URL" == "null" ] || [ -z "$UPLOAD_URL" ]; then
    echo "Failed to create deployment:"
    echo "$CREATE_RESPONSE"
    exit 1
fi

echo "Deployment ID: $DEPLOYMENT_ID"
echo "Upload URL: $UPLOAD_URL"

# Step 2: Create zip of the directory
TEMP_ZIP=$(mktemp)
echo "Zipping site content..."
zip -r "$TEMP_ZIP" "$DIRECTORY_TO_UPLOAD" -x "README.md" "LICENSE" ".git/*" "*.git*" "$(basename "$0")"

# Step 3: Upload the zip file to the presigned upload_url
echo "Uploading zip file to Cloudflare..."
UPLOAD_RESPONSE=$(curl -s -X PUT \
  -T "$TEMP_ZIP" \
  -H "Content-Type: application/zip" \
  "$UPLOAD_URL")

if [ $? -ne 0 ]; then
    echo "Upload failed:"
    echo "$UPLOAD_RESPONSE"
    exit 1
fi

# Step 4: Finalize (optional - Cloudflare may finalize automatically)
echo "Finalizing deployment (optional)..."
FINALIZE_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$PROJECT_NAME/deployments/$DEPLOYMENT_ID/finalize")

echo "Deployment complete."
echo "Deployment ID: $DEPLOYMENT_ID"

# Cleanup
rm -f "$TEMP_ZIP"