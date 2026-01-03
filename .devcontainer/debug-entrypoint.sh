#!/usr/bin/env bash

cat << 'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️   WARNING: DEBUG MODE IS ENABLED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Container status will show 'Up' but services are NOT running.
This is intentional for debugging purposes.

Important:
  - supervisord is NOT started automatically
  - code-server is NOT running
  - Web UI (port 9001) is NOT accessible

To start supervisord manually:
  supervisord -c /etc/supervisor/supervisord.conf

To validate supervisord configuration:
  supervisord -c /etc/supervisor/supervisord.conf -t

To check supervisord status:
  supervisorctl status

To exit debug mode:
  1. Edit docker-compose.yml
  2. Set DEBUG_MODE=false
  3. Restart container: docker-compose restart

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

echo ""
echo "Starting bash shell for debugging..."
echo ""

# Keep container running with bash
exec /bin/bash
