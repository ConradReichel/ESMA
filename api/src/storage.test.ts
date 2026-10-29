import assert from 'node:assert/strict';
import { createServer, IncomingMessage, ServerResponse } from 'node:http';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { createStorage } from './storage';

const originalEnv = { ...process.env };
let temporaryDirectory = '';
let s3Server: ReturnType<typeof createServer>;
let s3Address: string;
const objects = new Map<string, Buffer>();

function restoreEnv(): void {
  for (const key of Object.keys(process.env)) if (!(key in originalEnv)) delete process.env[key];
  Object.assign(process.env, originalEnv);
}

function respond(request: IncomingMessage, response: ServerResponse): void {
  const chunks: Buffer[] = [];
  request.on('data', (chunk: Buffer) => chunks.push(Buffer.from(chunk)));
  request.on('end', () => {
    const key = new URL(request.url || '/', 'http://localhost').pathname.replace(/^\/esma-test\//, '');
    if (request.method === 'PUT') {
      objects.set(key, Buffer.concat(chunks)); response.writeHead(200).end();
    } else if (request.method === 'GET' && objects.has(key)) {
      response.writeHead(200, { 'content-type': 'application/octet-stream' }).end(objects.get(key));
    } else if (request.method === 'DELETE') {
      objects.delete(key); response.writeHead(204).end();
    } else {
      response.writeHead(404, { 'content-type': 'application/xml' }).end('<Error><Code>NoSuchKey</Code></Error>');
    }
  });
}

before(async () => {
  temporaryDirectory = await mkdtemp(join(tmpdir(), 'esma-storage-'));
  s3Server = createServer(respond);
  await new Promise<void>((resolve) => s3Server.listen(0, '127.0.0.1', resolve));
  const address = s3Server.address();
  if (!address || typeof address === 'string') throw new Error('Test S3 server did not bind.');
  s3Address = `http://127.0.0.1:${address.port}`;
});

after(async () => {
  restoreEnv();
  await rm(temporaryDirectory, { recursive: true, force: true });
  await new Promise<void>((resolve, reject) => s3Server.close((error) => error ? reject(error) : resolve()));
});

test('local driver stores, replaces, reads and deletes an image', async () => {
  process.env.STORAGE_DRIVER = 'local';
  process.env.LOCAL_STORAGE_PATH = temporaryDirectory;
  const storage = createStorage();
  await storage.put('image-id', Buffer.from('first'), 'image/png');
  assert.equal((await storage.get('image-id'))?.toString(), 'first');
  await storage.put('image-id', Buffer.from('replacement'), 'image/jpeg');
  assert.equal((await readFile(join(temporaryDirectory, 'image-id'))).toString(), 'replacement');
  await storage.delete('image-id');
  assert.equal(await storage.get('image-id'), null);
});

test('S3 driver stores, replaces, reads and deletes an image', async () => {
  process.env.STORAGE_DRIVER = 's3';
  process.env.S3_ENDPOINT = s3Address;
  process.env.S3_REGION = 'test-1';
  process.env.S3_BUCKET = 'esma-test';
  process.env.S3_ACCESS_KEY_ID = 'test-key';
  process.env.S3_SECRET_ACCESS_KEY = 'test-secret';
  process.env.S3_FORCE_PATH_STYLE = 'true';
  const storage = createStorage();
  await storage.put('image-id', Buffer.from('first'), 'image/png');
  assert.equal((await storage.get('image-id'))?.toString(), 'first');
  await storage.put('image-id', Buffer.from('replacement'), 'image/jpeg');
  assert.equal((await storage.get('image-id'))?.toString(), 'replacement');
  await storage.delete('image-id');
  assert.equal(await storage.get('image-id'), null);
});

test('unknown drivers and incomplete provider configuration fail clearly', () => {
  process.env.STORAGE_DRIVER = 'unknown';
  assert.throws(() => createStorage(), /STORAGE_DRIVER muss local, s3 oder azure-blob sein/);
  process.env.STORAGE_DRIVER = 's3';
  delete process.env.S3_ENDPOINT;
  assert.throws(() => createStorage(), /S3_ENDPOINT fehlt/);
  process.env.STORAGE_DRIVER = 'azure-blob';
  delete process.env.AZURE_STORAGE_CONNECTION_STRING;
  assert.throws(() => createStorage(), /AZURE_STORAGE_CONNECTION_STRING fehlt/);
});
