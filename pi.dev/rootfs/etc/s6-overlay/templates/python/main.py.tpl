from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
import time

PORT = int(os.getenv("PORT", "8080"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = json.dumps({"app": "{{ PROJECT }}", "status": "ok"}).encode()
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        body = f"Hello from {{ PROJECT }}!\n".encode()
        self.send_response(200)
        self.send_header("content-type", "text/plain")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    print(f"{{ PROJECT }} listening on :{PORT}")
    HTTPServer(("", PORT), Handler).serve_forever()