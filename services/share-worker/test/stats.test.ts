// Counting downloads and update checks, and what is kept: src/stats.ts.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import worker from '../src/index';
import { CHANNEL_PREFIX, channelId, resetChannelMemo } from '../src/beta-auth';
import { resetBetaCache } from '../src/beta';
import type { Env } from '../src/env';
import { deviceCode, nextDayStart, parseUpdaterAgent, resetStatsMemo, statsDay } from '../src/stats';
import { FakeCache, makeCtx, makeEnv } from './fakes';

const ORIGIN = 'https://go.dshtui.com';
// Keep requests, per-day keys, and expected dates on the same test day.
const testNow = Date.parse('2026-10-30T04:00:00Z');
const VERSION = '0.9.8';
const APK = `dsh-go-${VERSION}-arm64.apk`;
const CN = 'https://dshgo-cn.oss-cn-hongkong.aliyuncs.com/';
const TOKEN = 'dshc_' + 'A'.repeat(43);
const IP = '203.0.113.77';
const IP6 = '2001:db8:abcd:12:1111:2222:3333:4444';
const UA = 'Mozilla/5.0 (Linux; Android 14; V2309A) AppleWebKit/537.36 Chrome/126 Mobile Safari/537.36';

const manifest = {
  schema: 1,
  version: `${VERSION}+10301000`,
  publishedAt: '2026-10-30T02:00:00Z',
  notesByLocale: { zh: '- 说明', en: '- notes' },
  routes: ['global', 'cn', 'github'],
  assets: { arm64: { name: APK, size: 10, sha256: 'ab'.repeat(32) } },
};

beforeEach(() => {
  vi.spyOn(Date, 'now').mockReturnValue(testNow);
  resetBetaCache();
  resetChannelMemo();
  resetStatsMemo();
  (globalThis as { caches?: unknown }).caches = { default: new FakeCache() };
});

afterEach(() => {
  vi.restoreAllMocks();
  delete (globalThis as { caches?: unknown }).caches;
});

async function setup(vars: Partial<Env> = {}) {
  const ctx = makeEnv({ BETA_SECRET: 'beta-secret-0123456789abcdef0123456789', CN_BASE_URL: CN, DOWNLOAD_ACCESS: 'public', ...vars });
  const put = (key: string, bytes: Uint8Array) => ctx.bucket.objects.set(key, { bytes, uploaded: new Date(), customMetadata: {} });
  put('beta/update.json', new TextEncoder().encode(JSON.stringify(manifest)));
  put(`beta/${VERSION}/${APK}`, new Uint8Array(10));
  ctx.kv.values.set(CHANNEL_PREFIX + (await channelId(TOKEN)), JSON.stringify({ label: 'app-1' }));
  return ctx;
}

function req(path: string, init: { method?: string; headers?: Record<string, string>; body?: string; ip?: string; country?: string } = {}) {
  const r = new Request(ORIGIN + path, {
    method: init.method ?? 'GET',
    headers: { 'CF-Connecting-IP': init.ip ?? IP, 'User-Agent': UA, ...init.headers },
    body: init.body,
  });
  if (init.country) Object.defineProperty(r, 'cf', { value: { country: init.country } });
  return r;
}

/** Runs the request and whatever it left for after the response. */
async function run(env: Env, request: Request) {
  const { ctx, settle } = makeCtx();
  const res = await worker.fetch(request, env, ctx);
  await settle();
  return res;
}

