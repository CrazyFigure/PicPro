/**
 * Web 产物运行检查：用无头 Chromium 实际加载页面，验证内核能否初始化。
 *
 * 为什么需要它：
 * Web 端的问题（MIME 类型丢失、WASM 加载脚本重复引入、跨源隔离不可用）
 * 全都「构建成功 + 静态检查通过」也照样存在，只有真正加载页面才会暴露。
 * 本项目已在真实部署中连续踩到过这三类问题，因此把检查固化下来。
 *
 * 检查内容：
 *   1. 页面加载后无 panic、无未捕获异常；
 *   2. 跨源隔离状态（crossOriginIsolated）是否符合预期；
 *   3. Flutter 引擎宿主节点是否出现（说明引擎已启动）；
 *   4. 输出截图，便于目视确认界面真的渲染出来了。
 *
 * 用法：
 *   node scripts/check_web.mjs <url> [截图输出路径]
 *
 * 典型用法（复现「纯 HTTP 公网访问」的场景）：
 *   # 1. 把产物绑到局域网地址提供服务
 *   python deploy/local_preview.py "" 0.0.0.0 8200
 *   # 2. 用局域网 IP 访问 —— 该来源不可信，浏览器会忽略 COOP/COEP
 *   node scripts/check_web.mjs http://192.168.1.10:8200/ shot.png
 *
 * 退出码：0 = 通过，1 = 未通过。
 */

import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';

const URL_TO_TEST = process.argv[2];
const SHOT_PATH = process.argv[3] ?? 'web-check-screenshot.png';
const PORT = 9333;

if (!URL_TO_TEST) {
  console.error('用法: node scripts/check_web.mjs <url> [截图输出路径]');
  process.exit(2);
}

/** 在 ms-playwright 缓存中查找 Chromium 可执行文件，避免写死版本号。 */
function findChrome() {
  const base = join(homedir(), 'AppData', 'Local', 'ms-playwright');
  if (!existsSync(base)) return null;
  const dirs = readdirSync(base)
    .filter((d) => d.startsWith('chromium-'))
    .sort()
    .reverse();
  for (const d of dirs) {
    const exe = join(base, d, 'chrome-win64', 'chrome.exe');
    if (existsSync(exe)) return exe;
  }
  return null;
}

const CHROME = process.env.CHROME_PATH ?? findChrome();
if (!CHROME || !existsSync(CHROME)) {
  console.error(
    '找不到 Chromium。可设置环境变量 CHROME_PATH 指向 chrome.exe，\n' +
      '或先执行 `npx playwright install chromium` / `agent-browser install`。',
  );
  process.exit(2);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** 极简 CDP 客户端，仅用到本脚本所需的少量命令。 */
class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.id = 0;
    this.pending = new Map();
    this.handlers = [];
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result);
      } else if (msg.method) {
        this.handlers.forEach((h) => h(msg));
      }
    });
  }
  send(method, params = {}, sessionId) {
    const id = ++this.id;
    const payload = { id, method, params };
    if (sessionId) payload.sessionId = sessionId;
    this.ws.send(JSON.stringify(payload));
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`超时: ${method}`));
        }
      }, 60000);
    });
  }
  on(fn) {
    this.handlers.push(fn);
  }
}

