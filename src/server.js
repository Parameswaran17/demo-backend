'use strict';
const http = require('http');

const PORT = process.env.PORT || 3000;
const COMMIT = process.env.APP_COMMIT || 'dev';
const STARTED = new Date().toISOString();

function handler(req, res) {
  const send = (code, body) => {
    res.writeHead(code, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(body));
  };

  if (req.url === '/api/health') return send(200, { status: 'ok' });
  if (req.url === '/api/version') return send(200, { service: 'backend', commit: COMMIT, started: STARTED });
  if (req.url === '/api/message') return send(200, { message: 'Hello from the backend v2!', commit: COMMIT });
  return send(404, { error: 'not found' });
}

if (require.main === module) {
  http.createServer(handler).listen(PORT, () => console.log(`backend ${COMMIT} listening on :${PORT}`));
}
module.exports = { handler };
// trigger build
