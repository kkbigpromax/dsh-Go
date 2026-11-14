// Locked, patched engine modules and the real request-extension registry.
// All messages and credentials are synthetic; fetch is intercepted locally.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import test from 'node:test';
import { pathToFileURL } from 'node:url';
import vm from 'node:vm';

const prefix = process.env.DSH_TEST_PREFIX ?? process.env.DSH_PREFIX;
assert.ok(prefix, 'set DSH_TEST_PREFIX to the locked, patched runtime');
const base = join(resolve(prefix), 'node_modules/@deepseek-ai');
const load = name => import(pathToFileURL(join(base, name, 'lib/index.js')));
const [{ Context }, { default: Extensions }, uploader, { DeepSeekAdapter, resolveAdapterOptions }] =
  await Promise.all([load('cordis'), load('dsh-deepseek-llm-api-extensions'),
    load('dsh-session-log-deepseek'), load('dsh-llm-deepseek')]);

test('old enabled preferences cannot add session logs to a model request', async t => {
  const ctx = new Context();
  t.after(() => ctx.fiber.dispose());
  await ctx.plugin(Extensions);
  let sessionReads = 0;
  ctx.provide('sessions', { get() { sessionReads++; throw Error('Log records must not be read'); } });
  await uploader.apply(ctx, { enabled: { get: () => true }, maxBytes: 8 * 1024 * 1024 });
  ctx.deepseekLlmApiExtensions.register('synthetic_extension', {
    prepare: () => ({ value: 'kept' }),
  });

  const requests = [];
  t.mock.method(globalThis, 'fetch', async (_url, init) => {
    requests.push(JSON.parse(init.body));
    const events = [
      { type: 'message_start', message: { id: 'synthetic-reply', type: 'message', role: 'assistant',
        model: 'synthetic-model', content: [], stop_reason: null, usage: { input_tokens: 1, output_tokens: 0 } } },
      { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
      { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'synthetic reply' } },
      { type: 'content_block_stop', index: 0 },
      { type: 'message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 2 } },
      { type: 'message_stop' },
    ];
    return new Response(events.map(event => `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`).join(''), {
      headers: { 'Content-Type': 'text/event-stream' },
    });
  });
  const options = resolveAdapterOptions({
    baseURL: 'https://synthetic-model.invalid/v1', thinking: 'disabled', maxTokens: 64,
    models: [{ id: 'synthetic-model', inputModalities: ['text'] }],
  });
  const adapter = new DeepSeekAdapter({
    options: () => options,
    resolveAuth: async () => ({ headers: { authorization: 'Bearer synthetic-not-a-credential' } }),
    resolveUserId: () => 'synthetic-user',
    prepareExtensions: request => ctx.deepseekLlmApiExtensions.prepare(request),
  });
  const chunks = [];
  for await (const chunk of adapter.stream({
    provider: 'synthetic', model: 'synthetic-model', sessionId: 'old-session-with-logs',
    messages: [{ role: 'user', content: [{ type: 'text', text: 'synthetic question' }] }],
  })) chunks.push(chunk);

  assert.equal(requests.length, 1);
  assert.equal(Object.hasOwn(requests[0], 'dsh_session_log'), false);
  assert.equal(requests[0].synthetic_extension, 'kept');
  assert.match(JSON.stringify(requests[0].messages), /synthetic question/);
  assert.match(JSON.stringify(chunks), /synthetic reply/);
  assert.equal(sessionReads, 0);
  assert.equal(ctx.get('sessionLogDeepSeek'), undefined);
});

test('the default bundles do not load either upload entry', async () => {
  const core = await readFile(join(base, 'dsh-base/cordis.patch.yml'), 'utf8');
  const web = await readFile(join(base, 'dsh-web-app/cordis.patch.yml'), 'utf8');
  assert.doesNotMatch(core, /id: session-log-deepseek\b/);
  assert.doesNotMatch(web, /id: ui-settings-session-log\b/);
});

test('a browser loading the old module gets no switch, notice or setting writes', async () => {
  let module;
  vm.runInNewContext(await readFile(join(base, 'dsh-client-ui-settings-session-log/lib/client.js'), 'utf8'), {
    window: { __ModuleLoader__: { load(value) { module = value; } } },
  });
  const plugin = module.factory();
  assert.equal(plugin.inject.length, 0);
  plugin.apply(new Proxy({}, { get() { assert.fail('Removed UI must not access host services'); } }));
});

test('the secondary JS entry is inert as well', async () => {
  const plugin = await import(pathToFileURL(join(base, 'dsh-session-log-deepseek/lib/types/index.js')));
  plugin.apply(new Proxy({}, { get() { assert.fail('Removed uploader must not access services'); } }));
  assert.deepEqual(plugin.inject, []);
});