describe('download buttons', () => {
  it('count the click, then redirect to the route', async () => {
    const { env, downloads } = await setup();
    const expected = { cn: `${CN}${VERSION}/${APK}`, global: `/download/${VERSION}/${APK}`, github: `https://github.com/ccch1mneyyy/dsh-go/releases/download/v${VERSION}/${APK}` };
    for (const [via, location] of Object.entries(expected)) {
      const res = await run(env, req(`/download/get?via=${via}&v=${VERSION}`, { country: 'CN' }));
      expect(res.status, via).toBe(302);
      expect(res.headers.get('Location')).toBe(location);
      expect(res.headers.get('Cache-Control')).toBe('no-store');
    }
    expect(downloads.points.map((p) => p.blobs.slice(0, 4))).toEqual(
      ['cn', 'global', 'github'].map((via) => [statsDay(), via, VERSION, 'CN']),
    );
    // One device, one code (same IP and browser, same day).
    const codes = new Set(downloads.points.map((p) => p.blobs[4]));
    expect(codes.size).toBe(1);
    expect([...codes][0]).toMatch(/^[0-9a-f]{16}$/);
    expect(downloads.points.map((p) => p.indexes[0])).toEqual(['cn', 'global', 'github']);
    expect(downloads.points.every((p) => p.doubles[0] === 1)).toBe(true);
  });

  it("don't count HEAD, stale or made-up links, or floods — but still redirect", async () => {
    const { env, downloads, readLimit } = await setup();
    const head = await run(env, req(`/download/get?via=cn&v=${VERSION}`, { method: 'HEAD' }));
    expect(head.status).toBe(302);
    expect(head.headers.get('Location')).toBe(`${CN}${VERSION}/${APK}`);
    const stale = await run(env, req('/download/get?via=cn&v=0.9.7'));
    expect(stale.headers.get('Location')).toBe('/download?via=cn');
    expect((await run(env, req(`/download/get?via=ftp&v=${VERSION}`))).headers.get('Location')).toBe('/download');
    expect((await run(env, req(`/download/get?via=%22%3E%3Cx&v=${VERSION}`))).headers.get('Location')).toBe('/download');
    expect((await run(env, req('/download/get'))).headers.get('Location')).toBe('/download');
    expect(downloads.points).toHaveLength(0);

    readLimit.allow = 1;
    for (let i = 0; i < 3; i++) expect((await run(env, req(`/download/get?via=global&v=${VERSION}`))).status).toBe(302);
    expect(downloads.points).toHaveLength(1);
    expect(readLimit.keys).toContain(`dlc:${IP}`);
  });

  it('a route that isn\'t offered sends you back to the page', async () => {
    const { env, downloads } = await setup({ CN_BASE_URL: '' });
    expect((await run(env, req(`/download/get?via=cn&v=${VERSION}`))).headers.get('Location')).toBe('/download?via=cn');
    expect(downloads.points).toHaveLength(0);
  });

  it('are 404 in key mode, like the rest of /download', async () => {
    const { env, downloads } = await setup({ DOWNLOAD_ACCESS: 'key' });
    expect((await run(env, req(`/download/get?via=global&v=${VERSION}`))).status).toBe(404);
    expect(downloads.points).toHaveLength(0);
  });

  it('count without a device code when the salt is out of reach', async () => {
    const { env, downloads, salts } = await setup();
    salts.fail = true;
    expect((await run(env, req(`/download/get?via=global&v=${VERSION}`))).status).toBe(302);
    expect(downloads.points[0]!.blobs[4]).toBe('');
  });
});

describe('update checks', () => {
  const check = (headers: Record<string, string> = {}, method = 'GET') =>
    req('/beta/update.json', { method, headers: { Authorization: `Bearer ${TOKEN}`, 'User-Agent': 'dsh-app-updater', ...headers }, country: 'US' });

  it('count what the channel answers, once per request', async () => {
    const { env, checks } = await setup();
    expect((await run(env, check())).status).toBe(200);
    expect((await run(env, check())).status).toBe(200);
    expect(checks.points).toHaveLength(2);
    const [a, b] = checks.points;
    expect(a!.blobs).toEqual([statsDay(), a!.blobs[1], '', '', 'US']);
    expect(a!.blobs[1]).toMatch(/^[0-9a-f]{16}$/);
    expect(b!.blobs[1]).toBe(a!.blobs[1]);
    expect(a!.indexes).toEqual([a!.blobs[1]]);
  });

  it('take the app version and ABI from the User-Agent when it has them', async () => {
    const { env, checks } = await setup();
    await run(env, check({ 'User-Agent': 'dsh-app-updater/0.9.9+10301000 (arm64-v8a)' }));
    expect(checks.points[0]!.blobs.slice(2, 4)).toEqual(['0.9.9+10301000', 'arm64-v8a']);
    expect(parseUpdaterAgent('dsh-app-updater/0.9.9 (mips)')).toEqual({ app: '0.9.9', abi: '' });
    expect(parseUpdaterAgent('curl/8')).toEqual({ app: '', abi: '' });
  });

  it("don't count refused, HEAD or other requests", async () => {
    const { env, checks } = await setup();
    expect((await run(env, req('/beta/update.json'))).status).toBe(401);
    expect((await run(env, check({ Authorization: 'Bearer dshc_' + 'B'.repeat(43) }))).status).toBe(401);
    expect((await run(env, check({}, 'HEAD'))).status).toBe(200);
    expect((await run(env, req(`/beta/${VERSION}/${APK}`, { headers: { Authorization: `Bearer ${TOKEN}` } }))).status).toBe(200);
    expect(checks.points).toHaveLength(0);
  });
});

