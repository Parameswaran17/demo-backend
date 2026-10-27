'use strict';
const test = require('node:test');
const assert = require('node:assert');
const http = require('http');
const { handler } = require('../src/server');

function get(server, path) {
  return new Promise((resolve, reject) => {
    http.get({ port: server.address().port, path }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(data) }));
    }).on('error', reject);
  });
}

test('API endpoints', async (t) => {
  const server = http.createServer(handler).listen(0);
  t.after(() => server.close());

  const health = await get(server, '/api/health');
  assert.strictEqual(health.status, 200);
  assert.strictEqual(health.body.status, 'ok');

  const msg = await get(server, '/api/message');
  assert.strictEqual(msg.status, 200);
  assert.ok(msg.body.message);

  const missing = await get(server, '/nope');
  assert.strictEqual(missing.status, 404);
});
