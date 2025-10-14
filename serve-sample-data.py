#!/usr/bin/env python3
"""
HTTP Server for Druid Sample Data Files

This script serves files from the demo/sample-data directory
so Druid can ingest them via HTTP.

Usage:
    python3 serve-sample-data.py [port]

Default port: 8888

Example:
    python3 serve-sample-data.py          # Runs on port 8888
    python3 serve-sample-data.py 9000     # Runs on port 9000
"""

import os
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from functools import partial

# Configuration
DEFAULT_PORT = 8888
SAMPLE_DATA_DIR = "demo/sample-data"


class CustomHTTPRequestHandler(SimpleHTTPRequestHandler):
    """Custom handler with better logging"""

    def log_message(self, format, *args):
        """Override to add colored output"""
        print(f"[HTTP] {self.address_string()} - {format % args}")

    def end_headers(self):
        """Add CORS headers for cross-origin requests"""
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        SimpleHTTPRequestHandler.end_headers(self)


def main():
    # Get port from command line or use default
    port = DEFAULT_PORT
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print(f"Error: Invalid port number '{sys.argv[1]}'")
            print(f"Usage: {sys.argv[0]} [port]")
            sys.exit(1)

    # Get script directory
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Change to sample-data directory
    sample_data_path = os.path.join(script_dir, SAMPLE_DATA_DIR)

    if not os.path.exists(sample_data_path):
        print(f"Error: Sample data directory not found: {sample_data_path}")
        sys.exit(1)

    os.chdir(sample_data_path)

    # List available files
    files = [f for f in os.listdir('.') if os.path.isfile(f)]

    # Create server
    handler = partial(CustomHTTPRequestHandler)
    server = HTTPServer(('0.0.0.0', port), handler)

    # Print startup info
    print("=" * 70)
    print("🚀 Druid Sample Data HTTP Server")
    print("=" * 70)
    print(f"📁 Serving directory: {sample_data_path}")
    print(f"🌐 Server running at: http://localhost:{port}/")
    print(f"🌐 Network address:   http://0.0.0.0:{port}/")
    print("=" * 70)
    print(f"📄 Available files ({len(files)}):")
    for f in sorted(files):
        file_size = os.path.getsize(f)
        print(f"   - http://localhost:{port}/{f} ({file_size} bytes)")
    print("=" * 70)
    print("\n💡 Usage in Druid:")
    print(f"   1. Open Druid Console: http://localhost:31888")
    print(f"   2. Load data → HTTP")
    print(f"   3. URI: http://localhost:{port}/<filename>")
    print(f"   Example: http://localhost:{port}/two-partition-demo.json")
    print("\n⚠️  Press Ctrl+C to stop the server\n")
    print("=" * 70)

    # Start server
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n\n🛑 Server stopped by user")
        server.shutdown()
        sys.exit(0)


if __name__ == "__main__":
    main()
