#!/usr/bin/env node
// Plays the web build in real Chrome (real GPU) and records what a player feels:
// every frame's time from requestAnimationFrame, the browser's long tasks, script
// time and JS heap from the DevTools protocol, and -- with a build that has it --
// the client's own once-a-second [perf] line (objects, nodes, orphans, memory,
// draw calls, entities, bullets, packets). Rows are printed every few seconds and
// the whole run is written as JSON for before/after comparison.
//
//   node tools/web_perf.mjs --account=62 --seconds=120                    idle in the nexus
//   node tools/web_perf.mjs --account=62 --autopilot=beach-hard --seconds=180
//   node tools/web_perf.mjs --build=build/perf ...                         test a local web export
//
// Logs a load-test bot in (~/.gravebound-loadtest/accounts.json) by rewriting the
// page's GODOT_CONFIG args on the way in, so the live page and live servers are
// used unchanged. --build serves index.html and index.pck from a local
// `--export-release "Web"` (same engine, so the live wasm/js still fit), so a
// client change is measured without a release. No dependencies: Node 22+
// (global WebSocket and fetch).
//
// Options: --url --account --seconds --autopilot[=realm] --build --headless
//          --chrome --out --every (seconds per printed row) --cpu-throttle (rate)
//          --uncapped (no vsync: fps = throughput) --profile[=secs] --top=N
//
// The bot always asks for /loadout (max-tier gear, invincible) so it can stand in combat.

import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, resolve } from "node:path";

const args = Object.fromEntries(process.argv.slice(2).map((arg) => {
  const [key, ...rest] = arg.replace(/^--/, "").split("=");
  return [key, rest.length ? rest.join("=") : true];
}));
const url = args.url ?? "https://grave-bound.com/play/";
const seconds = Number(args.seconds ?? 90);
const every = Number(args.every ?? 5);
const chrome = args.chrome ?? "C:/Program Files/Google/Chrome/Application/chrome.exe";
const out = resolve(args.out ?? `build/web-perf-${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
const port = 9300 + Math.floor(Math.random() * 500);

const accounts = JSON.parse(readFileSync(join(homedir(), ".gravebound-loadtest", "accounts.json"), "utf8"));
const account = accounts[Number(args.account ?? 62)];
const gameArgs = ["--", `--email=${account.email}`, `--password=${account.password}`,
  `--character=${account.characterUuid}`, "--perf-log", "--loadout"];
if (args.autopilot) gameArgs.push(args.autopilot === true ? "--autopilot" : `--autopilot=${args.autopilot}`);
const build = args.build ? resolve(args.build) : null;
const pck = build ? readFileSync(join(build, "index.pck")) : null;

const profile = mkdtempSync(join(tmpdir(), "gb-web-perf-"));
const browser = spawn(chrome, [
  `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1600,900",
  "--use-angle=d3d11", "--enable-gpu", "--ignore-gpu-blocklist",
  // A covered or unfocused window must keep drawing at full rate.
  "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
  "--disable-backgrounding-occluded-windows",
  // Uncapped: no vsync or rAF cap, so fps is what the frame actually costs.
  ...(args.uncapped ? ["--disable-gpu-vsync", "--disable-frame-rate-limit"] : []),
  ...(args.headless ? ["--headless=new"] : []), "about:blank",
], { stdio: "ignore" });

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

async function pageSocket() {
  for (let attempt = 0; attempt < 50; attempt++) {
    try {
      const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const page = targets.find((target) => target.type === "page");
      if (page) return page.webSocketDebuggerUrl;
    } catch { /* Chrome is still starting */ }
    await sleep(200);
  }
  throw new Error("Chrome never offered a page target");
}

class Cdp {
  constructor(socket) {
    this.socket = socket;
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Map();
    socket.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (message.id && this.pending.has(message.id)) {
        const { done, fail } = this.pending.get(message.id);
        this.pending.delete(message.id);
        message.error ? fail(new Error(message.error.message)) : done(message.result);
      } else if (message.method) {
        for (const listener of this.listeners.get(message.method) ?? []) listener(message.params);
      }
    });
    // A closed window must end the run with what was recorded, not hang it.
    socket.addEventListener("close", () => {
      this.closed = true;
      for (const { fail } of this.pending.values()) fail(new Error("browser closed"));
      this.pending.clear();
    });
  }

  send(method, params = {}) {
    if (this.closed) return Promise.reject(new Error("browser closed"));
    const id = this.nextId++;
    this.socket.send(JSON.stringify({ id, method, params }));
    return new Promise((done, fail) => this.pending.set(id, { done, fail }));
  }

  on(method, listener) {
    if (!this.listeners.has(method)) this.listeners.set(method, []);
    this.listeners.get(method).push(listener);
  }
}

