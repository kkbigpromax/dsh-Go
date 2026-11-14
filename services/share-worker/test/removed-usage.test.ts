import { describe, expect, it } from 'vitest';
import worker from '../src/index';
import { FakeDataset, makeCtx, makeEnv } from './fakes';

describe('removed anonymous usage reporting', () => {
  it('rejects reports even when an old deployment still has usage bindings', async () => {
    const { env, downloads, checks, kv, salts } = makeEnv();
    const retiredUsage = new FakeDataset();
    const legacyEnv = { ...env, USAGE: retiredUsage, USAGE_SECRET: 'synthetic-unused-legacy-secret' };
    for (const method of ['GET', 'POST']) {
      const { ctx, settle } = makeCtx();
      const response = await worker.fetch(new Request('https://go.dshtui.com/api/usage/v1', {
        method,
        ...(method === 'POST' ? {
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ v: 2, iid: 'old-install-id', counts: { turns: 1 } }),
        } : {}),
      }), legacyEnv, ctx);
      await settle();
      expect(response.status).toBe(404);
      expect(await response.json()).toEqual({ error: 'not_found' });
    }
    expect(retiredUsage.points).toEqual([]);
    expect(downloads.points).toEqual([]);
    expect(checks.points).toEqual([]);
    expect(kv.values.size).toBe(0);
    expect(salts.calls).toBe(0);
  });
});
