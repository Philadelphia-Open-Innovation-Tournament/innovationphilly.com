#!/bin/bash

# Configuration
PROJECT_NAME="innovationphilly"
DIRECTORY_TO_UPLOAD="./"  # Directory containing your index.html

# Validate environment variables
if [ -z "$CLOUDFLARE_ACCOUNT_ID" ] || [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "Error: CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN environment variables must be set."
    exit 1
fi

# Create a temporary directory for the upload
TEMP_DIR=$(mktemp -d)
echo "Created temporary directory: $TEMP_DIR"

# Zip the contents of the directory
# Exclude the README.md, LICENSE, .gitignore file and the .git folder
echo "Zipping files..."
zip -r "$TEMP_DIR/upload.zip" "$DIRECTORY_TO_UPLOAD" -x "README.md" "LICENSE" ".gitignore" ".git/*" "*.git*" "$TEMP_DIR/*"

# Get the contents of the zip as base64 and save to a file
# This avoids the "Argument list too long" error
echo "Encoding zip file to base64..."
base64 "$TEMP_DIR/upload.zip" > "$TEMP_DIR/upload.base64"

# Construct the API URL
API_URL="https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$PROJECT_NAME/deployments"

# Create a JSON template file with the required "manifest" field
cat > "$TEMP_DIR/payload_template.json" <<EOF
{
  "production": true,
  "manifest": {
    "version": 1,
    "main_asset": "index.html"
  },
  "deployment_configs": {
    "production": {
      "environment": {
        "files": {
          "upload.zip": {
            "contentType": "application/zip",
            "base64": "BASE64_CONTENT"
          }
        }
      }
    }
  }
}
EOF

# Use jq to replace the base64 content
echo "Using jq to create payload..."
jq --rawfile b64 "$TEMP_DIR/upload.base64" '.deployment_configs.production.environment.files."upload.zip".base64 = $b64' \
    "$TEMP_DIR/payload_template.json" > "$TEMP_DIR/payload.json"

# Send the API request using the payload file
echo "Sending deployment request to Cloudflare..."
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @"$TEMP_DIR/payload.json" \
  "$API_URL")

# Store curl exit code
CURL_EXIT_CODE=$?

# Output the response
echo "API Response:"
echo "$RESPONSE"

# Cleanup the temporary directory
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

# Check the exit code of curl to determine success or failure.
if [ $CURL_EXIT_CODE -eq 0 ]; then
    if echo "$RESPONSE" | grep -q '"success":true'; then
        echo "Deployment successful."
        exit 0
    else
        echo "Deployment failed. See API response for details."
        exit 1
    fi
else
    echo "Deployment failed with curl exit code: $CURL_EXIT_CODE"
    exit $CURL_EXIT_CODE
fi
