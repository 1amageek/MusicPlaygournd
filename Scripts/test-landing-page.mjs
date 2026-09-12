import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const html = await readFile(resolve(root, 'docs/index.html'), 'utf8');
const readme = await readFile(resolve(root, 'README.md'), 'utf8');
const commands = html.match(/<code id="commands">([\s\S]*?)<\/code>/)[1];
assert.ok(readme.includes(commands), 'Install commands must match README exactly');
const ids = new Set([...html.matchAll(/\bid="([^"]+)"/g)].map(m => m[1]));
for (const [, attribute, value] of html.matchAll(/\b(src|href)="([^"]+)"/g)) {
  assert.equal(/\s/.test(value), false, `Invalid URL: ${value}`);
  if (value.startsWith('#')) {
    if (value.length > 1) assert.ok(ids.has(value.slice(1)), `Missing anchor: ${value}`);
  } else if (!value.startsWith('https:')) {
    const url = new URL(value, 'https://example.test/MusicPlaygournd/');
    assert.ok(url.pathname.startsWith('/MusicPlaygournd/'), 'Asset must support a project subpath');
    assert.ok((await stat(resolve(root, 'docs', value))).isFile(), `Missing ${attribute}: ${value}`);
  }
}
const script = await readFile(resolve(root, 'docs/site.js'), 'utf8');
for (const mode of ['success', 'denied', 'unavailable']) {
  let handler;
  let copied;
  const button = { hidden: true, addEventListener: (event, callback) => { assert.equal(event, 'click'); handler = callback; } };
  const status = { textContent: '' };
  const elements = { copy: button, 'copy-status': status, commands: { textContent: commands } };
  const navigator = mode === 'unavailable' ? {} : { clipboard: { writeText: async text => {
    if (mode === 'denied') throw new Error('Permission denied');
    copied = text;
  } } };
  vm.runInNewContext(script, { document: { getElementById: id => elements[id] }, navigator });
  assert.equal(button.hidden, false);
  await handler();
  if (mode === 'success') {
    assert.equal(copied, commands);
    assert.equal(status.textContent, 'Commands copied.');
  } else {
    assert.match(status.textContent, /Select and copy/);
    assert.equal(copied, undefined);
  }
}
console.log('PASS: README commands, local assets, repository subpath, anchors, clipboard success/denied/unavailable');
