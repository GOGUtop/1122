import Foundation

enum TavernToolsScript {
    static let source = #"""
(() => {
  if (window.__tavernLiteToolsInstalled) return;
  window.__tavernLiteToolsInstalled = true;

  const css = `
  #dog-actions, #dog-translation, #dog-error-panel, #dog-card-toast, #dog-card-panel { font-family: -apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC",sans-serif; z-index: 2147483647; box-sizing:border-box; }
  #dog-actions { position: fixed; display: none; align-items:center; gap: 7px; padding: 7px; border-radius: 999px; background: rgba(12,18,32,.76); backdrop-filter: blur(22px) saturate(1.8); -webkit-backdrop-filter: blur(22px) saturate(1.8); box-shadow: 0 14px 38px rgba(0,0,0,.38); border: 1px solid rgba(255,255,255,.20); transform: translate(-50%, -118%); animation: dogPop .18s ease-out; }
  #dog-actions button { border: 0; border-radius: 999px; color: #fff; background: rgba(255,255,255,.13); padding: 9px 13px; font-size: 13px; font-weight: 850; white-space: nowrap; display:flex; align-items:center; gap:5px; }
  #dog-actions button.primary { color:#15110b; background: linear-gradient(135deg,#fff0a3,#ffc845); box-shadow: inset 0 1px 0 rgba(255,255,255,.62), 0 5px 15px rgba(255,196,49,.22); }
  #dog-actions .count { color:rgba(255,255,255,.62); font-size:11px; font-weight:800; padding:0 4px; }
  #dog-translation { position: fixed; display:none; width:min(90vw, 420px); color:#f8fbff; background: rgba(11,16,29,.88); border:1px solid rgba(255,255,255,.17); box-shadow:0 18px 48px rgba(0,0,0,.42); backdrop-filter: blur(24px) saturate(1.55); -webkit-backdrop-filter: blur(24px) saturate(1.55); border-radius:24px; padding:14px 15px 15px; line-height:1.54; transform: translate(-50%, 10px); animation: dogPop .18s ease-out; }
  #dog-translation .top { display:flex; align-items:center; justify-content:space-between; gap:8px; margin-bottom:9px; }
  #dog-translation .title { font-size:13px; font-weight:900; color:#ffdf73; }
  #dog-translation .actions { display:flex; gap:6px; }
  #dog-translation button { border:0; border-radius:999px; color:rgba(255,255,255,.84); background:rgba(255,255,255,.10); font-size:12px; font-weight:800; padding:6px 9px; }
  #dog-translation .label { color:rgba(255,255,255,.48); font-size:11px; font-weight:800; margin:8px 0 4px; }
  #dog-translation .origin { max-height:82px; overflow:auto; color:rgba(255,255,255,.55); font-size:12px; white-space:pre-wrap; word-break:break-word; padding:9px 10px; border-radius:14px; background:rgba(255,255,255,.055); }
  #dog-translation .body { font-size:15px; white-space:pre-wrap; word-break:break-word; color:#fff; padding:10px 2px 2px; }
  #dog-translation.loading .body { color:rgba(255,255,255,.72); }
  #dog-card-panel { position:fixed; left:12px; right:12px; bottom:max(12px, env(safe-area-inset-bottom)); display:none; color:#fff; background:rgba(8,12,23,.90); border:1px solid rgba(255,255,255,.16); box-shadow:0 -14px 54px rgba(0,0,0,.44); backdrop-filter:blur(26px) saturate(1.45); -webkit-backdrop-filter:blur(26px) saturate(1.45); border-radius:28px; overflow:hidden; animation: dogSlide .2s ease-out; }
  #dog-card-panel .head { display:flex; align-items:center; justify-content:space-between; gap:10px; padding:15px 16px 10px; border-bottom:1px solid rgba(255,255,255,.08); }
  #dog-card-panel .head b { font-size:17px; }
  #dog-card-panel .head span { display:block; font-size:11px; color:rgba(255,255,255,.54); margin-top:2px; }
  #dog-card-panel .head button { border:0; border-radius:12px; padding:7px 10px; color:#fff; background:rgba(255,255,255,.12); font-weight:800; }
  #dog-card-panel .themes { display:grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap:10px; padding:12px 13px 15px; }
  #dog-card-panel .theme { border:1px solid rgba(255,255,255,.12); border-radius:20px; padding:12px 12px 11px; text-align:left; color:#fff; min-height:72px; overflow:hidden; position:relative; background:rgba(255,255,255,.08); }
  #dog-card-panel .theme:before { content:''; position:absolute; inset:0; opacity:.9; z-index:-1; }
  #dog-card-panel .theme b { font-size:14px; display:block; margin-bottom:3px; }
  #dog-card-panel .theme span { font-size:11px; color:rgba(255,255,255,.68); }
  #dog-card-panel .theme[data-theme="night"]:before { background:linear-gradient(135deg,#07111f,#10294c,#25133b); }
  #dog-card-panel .theme[data-theme="cream"]:before { background:linear-gradient(135deg,#fff2d8,#fce7e8,#e9f2ff); }
  #dog-card-panel .theme[data-theme="cream"] { color:#30243a; } #dog-card-panel .theme[data-theme="cream"] span{color:rgba(48,36,58,.62)}
  #dog-card-panel .theme[data-theme="cyber"]:before { background:linear-gradient(135deg,#070a16,#161e52,#391052); }
  #dog-card-panel .theme[data-theme="sakura"]:before { background:linear-gradient(135deg,#3a1835,#9b315d,#ffc1d8); }
  #dog-card-panel .theme[data-theme="emerald"]:before { background:linear-gradient(135deg,#06231d,#0e4b3e,#c7a85b); }
  #dog-card-panel .theme[data-theme="aurora"]:before { background:linear-gradient(135deg,#10163a,#4057c8,#a870ff); }
  #dog-card-panel .theme[data-theme="ink"]:before { background:linear-gradient(135deg,#050505,#17120c,#3a2b13); }
  #dog-card-panel .theme[data-theme="minimal"]:before { background:linear-gradient(135deg,#f9faff,#eef3ff,#fff); }
  #dog-card-panel .theme[data-theme="minimal"] { color:#192033; } #dog-card-panel .theme[data-theme="minimal"] span{color:rgba(25,32,51,.56)}
  #dog-error-panel { position: fixed; left: 12px; right: 12px; bottom: max(12px, env(safe-area-inset-bottom)); display:none; color:#f7f9ff; background: rgba(10,14,25,.90); border:1px solid rgba(255,255,255,.16); box-shadow:0 -12px 50px rgba(0,0,0,.42); backdrop-filter: blur(24px) saturate(1.4); -webkit-backdrop-filter: blur(24px) saturate(1.4); border-radius: 24px; overflow:hidden; }
  #dog-error-panel .head { display:flex; align-items:center; justify-content:space-between; padding:14px 15px 10px; border-bottom:1px solid rgba(255,255,255,.08); }
  #dog-error-panel .head b { font-size:16px; }
  #dog-error-panel .head button { border:0; border-radius:12px; padding:7px 10px; color:#fff; background:rgba(255,255,255,.12); font-weight:700; }
  #dog-error-panel .list { max-height: min(55vh, 520px); overflow:auto; padding:10px 12px 14px; }
  #dog-error-panel .item { border:1px solid rgba(255,255,255,.1); background:rgba(255,255,255,.055); border-radius:18px; padding:12px; margin:8px 0; }
  #dog-error-panel .item .t { color:#ffdb6b; font-weight:850; font-size:14px; margin-bottom:5px; }
  #dog-error-panel .item .d { font-size:13px; color:rgba(255,255,255,.82); line-height:1.5; white-space:pre-wrap; word-break:break-word; }
  #dog-error-panel .item .raw { margin-top:8px; color:rgba(255,255,255,.48); font-size:12px; max-height:72px; overflow:hidden; white-space:pre-wrap; }
  #dog-error-panel .item button { margin-top:9px; border:0; border-radius:999px; background:rgba(255,210,88,.18); color:#ffe087; padding:7px 10px; font-size:12px; font-weight:800; }
  #dog-card-toast { position:fixed; left:50%; bottom:max(88px, calc(env(safe-area-inset-bottom) + 70px)); transform:translateX(-50%); display:none; color:#fff; background:rgba(10,15,25,.86); border:1px solid rgba(255,255,255,.16); border-radius:999px; padding:10px 14px; box-shadow:0 10px 28px rgba(0,0,0,.35); backdrop-filter:blur(18px); -webkit-backdrop-filter:blur(18px); font-size:13px; font-weight:850; }
  @keyframes dogPop { from { opacity:0; transform:translate(-50%, -106%) scale(.94); } to { opacity:1; transform:translate(-50%, -118%) scale(1); } }
  @keyframes dogSlide { from { opacity:0; transform:translateY(14px); } to { opacity:1; transform:translateY(0); } }
  `;
  const style = document.createElement('style');
  style.id = 'dog-lite-tools-style';
  style.textContent = css;
  document.documentElement.appendChild(style);

  const actions = document.createElement('div');
  actions.id = 'dog-actions';
  actions.innerHTML = `<button data-act="translate">🌐 翻译</button><button data-act="card" class="primary">🔖 卡片</button><span class="count"></span>`;
  document.documentElement.appendChild(actions);

  const trans = document.createElement('div');
  trans.id = 'dog-translation';
  trans.innerHTML = `<div class="top"><div class="title">🌐 Edge 翻译</div><div class="actions"><button data-copy>复制</button><button data-close>×</button></div></div><div class="label">原文</div><div class="origin"></div><div class="label">译文</div><div class="body"></div>`;
  document.documentElement.appendChild(trans);

  const cardPanel = document.createElement('div');
  cardPanel.id = 'dog-card-panel';
  cardPanel.innerHTML = `<div class="head"><div><b>🔖 选择卡片主题</b><span>生成 DogTavern 风格分享卡</span></div><button data-close>收起</button></div><div class="themes"></div>`;
  document.documentElement.appendChild(cardPanel);

  const errPanel = document.createElement('div');
  errPanel.id = 'dog-error-panel';
  errPanel.innerHTML = `<div class="head"><b>🩺 错误码翻译</b><button data-close>收起</button></div><div class="list"></div>`;
  document.documentElement.appendChild(errPanel);

  const toast = document.createElement('div');
  toast.id = 'dog-card-toast';
  document.documentElement.appendChild(toast);

  const CARD_THEMES = [
    ['night','星夜玻璃','深蓝发光 · 通用推荐'],
    ['cream','奶油便签','柔和浅色 · 日常摘录'],
    ['cyber','赛博霓虹','高对比 · 科幻感'],
    ['sakura','樱粉胶片','粉紫渐变 · 角色台词'],
    ['emerald','墨绿诗页','稳重高级 · 文学感'],
    ['aurora','极光蓝紫','梦幻流光 · 长文本'],
    ['ink','黑金剧场','暗黑金色 · 戏剧感'],
    ['minimal','极简白卡','干净清爽 · 便于阅读']
  ];
  cardPanel.querySelector('.themes').innerHTML = CARD_THEMES.map(([id, name, desc]) => `<button class="theme" data-theme="${id}"><b>${name}</b><span>${desc}</span></button>`).join('');

  let activeSelection = null;
  let requestSeq = 1;
  const callbacks = new Map();
  const localTranslateCache = new Map();

  function post(action, payload) {
    try { window.webkit.messageHandlers.tavernTools.postMessage(Object.assign({ action }, payload || {})); } catch (_) {}
  }

  function withNative(action, payload, cb) {
    const requestId = 'dog-' + Date.now() + '-' + (requestSeq++);
    callbacks.set(requestId, cb);
    post(action, Object.assign({ requestId }, payload || {}));
  }

  function rectToPoint(rect) {
    const x = Math.min(Math.max(rect.left + rect.width / 2, 32), window.innerWidth - 32);
    const y = Math.min(Math.max(rect.top, 74), window.innerHeight - 40);
    return { x, y };
  }

  function showToast(text) {
    toast.textContent = text;
    toast.style.display = 'block';
    clearTimeout(showToast._t);
    showToast._t = setTimeout(() => toast.style.display = 'none', 1700);
  }

  function isMostlyChinese(text) {
    const zh = (text.match(/[\u3400-\u9fff]/g) || []).length;
    const en = (text.match(/[A-Za-z]/g) || []).length;
    return zh >= 4 && zh >= en;
  }

  function setTranslationPanel(origin, body, rect, loading) {
    const p = rectToPoint(rect || { left: window.innerWidth / 2, top: 120, width: 1, height: 1 });
    trans.classList.toggle('loading', !!loading);
    trans.querySelector('.title').textContent = loading ? '🌐 Edge 翻译中…' : '🌐 Edge 翻译';
    trans.querySelector('.origin').textContent = origin || '';
    trans.querySelector('.body').textContent = body || '';
    trans.style.left = p.x + 'px';
    trans.style.top = Math.min(window.innerHeight - 210, p.y + 13) + 'px';
    trans.style.display = 'block';
  }

  function translate(text, rect) {
    const value = (text || '').trim();
    if (!value) return;
    if (isMostlyChinese(value)) {
      setTranslationPanel(value, value, rect, false);
      showToast('原文主要是中文，已直接显示。');
      return;
    }
    const key = value.slice(0, 800) + ':' + value.length;
    const cached = localTranslateCache.get(key);
    if (cached) {
      setTranslationPanel(value, cached, rect, false);
      showToast('已使用翻译缓存');
      return;
    }
    setTranslationPanel(value, '正在调用 Microsoft Edge 翻译引擎…', rect, true);
    withNative('translate', { text: value }, (res) => {
      if (res && res.ok) {
        const translated = res.text || '';
        localTranslateCache.set(key, translated);
        setTranslationPanel(value, translated, rect, false);
      } else {
        setTranslationPanel(value, (res && res.error) || '翻译失败，请稍后再试。', rect, false);
      }
    });
  }

  function closestMes(node) {
    let el = node && (node.nodeType === 1 ? node : node.parentElement);
    while (el && el !== document.documentElement) {
      if (el.classList && el.classList.contains('mes')) return el;
      el = el.parentElement;
    }
    return null;
  }

  function isAIMessage(mes) {
    if (!mes) return false;
    const attr = (mes.getAttribute('is_user') || mes.dataset?.isUser || '').toLowerCase();
    if (attr === 'true' || attr === '1') return false;
    if (mes.classList.contains('user_mes') || mes.classList.contains('user') || mes.classList.contains('is_user')) return false;
    return true;
  }

  function characterName(mes) {
    if (!mes) return '';
    const el = mes.querySelector('.name_text, .ch_name, .mes_name, [data-name], .avatar img[title]');
    return (el?.getAttribute?.('title') || el?.dataset?.name || el?.textContent || '').trim();
  }

  function currentSelectionInfo() {
    const sel = window.getSelection();
    const text = (sel && sel.toString() || '').trim();
    if (!sel || sel.rangeCount === 0 || text.length < 2) return null;
    const range = sel.getRangeAt(0);
    const rects = Array.from(range.getClientRects()).filter(r => r && r.width > 0 && r.height > 0);
    const rect = rects[rects.length - 1] || range.getBoundingClientRect();
    if (!rect || (!rect.width && !rect.height)) return null;
    const mes = closestMes(range.commonAncestorContainer);
    const ai = isAIMessage(mes);
    return { text, rect, isAI: ai, character: characterName(mes), length: text.length };
  }

  function showActions(info) {
    activeSelection = info;
    actions.querySelector('[data-act="card"]').style.display = info.isAI ? '' : 'none';
    actions.querySelector('.count').textContent = info.length > 80 ? `${info.length}字` : '';
    const p = rectToPoint(info.rect);
    actions.style.left = p.x + 'px';
    actions.style.top = p.y + 'px';
    actions.style.display = 'flex';
  }

  function updateSelection(force) {
    const info = currentSelectionInfo();
    if (info) {
      showActions(info);
      return;
    }
    if (force) return;
    actions.style.display = 'none';
  }

  let selectionTimer = null;
  function scheduleSelectionUpdate(delay = 150) {
    clearTimeout(selectionTimer);
    selectionTimer = setTimeout(() => updateSelection(false), delay);
  }
  document.addEventListener('selectionchange', () => scheduleSelectionUpdate(170), true);
  document.addEventListener('touchend', () => scheduleSelectionUpdate(260), true);
  document.addEventListener('mouseup', () => scheduleSelectionUpdate(120), true);
  document.addEventListener('contextmenu', () => scheduleSelectionUpdate(80), true);
  document.addEventListener('scroll', () => { actions.style.display = 'none'; }, true);
  document.addEventListener('click', (ev) => {
    if (!actions.contains(ev.target) && !trans.contains(ev.target) && !errPanel.contains(ev.target) && !cardPanel.contains(ev.target)) {
      actions.style.display = 'none';
    }
  }, true);

  trans.querySelector('[data-close]').addEventListener('click', () => trans.style.display = 'none');
  trans.querySelector('[data-copy]').addEventListener('click', async () => {
    const value = trans.querySelector('.body').textContent || '';
    try { await navigator.clipboard.writeText(value); showToast('翻译已复制'); } catch (_) { showToast('复制失败，请手动长按复制'); }
  });
  errPanel.querySelector('[data-close]').addEventListener('click', () => errPanel.style.display = 'none');
  cardPanel.querySelector('[data-close]').addEventListener('click', () => cardPanel.style.display = 'none');

  actions.addEventListener('click', (ev) => {
    const btn = ev.target.closest('button');
    if (!btn || !activeSelection) return;
    ev.preventDefault();
    ev.stopPropagation();
    if (btn.dataset.act === 'translate') {
      translate(activeSelection.text, activeSelection.rect);
    } else if (btn.dataset.act === 'card') {
      cardPanel.style.display = 'block';
      actions.style.display = 'none';
    }
  });

  cardPanel.addEventListener('click', (ev) => {
    const btn = ev.target.closest('[data-theme]');
    if (!btn || !activeSelection) return;
    ev.preventDefault();
    ev.stopPropagation();
    const theme = btn.dataset.theme || 'night';
    post('makeCard', { text: activeSelection.text, character: activeSelection.character || 'AI Message', theme });
    showToast('正在生成卡片…');
    window.getSelection()?.removeAllRanges?.();
    cardPanel.style.display = 'none';
  });

  const ERROR_DICT = [
    {k:['400','bad request'],t:'400 请求格式错误',d:'请求体、参数或代理格式不符合接口要求。检查模型、上下文长度、反代地址和请求模板。'},
    {k:['401','unauthorized','invalid api key','api key invalid','incorrect api key'],t:'401 未授权',d:'API Key 错误、过期、没有填入，或当前反代不接受这个 Key。'},
    {k:['403','forbidden','permission denied','access denied'],t:'403 禁止访问',d:'账号、Key、白名单、地区或模型权限不足。'},
    {k:['404','not found','model_not_found','model not found'],t:'404 未找到',d:'接口地址或模型名称不存在。检查模型 ID、反代路径和端口。'},
    {k:['405','method not allowed'],t:'405 方法不允许',d:'接口路径正确但请求方法不对，常见于把聊天接口和文本补全接口填反。'},
    {k:['408','request timeout'],t:'408 请求超时',d:'服务器等待请求超时，通常是网络、代理或反代太慢。'},
    {k:['409','conflict'],t:'409 请求冲突',d:'服务端状态冲突，稍后重试或新开一轮会话。'},
    {k:['413','payload too large','request entity too large'],t:'413 请求过大',d:'上下文、世界书或提示词过长。减少上下文长度或压缩世界书。'},
    {k:['415','unsupported media type'],t:'415 格式不支持',d:'Content-Type 或请求体格式不被接口接受。'},
    {k:['422','unprocessable entity','validation error'],t:'422 参数校验失败',d:'模型参数不合法，例如 temperature、top_p、max_tokens 或消息数组格式异常。'},
    {k:['429','rate limit','too many requests','quota'],t:'429 额度或频率限制',d:'请求太频繁、额度耗尽或并发过高。降低频率、换 Key 或换节点。'},
    {k:['500','internal server error'],t:'500 服务器内部错误',d:'模型服务或反代内部报错。先重试，不行换模型或查看服务端日志。'},
    {k:['502','bad gateway'],t:'502 网关错误',d:'反代或上游接口挂了，通常不是酒馆本身的问题。'},
    {k:['503','service unavailable','overloaded'],t:'503 服务不可用',d:'上游繁忙、维护或模型过载。稍后重试或切换模型。'},
    {k:['504','gateway timeout'],t:'504 网关超时',d:'反代等上游返回超时，适合降低上下文、换节点或延长超时。'},
    {k:['520'],t:'520 未知网关错误',d:'Cloudflare 或反代返回未知错误，优先检查反代状态。'},
    {k:['521'],t:'521 源站拒绝连接',d:'源服务器没开、端口错或防火墙拒绝。'},
    {k:['522'],t:'522 连接超时',d:'Cloudflare 连不上源站，检查服务器端口、防火墙和负载。'},
    {k:['524'],t:'524 超时',d:'源站处理时间太长，减少上下文或提高反代超时。'},
    {k:['cors','cross-origin'],t:'CORS 跨域错误',d:'浏览器跨域被拦截。优先使用同源反代或在服务端配置 CORS。'},
    {k:['networkerror','network error','failed to fetch'],t:'网络请求失败',d:'DNS、代理、证书、端口或反代连接异常。'},
    {k:['load failed','cannot connect','connection refused'],t:'连接被拒绝',d:'服务器端口没监听，或防火墙/Nginx 没放行。'},
    {k:['connection reset','econnreset'],t:'连接被重置',d:'上游或代理主动断开连接，常见于超时和连接池问题。'},
    {k:['etimedout','timed out','timeout'],t:'连接超时',d:'网络链路或模型响应太慢。尝试减少上下文或换节点。'},
    {k:['enotfound','getaddrinfo'],t:'DNS 解析失败',d:'域名解析不到服务器 IP，检查 A 记录和本机 DNS。'},
    {k:['ssl','tls','certificate','cert'],t:'证书/TLS 错误',d:'HTTPS 证书无效、过期或域名不匹配。'},
    {k:['json parse','unexpected token','invalid json'],t:'JSON 解析失败',d:'接口返回了非 JSON 内容，可能是报错 HTML、登录页或反代异常。'},
    {k:['context_length_exceeded','maximum context length','too many tokens'],t:'上下文超限',d:'提示词、历史记录或世界书超过模型上下文。减少上下文或换长上下文模型。'},
    {k:['max_tokens','finish_reason":"length','finish_reason: length'],t:'回复被截断',d:'输出达到最大 token 限制。提高 max_tokens 或继续生成。'},
    {k:['content_filter','safety','policy violation'],t:'内容安全拦截',d:'模型安全策略拦截。换表达方式、换模型或降低敏感内容。'},
    {k:['insufficient_quota','billing','payment required'],t:'余额或账单异常',d:'账户余额不足、账单未开通或 Key 没有可用额度。'},
    {k:['invalid_request_error'],t:'请求参数错误',d:'接口认为请求参数不合法，检查模型、消息格式、流式选项和采样参数。'},
    {k:['authenticationerror','authentication error'],t:'认证失败',d:'Key、令牌或登录状态错误。'},
    {k:['permissionerror','permission error'],t:'权限错误',d:'Key 或账号没有访问该模型/接口的权限。'},
    {k:['not enough credits','credit balance'],t:'点数不足',d:'服务商账户余额不足或套餐已用完。'},
    {k:['model is overloaded','server overloaded'],t:'模型过载',d:'当前模型繁忙，稍后重试或切换模型。'},
    {k:['stream interrupted','premature close','socket hang up'],t:'流式输出中断',d:'网络或上游提前断开，可能导致空回或截断。'},
    {k:['no response','empty response','response body is empty'],t:'空响应',d:'上游没有返回正文。检查反代、模型状态和提示词是否触发异常。'},
    {k:['invalid model','unsupported model'],t:'模型不支持',d:'当前接口不支持填写的模型 ID 或参数组合。'},
    {k:['proxy error','tunnel'],t:'代理错误',d:'本机代理、反代或隧道连接失败。'},
    {k:['csrf','forgery'],t:'CSRF 校验失败',d:'网页登录态或请求头异常，刷新页面或重新登录。'},
    {k:['forbidden by whitelist','whitelist'],t:'白名单拦截',d:'SillyTavern 白名单或访问控制拦截了当前 IP。'},
    {k:['websocket','ws error'],t:'WebSocket 错误',d:'实时连接断开，检查反代是否支持 WebSocket Upgrade。'},
    {k:['mixed content'],t:'混合内容拦截',d:'HTTPS 页面加载 HTTP 资源被浏览器阻止。'},
    {k:['aborterror','the operation was aborted'],t:'请求被取消',d:'请求被用户停止、页面刷新或系统中断。'},
    {k:['typeerror'],t:'前端脚本错误',d:'网页脚本执行失败，可能是插件冲突或版本不兼容。'}
  ];


  function matchError(text) {
    const lower = (text || '').toLowerCase();
    return ERROR_DICT.find(e => e.k.some(key => lower.includes(key)));
  }

  function visible(el) {
    const st = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return st.display !== 'none' && st.visibility !== 'hidden' && r.width > 0 && r.height > 0;
  }

  function likelyError(text) {
    return /(error|failed|fail|exception|timeout|timed out|unauthorized|forbidden|quota|rate limit|invalid|denied|not found|bad gateway|service unavailable|network|cors|ssl|tls|401|403|404|408|413|422|429|500|502|503|504|520|521|522|524)/i.test(text || '');
  }

  function collectErrors() {
    const selectors = '.toast,.toast-message,.error,.warning,.errorMessage,.swal2-popup,#toast-container,.mes_text,.popup,pre,code,[role="alert"]';
    const list = [];
    document.querySelectorAll(selectors).forEach(el => {
      if (!visible(el)) return;
      const text = (el.innerText || el.textContent || '').trim();
      if (text.length < 5 || text.length > 3200) return;
      if (!likelyError(text)) return;
      if (!list.some(x => x.text === text)) list.push({ text, rect: el.getBoundingClientRect() });
    });
    if (!list.length) {
      const body = (document.body.innerText || '').slice(-9000);
      const lines = body.split('\n').map(x => x.trim()).filter(x => x.length > 4 && likelyError(x));
      lines.slice(-5).forEach(text => list.push({ text, rect: { left: window.innerWidth / 2, top: 120, width: 1, height: 1 } }));
    }
    return list.slice(-8).reverse();
  }

  function renderErrors(items) {
    const list = errPanel.querySelector('.list');
    list.innerHTML = '';
    if (!items.length) {
      list.innerHTML = `<div class="item"><div class="t">没有找到明显错误码</div><div class="d">页面当前没有检测到 HTTP 错误、接口错误或网络错误。可以选中报错文字后点“划词翻译”。</div></div>`;
    } else {
      items.forEach((it) => {
        const hit = matchError(it.text);
        const div = document.createElement('div');
        div.className = 'item';
        div.innerHTML = `<div class="t"></div><div class="d"></div><div class="raw"></div><button>Edge 翻译原文</button>`;
        div.querySelector('.t').textContent = hit ? hit.t : '未知错误，建议机翻原文';
        div.querySelector('.d').textContent = hit ? hit.d : '内置字典没有命中这个错误，可以用 Microsoft Edge 翻译引擎翻译原文。';
        div.querySelector('.raw').textContent = it.text;
        div.querySelector('button').addEventListener('click', () => translate(it.text, it.rect));
        list.appendChild(div);
      });
    }
    errPanel.style.display = 'block';
  }

  window.__tavernLiteTools = {
    nativeResult(res) {
      const cb = callbacks.get(res && res.requestId);
      if (cb) {
        callbacks.delete(res.requestId);
        cb(res);
      }
    },
    scanErrors() { renderErrors(collectErrors()); },
    hideAll() {
      actions.style.display = 'none';
      trans.style.display = 'none';
      errPanel.style.display = 'none';
      cardPanel.style.display = 'none';
    }
  };
})();
"""#
}
