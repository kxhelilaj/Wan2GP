#!/bin/bash
set -e

echo "=== Wan2GP Container Startup ==="

# Restore application files if needed (handles volume mount scenario)
if [ ! -f "/workspace/Wan2GP/wgp.py" ]; then
    echo "Restoring application files..."
    mkdir -p /workspace/Wan2GP
    rsync -a /opt/wan2gp_source/ /workspace/Wan2GP/
    echo "Application files restored"
else
    echo "Application files already present"
fi

# Set up nginx authentication using RunPod's existing infrastructure
echo "Setting up authentication..."
PASSWORD=${WAN2GP_PASSWORD:-"gpuPoor2025"}
USERNAME=${WAN2GP_USERNAME:-"admin"}

# Verify required tools are available
if ! command -v htpasswd &> /dev/null; then
    echo "❌ ERROR: htpasswd command not found (apache2-utils not installed)"
    exit 1
fi

if ! command -v nginx &> /dev/null; then
    echo "❌ ERROR: nginx command not found"
    echo "RunPod base image may have changed - nginx CLI tools not available"
    exit 1
fi

# Create password file
htpasswd -cb /etc/nginx/.htpasswd "$USERNAME" "$PASSWORD"

# Find RunPod's nginx config and add auth to the 7861 proxy
RUNPOD_NGINX_CONF=$(find /etc/nginx -name "*.conf" -exec grep -l "listen.*7861" {} \; | head -1)

if [ -z "$RUNPOD_NGINX_CONF" ]; then
    echo "❌ ERROR: RunPod nginx config with port 7861 not found!"
    echo "Expected to find nginx config with 'listen 7861' but couldn't locate it."
    echo "This suggests the RunPod base image has changed."
    echo "Please update the Dockerfile to use the correct RunPod base image."
    exit 1
fi

echo "✅ Found RunPod nginx config: $RUNPOD_NGINX_CONF"

# Backup original config
cp "$RUNPOD_NGINX_CONF" "${RUNPOD_NGINX_CONF}.backup"

# Add auth to the existing 7861 server block (keep existing proxy_pass to 7860)
sed -i '/listen 7861;/a\        auth_basic "Wan2GP Access Required";\n        auth_basic_user_file /etc/nginx/.htpasswd;' "$RUNPOD_NGINX_CONF"

# Test nginx config before reloading
if ! nginx -t; then
    echo "❌ ERROR: nginx configuration test failed after adding authentication"
    echo "Restoring original config..."
    cp "${RUNPOD_NGINX_CONF}.backup" "$RUNPOD_NGINX_CONF"
    exit 1
fi

# Reload nginx to apply changes
nginx -s reload
echo "✅ Authentication added to RunPod nginx - Username: $USERNAME, Password: $PASSWORD"
echo "🌐 Access via port 7861 with authentication"

# Start our application in the background
echo "Starting Wan2GP application in background..."
cd /workspace/Wan2GP

# Use RunPod's existing infrastructure: 7861 (nginx with auth) → 7860 (gradio)
SERVER_NAME="127.0.0.1"
SERVER_PORT="7860"
echo "Using RunPod infrastructure: nginx on 7861 → gradio on 7860"

echo "Starting Wan2GP on $SERVER_NAME:$SERVER_PORT"
nohup python3 wgp.py --server-name $SERVER_NAME --server-port $SERVER_PORT > /workspace/wan2gp.log 2>&1 &
echo "Wan2GP started on port $SERVER_PORT, logs in /workspace/wan2gp.log"

# Now chain to RunPod's natural startup process
echo "Starting RunPod services..."
if [ -f "/start.sh" ]; then
    exec /start.sh
else
    echo "No /start.sh found, keeping container alive"
    tail -f /workspace/wan2gp.log
fi 