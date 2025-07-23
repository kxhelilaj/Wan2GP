#!/bin/bash

echo "🔧 Setting up nginx authentication for Wan2GP..."

# Check if nginx is installed
if ! command -v nginx &> /dev/null; then
    echo "Installing nginx and password tools..."
    apt update && apt install nginx apache2-utils -y
fi

# Get password from environment or use default
PASSWORD=${WAN2GP_PASSWORD:-"gpuPoor2025"}
USERNAME=${WAN2GP_USERNAME:-"admin"}

# Create password file
htpasswd -cb /etc/nginx/.htpasswd "$USERNAME" "$PASSWORD"

# Create simple nginx config
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

echo "✅ nginx authentication setup complete!"
echo "🔑 Username: $USERNAME"
echo "🔑 Password: $PASSWORD"
echo ""
echo "Now run Wan2GP with:"
echo "python wgp.py --server-name 127.0.0.1 --server-port 7861"
echo ""
echo "Your app will be protected at: http://your-server:7860" 