// Counts frames and long tasks from inside the page, drained once a second.
const SAMPLER = `(() => {
  const perf = window.__gbPerf = { frames: [], longTasks: [] };
  let last = performance.now();
  const frame = (now) => { perf.frames.push(now - last); last = now; requestAnimationFrame(frame); };
  requestAnimationFrame(frame);
  try {
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) perf.longTasks.push(entry.duration);
    }).observe({ type: "longtask", buffered: true });
  } catch { /* no long task API */ }
})();`;
const DRAIN = `(() => {
  const perf = window.__gbPerf;
  if (!perf) return null;
  const sample = { frames: perf.frames, longTasks: perf.longTasks,
    heap: performance.memory ? performance.memory.usedJSHeapSize : 0 };
  perf.frames = []; perf.longTasks = [];
  return sample;
})()`;

function rewritePage(html) {
  let page = html.replace(/"args":\s*\[[^\]]*\]/, `"args":${JSON.stringify(gameArgs)}`);
  if (pck) page = page.replace(/"index\.pck":\s*\d+/, `"index.pck":${pck.length}`);
  return page;
}

const percentile = (sorted, p) => sorted.length ? sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))] : 0;
const round = (value, places = 1) => Math.round(value * 10 ** places) / 10 ** places;

async function main() {
  const socket = new WebSocket(await pageSocket());
  await new Promise((done) => socket.addEventListener("open", done));
  const cdp = new Cdp(socket);
  const consoleLines = [];
  let latestPerf = null;

  cdp.on("Runtime.consoleAPICalled", ({ args: values }) => {
    const text = values.map((value) => value.value ?? value.description ?? "").join(" ");
    if (text.startsWith("[perf] ")) {
      try { latestPerf = JSON.parse(text.slice(7)); } catch { /* partial line */ }
      return;
    }
    consoleLines.push(text);
    if (/error|SCRIPT|\[startup\]/i.test(text)) console.log(`  console: ${text.slice(0, 200)}`);
  });
  cdp.on("Fetch.requestPaused", async ({ requestId, request }) => {
    try {
      const path = new URL(request.url).pathname;
      if (path.endsWith("/play/") || path.endsWith("/index.html")) {
        const html = build ? readFileSync(join(build, "index.html"), "utf8") : await (await fetch(request.url)).text();
        await cdp.send("Fetch.fulfillRequest", { requestId, responseCode: 200,
          responseHeaders: [{ name: "Content-Type", value: "text/html" }, { name: "Cache-Control", value: "no-store" }],
          body: Buffer.from(rewritePage(html)).toString("base64") });
      } else if (pck && path.endsWith("/index.pck")) {
        await cdp.send("Fetch.fulfillRequest", { requestId, responseCode: 200,
          responseHeaders: [{ name: "Content-Type", value: "application/octet-stream" }],
          body: pck.toString("base64") });
      } else {
        await cdp.send("Fetch.continueRequest", { requestId });
      }
    } catch (error) {
      console.log(`  fetch intercept failed for ${request.url}: ${error.message}`);
      await cdp.send("Fetch.continueRequest", { requestId }).catch(() => {});
    }
  });

  await cdp.send("Runtime.enable");
  await cdp.send("Performance.enable");
  await cdp.send("Page.enable");
  await cdp.send("Network.setCacheDisabled", { cacheDisabled: true });
  await cdp.send("Fetch.enable", { patterns: [{ urlPattern: "*/play/*", requestStage: "Request" }] });
  await cdp.send("Page.addScriptToEvaluateOnNewDocument", { source: SAMPLER });
  if (args["cpu-throttle"]) await cdp.send("Emulation.setCPUThrottlingRate", { rate: Number(args["cpu-throttle"]) });
  await cdp.send("Page.navigate", { url });
  console.log(`web perf: ${url} as ${account.email}${args.autopilot ? " (autopilot)" : " (manual: play in the Chrome window)"}${build ? ` with local build ${args.build}` : ""}, ${seconds}s`);

  // Wait for the game to be in a realm: the [perf] line counts a player (us).
  const loadStart = Date.now();
  while (!(latestPerf && latestPerf.players > 0)) {
    if (Date.now() - loadStart > 90_000) throw new Error("never reached a realm in 90s");
    await sleep(500);
  }
  console.log(`  in a realm after ${round((Date.now() - loadStart) / 1000)}s; recording`);
  await cdp.send("Runtime.evaluate", { expression: DRAIN, returnByValue: true });

  // Profiled in chunks so a window closed mid-run keeps everything but the last chunk.
  const perSecond = [];
  let chunkStart = 0;
  if (args.profile) {
    await cdp.send("Profiler.enable");
    await cdp.send("Profiler.setSamplingInterval", { interval: Number(args["sample-us"] ?? 500) });
    await cdp.send("Profiler.start");
  }
  const flushProfile = async (restart) => {
    const { profile: cpu } = await cdp.send("Profiler.stop");
    absorbProfile(cpu, chunkStart, perSecond);
    chunkStart = rows.length;
    if (restart) await cdp.send("Profiler.start");
  };

  const rows = [];
  let window = [];
  let lastMetrics = null;
  console.log("   t  fps   p50   p95   p99   max >33ms longtask script heapMB |  gd.ms worst slow  objects  nodes orphan statMB draws ene bul ply pkts   kB ping jit");
  try {
    for (let second = 1; second <= seconds; second++) {
      await sleep(1000);
      const drained = (await cdp.send("Runtime.evaluate", { expression: DRAIN, returnByValue: true })).result.value;
      const metrics = Object.fromEntries((await cdp.send("Performance.getMetrics")).metrics.map((m) => [m.name, m.value]));
      const scriptMs = lastMetrics ? (metrics.ScriptDuration - lastMetrics.ScriptDuration) * 1000 : 0;
      const taskMs = lastMetrics ? (metrics.TaskDuration - lastMetrics.TaskDuration) * 1000 : 0;
      lastMetrics = metrics;
      const row = { t: second, frames: drained?.frames ?? [], longTasks: drained?.longTasks ?? [],
        heapMb: (metrics.JSHeapUsedSize ?? 0) / 1048576, scriptMs, taskMs, game: latestPerf };
      rows.push(row);
      window.push(row);
      if (second % every === 0) {
        printWindow(window);
        window = [];
      }
      if (args.profile && second % 30 === 0) await flushProfile(second < seconds);
    }
    if (args.profile && chunkStart < rows.length) await flushProfile(false);
  } catch (error) {
    if (!cdp.closed) throw error;
    console.log(`  browser closed at t=${rows.length}s; reporting what was recorded`);
  }
  if (!rows.length) throw new Error("nothing recorded");
  const all = rows.flatMap((row) => row.frames).sort((a, b) => a - b);
  const summary = {
    seconds: rows.length, url, autopilot: args.autopilot ?? false, localBuild: args.build ?? false,
    fps: round(all.length / rows.length), p50: round(percentile(all, 0.5), 2), p95: round(percentile(all, 0.95), 2),
    p99: round(percentile(all, 0.99), 2), max: round(all[all.length - 1] ?? 0, 2),
    over33: all.filter((ms) => ms > 33.4).length, over50: all.filter((ms) => ms > 50).length,
    longTaskMs: round(rows.reduce((sum, row) => sum + row.longTasks.reduce((a, b) => a + b, 0), 0)),
    heapStartMb: round(rows[0]?.heapMb ?? 0), heapEndMb: round(rows.at(-1)?.heapMb ?? 0),
    objectsStart: rows[0]?.game?.objects, objectsEnd: rows.at(-1)?.game?.objects,
    nodesStart: rows[0]?.game?.nodes, nodesEnd: rows.at(-1)?.game?.nodes,
  };
  console.log("summary", JSON.stringify(summary));
  if (args.profile && perSecond.length) reportProfile(perSecond, rows);
  writeFileSync(out, JSON.stringify({ summary, rows: rows.map((row) => ({ ...row, frames: row.frames.map((ms) => round(ms, 2)) })),
    console: consoleLines.slice(-500) }, null, 1));
  console.log(`wrote ${out}`);
}