async function main() {
  const chrome = spawn(
    CHROME,
    [
      '--headless=new',
      '--disable-gpu',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-extensions',
      // 软件渲染，保证 Flutter 的 CanvasKit 能在无头环境出图
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--window-size=1280,900',
      `--remote-debugging-port=${PORT}`,
      `--user-data-dir=${join(process.env.TEMP ?? '.', 'picpro-cdp-' + Date.now())}`,
      'about:blank',
    ],
    { stdio: ['ignore', 'ignore', 'pipe'] },
  );

  let chromeErr = '';
  chrome.stderr.on('data', (d) => (chromeErr += d.toString()));

  let version = null;
  for (let i = 0; i < 60; i++) {
    await sleep(500);
    try {
      version = await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json();
      break;
    } catch {
      /* 尚未就绪 */
    }
  }
  if (!version) {
    console.error('调试端口未就绪。chrome stderr:\n' + chromeErr.slice(0, 2000));
    chrome.kill();
    process.exit(1);
  }

  const ws = new WebSocket(version.webSocketDebuggerUrl);
  await new Promise((res, rej) => {
    ws.addEventListener('open', res);
    ws.addEventListener('error', rej);
  });
  const cdp = new Cdp(ws);

  const consoleLines = [];
  const exceptions = [];
  cdp.on((msg) => {
    if (msg.method === 'Runtime.consoleAPICalled') {
      consoleLines.push(
        `[${msg.params.type}] ` +
          (msg.params.args ?? [])
            .map((a) => a.value ?? a.description ?? '')
            .join(' '),
      );
    } else if (msg.method === 'Runtime.exceptionThrown') {
      const d = msg.params.exceptionDetails;
      exceptions.push(d.exception?.description ?? d.text ?? '未知异常');
    }
  });

  const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await cdp.send('Target.attachToTarget', {
    targetId,
    flatten: true,
  });

  await cdp.send('Runtime.enable', {}, sessionId);
  await cdp.send('Log.enable', {}, sessionId);
  await cdp.send('Page.enable', {}, sessionId);

  console.log(`导航到 ${URL_TO_TEST}`);
  await cdp.send('Page.navigate', { url: URL_TO_TEST }, sessionId);

  // 留足时间给 Flutter 引擎初始化与 Rust 内核加载
  await sleep(12000);

  const evalExpr = async (expr) =>
    (
      await cdp.send(
        'Runtime.evaluate',
        { expression: expr, returnByValue: true },
        sessionId,
      )
    ).result?.value;

  const isolated = await evalExpr('crossOriginIsolated');
  const origin = await evalExpr('location.origin');
  const isSecure = await evalExpr('isSecureContext');
  // 引擎启动后 Flutter 会插入这些宿主节点
  const glassPane = await evalExpr(
    "!!document.querySelector('flt-glass-pane, flutter-view, flt-scene-host')",
  );

  const shot = await cdp.send('Page.captureScreenshot', { format: 'png' }, sessionId);
  mkdirSync(dirname(SHOT_PATH), { recursive: true });
  writeFileSync(SHOT_PATH, Buffer.from(shot.data, 'base64'));

  // 与内核初始化失败相关的关键字
  const panic = consoleLines.filter((l) =>
    /panic|WorkerPool|crossOriginIsolated|SharedArrayBuffer|wasm_bindgen/i.test(l),
  );

  console.log('\n================ 检查结果 ================');
  console.log('访问地址        :', origin);
  console.log('是否安全上下文  :', isSecure);
  console.log('跨源隔离        :', isolated);
  console.log('Flutter 宿主节点:', glassPane);
  console.log('截图已保存      :', SHOT_PATH);

  console.log('\n--- 内核相关控制台输出 ---');
  if (panic.length === 0) {
    console.log('（无）');
  } else {
    panic.slice(0, 6).forEach((l) => console.log('  ' + l.slice(0, 220)));
  }

  console.log('\n--- 未捕获异常 ---');
  if (exceptions.length === 0) {
    console.log('（无）');
  } else {
    exceptions.slice(0, 4).forEach((e) => console.log('  ' + e.split('\n')[0].slice(0, 220)));
  }

  // 判定标准：内核无 panic、无未捕获异常、Flutter 引擎已启动。
  // 注意不要求 crossOriginIsolated 为 true —— 本项目用单线程内核，
  // 在非安全来源（纯 HTTP）下该值为 false 也属正常。
  const ok = panic.length === 0 && exceptions.length === 0 && glassPane === true;
  console.log('\n结论:', ok ? '✓ 页面可正常加载，内核已就绪' : '✗ 未通过');

  ws.close();
  chrome.kill();
  process.exit(ok ? 0 : 1);
}

main().catch((e) => {
  console.error('脚本异常:', e);
  process.exit(1);
});