describe('daily device codes', () => {
  it('stay the same through a day, change with the day, and differ by IP and browser', async () => {
    const { env, salts } = await setup();
    let now = Date.parse('2026-10-30T01:00:00Z');
    salts.now = () => now;
    const code = (ip: string, ua = UA) => deviceCode(env, req('/', { ip, headers: { 'User-Agent': ua } }), now);
    const morning = await code(IP);
    now += 10 * 3600_000;
    expect(await code(IP)).toBe(morning);
    expect(await code('203.0.113.78')).not.toBe(morning);
    expect(await code(IP, 'dsh-app-updater')).not.toBe(morning);
    // IPv6: the /64, like the rate limits.
    expect(await code(IP6)).toBe(await code('2001:db8:abcd:12:9999::1'));
    // 2026-10-31 in UTC+8 starts at 16:00 UTC: a new salt, a new code.
    now = Date.parse('2026-10-30T16:00:01Z');
    const next = await code(IP);
    expect(next).not.toBe(morning);
    expect(next).toMatch(/^[0-9a-f]{16}$/);
    expect(salts.calls).toBe(2);
  });

  it("the salt is random, kept for the day only, and deleted after", async () => {
    const { env, salts } = await setup();
    let now = Date.parse('2026-10-30T01:00:00Z');
    salts.now = () => now;
    await deviceCode(env, req('/'), now);
    const { salt, storage } = salts.objects.get('salt')!;
    const first = (storage.data.get('salt') as { day: string; salt: string });
    expect(first.day).toBe('2026-10-30');
    expect(first.salt).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(storage.alarm).toBe(nextDayStart(now));
    expect(new Date(storage.alarm!).toISOString()).toBe('2026-10-30T16:00:00.000Z');
    // The alarm, a little early: kept; at the day's end: gone.
    now = storage.alarm! - 1000;
    await salt.alarm();
    expect(storage.data.size).toBe(1);
    now = storage.alarm!;
    await salt.alarm();
    expect(storage.data.size).toBe(0);
    // A fresh one the next day, not yesterday's.
    resetStatsMemo();
    await deviceCode(env, req('/'), now);
    expect((storage.data.get('salt') as { salt: string }).salt).not.toBe(first.salt);
  });
});

describe('without Analytics Engine', () => {
  it('downloads and update checks work and count nothing', async () => {
    const { env, salts } = await setup({ DOWNLOADS: undefined, CHECKS: undefined });
    const button = await run(env, req(`/download/get?via=github&v=${VERSION}`));
    expect(button.status).toBe(302);
    expect(button.headers.get('Location')).toBe(`https://github.com/ccch1mneyyy/dsh-go/releases/download/v${VERSION}/${APK}`);
    const feed = await run(env, req('/beta/update.json', { headers: { Authorization: `Bearer ${TOKEN}` } }));
    expect(feed.status).toBe(200);
    expect((await run(env, req('/download'))).status).toBe(200);
    expect(salts.calls).toBe(0);
  });
});

describe('what is kept', () => {
  it('never an IP, an install id or a User-Agent', async () => {
    const { env, downloads, checks, salts, kv } = await setup();
    for (const ip of [IP, IP6]) {
      await run(env, req(`/download/get?via=cn&v=${VERSION}`, { ip, country: 'CN' }));
      await run(env, req('/beta/update.json', { ip, headers: { Authorization: `Bearer ${TOKEN}` } }));
    }
    const kept = JSON.stringify([downloads.points, checks.points, [...salts.objects.values()].map((o) => [...o.storage.data]), [...kv.values]]);
    expect(downloads.points.length + checks.points.length).toBe(4);
    for (const secret of [IP, IP6, '2001:db8:abcd:12', UA, 'V2309A']) expect(kept, secret).not.toContain(secret);
  });
});