// Where the main thread's time went, by bucket, for a typical second against the
// seconds with the most dropped frames -- what grows in a bad second is the cause.
// The release wasm is stripped, so engine and GDScript time is one "wasm" bucket;
// the browser-side buckets (WebGL calls, the canvas blit, GC) are named.
function bucketOf(frame) {
  const name = frame.functionName;
  if (name === "(garbage collector)") return "gc";
  if (name === "(idle)") return "idle";
  if (name === "(program)") return "browser (program)";
  if (name === "getParameter" || name === "blitOffscreenFramebuffer") return "canvas blit (commit_frame)";
  if (/^wasm-function/.test(name) || name === "wasm-to-js" || /^js-to-wasm/.test(name)) return "wasm (engine + GDScript)";
  if (/^(get|tex|draw|bind|buffer|uniform|vertexAttrib|enable|disable|blend|use|clear|viewport|scissor|fenceSync|clientWaitSync|readPixels|framebuffer|invalidate|delete|create|compile|link|shader|copy|active|pixelStorei|depth|color|stencil|cull|front|line|polygon)/.test(name)) return "webgl calls";
  if (/_emscripten_gl|_gl[A-Z]/.test(name)) return "webgl glue";
  if (frame.url && /index\.js$/.test(frame.url)) return "emscripten js";
  return `other: ${name || "(anonymous)"}`;
}

