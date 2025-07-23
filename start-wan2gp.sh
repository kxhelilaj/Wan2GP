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

# Set up nginx authentication
echo "Setting up authentication..."
PASSWORD=${WAN2GP_PASSWORD:-"gpuPoor2025"}
USERNAME=${WAN2GP_USERNAME:-"admin"}

# Create password file
htpasswd -cb /etc/nginx/.htpasswd "$USERNAME" "$PASSWORD"

# Create nginx config for auth proxy
cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 7860;
    server_name localhost;
    
    # Basic authentication
    auth_basic "Wan2GP Access Required";
    auth_basic_user_file /etc/nginx/.htpasswd;
    
    # Proxy to Gradio on internal port
    location / {
        proxy_pass http://127.0.0.1:7861;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        
        # WebSocket support for Gradio
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# Start nginx
service nginx start
echo "✅ Authentication enabled - Username: $USERNAME, Password: $PASSWORD"

# Start our application in the background on internal port
echo "Starting Wan2GP application in background..."
cd /workspace/Wan2GP
nohup python3 wgp.py --server-name 127.0.0.1 --server-port 7861 > /workspace/wan2gp.log 2>&1 &
echo "Wan2GP started on internal port 7861, logs in /workspace/wan2gp.log"

# Now chain to RunPod's natural startup process
echo "Starting RunPod services..."
if [ -f "/start.sh" ]; then
    exec /start.sh
else
    echo "No /start.sh found, keeping container alive"
    tail -f /workspace/wan2gp.log
fi 