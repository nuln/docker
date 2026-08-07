import { createServer } from "node:http";

const port = Number(process.env.PORT ?? 8080);

const server = createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ app: "{{ PROJECT }}", status: "ok" }));
    return;
  }
  res.writeHead(200, { "content-type": "text/plain" });
  res.end(`Hello from {{ PROJECT }}!\n`);
});

server.listen(port, () => {
  console.log(`{{ PROJECT }} listening on :${port}`);
});