// Adds one profile chunk's samples to per-second bucket totals (us), from the
// chunk's first recorded second; the latest chunk is also kept as a .cpuprofile.
function absorbProfile(cpu, firstSecond, perSecond) {
  writeFileSync(out.replace(/\.json$/, ".cpuprofile"), JSON.stringify(cpu));
  const nodes = new Map(cpu.nodes.map((node) => [node.id, node]));
  let clock = cpu.startTime;
  cpu.samples.forEach((id, index) => {
    const delta = cpu.timeDeltas[index + 1] ?? 0;
    clock += cpu.timeDeltas[index];
    const second = firstSecond + Math.floor((clock - cpu.startTime) / 1e6);
    const bucket = bucketOf(nodes.get(id).callFrame);
    perSecond[second] ??= new Map();
    perSecond[second].set(bucket, (perSecond[second].get(bucket) ?? 0) + delta);
  });
}

function reportProfile(perSecond, rows) {
  const drops = (row) => row.frames.filter((ms) => ms > 33.4).length;
  const ranked = rows.map((row, index) => ({ index, drops: drops(row), fps: row.frames.length }))
    .sort((a, b) => b.drops - a.drops);
  const worst = ranked.filter((entry) => entry.drops > 0).slice(0, 5);
  const calm = ranked.filter((entry) => entry.drops === 0).map((entry) => entry.index);
  const average = (indices) => {
    const sums = new Map();
    for (const index of indices) for (const [bucket, us] of perSecond[index] ?? []) sums.set(bucket, (sums.get(bucket) ?? 0) + us);
    return new Map([...sums].map(([bucket, us]) => [bucket, us / 1000 / Math.max(1, indices.length)]));
  };
  const calmAverage = average(calm);
  const worstAverage = average(worst.map((entry) => entry.index));
  const buckets = [...new Set([...calmAverage.keys(), ...worstAverage.keys()])]
    .sort((a, b) => (worstAverage.get(b) ?? calmAverage.get(b) ?? 0) - (worstAverage.get(a) ?? calmAverage.get(a) ?? 0)).slice(0, 14);
  console.log(`  main thread ms per second: ${calm.length} calm seconds vs worst ${worst.length} (t=${worst.map((e) => `${e.index + 1}:${e.drops}drops/${e.fps}fps`).join(" ")})`);
  for (const bucket of buckets) {
    const calmMs = calmAverage.get(bucket) ?? 0;
    const worstMs = worstAverage.get(bucket) ?? 0;
    console.log(`  ${calmMs.toFixed(0).padStart(6)} ${worstMs.toFixed(0).padStart(6)} ${(worstMs - calmMs >= 0 ? "+" : "") + (worstMs - calmMs).toFixed(0).padStart(5)}  ${bucket}`);
  }
}

function printWindow(rows) {
  const frames = rows.flatMap((row) => row.frames).sort((a, b) => a - b);
  const game = rows.at(-1).game ?? {};
  const sum = (key) => rows.reduce((total, row) => total + (row.game?.[key] ?? 0), 0);
  const cells = [
    String(rows.at(-1).t).padStart(4), round(frames.length / rows.length).toFixed(0).padStart(4),
    round(percentile(frames, 0.5)).toFixed(1).padStart(5), round(percentile(frames, 0.95)).toFixed(1).padStart(5),
    round(percentile(frames, 0.99)).toFixed(1).padStart(5), round(frames.at(-1) ?? 0).toFixed(0).padStart(5),
    String(frames.filter((ms) => ms > 33.4).length).padStart(5),
    round(rows.reduce((t, row) => t + row.longTasks.reduce((a, b) => a + b, 0), 0) / rows.length).toFixed(0).padStart(8),
    round(rows.reduce((t, row) => t + row.scriptMs, 0) / rows.length).toFixed(0).padStart(6),
    round(rows.at(-1).heapMb).toFixed(1).padStart(6), "|",
    String(game.process_ms ?? "").padStart(6), String(game.worst_ms ?? "").padStart(5), String(sum("slow_frames")).padStart(4),
    String(game.objects ?? "").padStart(8), String(game.nodes ?? "").padStart(6), String(game.orphans ?? "").padStart(6),
    String(game.static_mb ?? "").padStart(6), String(game.draw_calls ?? "").padStart(5),
    String(game.enemies ?? "").padStart(3), String(game.bullets ?? "").padStart(3), String(game.players ?? "").padStart(3),
    String(Math.round(sum("packets") / rows.length)).padStart(4), String(round(sum("kbytes") / rows.length)).padStart(5),
    String(game.ping_ms ?? "").padStart(4), String(game.jitter_ms ?? "").padStart(3),
  ];
  console.log(cells.join(" "));
}

try {
  await main();
} catch (error) {
  console.error(`web perf failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  browser.kill();
  await sleep(500);
  try { rmSync(profile, { recursive: true, force: true }); } catch { /* Chrome still holds a lock */ }
}
