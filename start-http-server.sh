#!/bin/bash
#
# Start HTTP server for Druid sample data files
#
# Usage:
#   ./start-http-server.sh [port]
#
# Default port: 8888
#

PORT=${1:-8888}

echo "Starting HTTP server on port $PORT..."
echo "Serving files from: demo/sample-data/"
echo ""
echo "To stop the server: Ctrl+C or kill the process"
echo ""

exec python3 serve-sample-data.py "$PORT"
