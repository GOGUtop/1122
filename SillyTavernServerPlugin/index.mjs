import crypto from 'node:crypto';

export const info = {
    id: 'tavern-live-bridge',
    name: 'Tavern Live Bridge',
    description: 'Streams SillyTavern generation output to the iOS live Picture in Picture client.',
};

const subscribers = new Map();
const histories = new Map();

export async function init(router) {
    router.get('/health', (_req, res) => {
        res.json({ ok: true, plugin: info.id });
    });

    router.get('/events', (req, res) => {
        const channel = cleanChannel(req.query.channel);
        if (!channel) return res.status(400).json({ error: 'Missing channel' });

        res.status(200);
        res.set({
            'Content-Type': 'text/event-stream; charset=utf-8',
            'Cache-Control': 'no-cache, no-transform',
            'Connection': 'keep-alive',
            'X-Accel-Buffering': 'no',
        });
        res.flushHeaders?.();

        const set = subscribers.get(channel) ?? new Set();
        set.add(res);
        subscribers.set(channel, set);
        send(res, { type: 'ready' });

        const history = histories.get(channel);
        if (history) {
            if (history.ended) {
                send(res, {
                    type: 'end',
                    generationId: history.generationId,
                    text: history.text,
                    reason: classifyReason(history.finishReason, history.text.trim()),
                    character: history.character,
                });
            } else {
                send(res, {
                    type: 'snapshot',
                    generationId: history.generationId,
                    text: history.text,
                    character: history.character,
                });
            }
        }

        const heartbeat = setInterval(() => res.write(': keepalive\n\n'), 15_000);
        req.on('close', () => {
            clearInterval(heartbeat);
            set.delete(res);
            if (set.size === 0) subscribers.delete(channel);
        });
    });

    router.all('/proxy', async (req, res) => {
        const channel = cleanChannel(req.get('x-tavern-live-channel'));
        const target = req.get('x-tavern-live-target');
        if (!channel || !isAllowedTarget(target)) {
            return res.status(400).json({ error: 'Invalid live bridge request' });
        }

        const generationId = crypto.randomUUID();
        const state = {
            generationId,
            text: '',
            character: '',
            finishReason: '',
            ended: false,
        };
        histories.set(channel, state);
        broadcast(channel, { type: 'start', generationId });

        const controller = new AbortController();
        req.on('aborted', () => {
            if (!state.ended) controller.abort();
        });
        res.on('close', () => {
            if (!state.ended) controller.abort();
        });

        try {
            const protocol = String(req.get('x-forwarded-proto') ?? req.protocol).split(',')[0].trim();
            const host = String(req.get('x-forwarded-host') ?? req.get('host')).split(',')[0].trim();
            const upstreamURL = new URL(target, `${protocol}://${host}`);
            const headers = copyHeaders(req.headers);
            headers.delete('host');
            headers.delete('content-length');
            headers.delete('x-tavern-live-channel');
            headers.delete('x-tavern-live-target');
            headers.set('accept-encoding', 'identity');

            const body = ['GET', 'HEAD'].includes(req.method)
                ? undefined
                : serializeBody(req);

            const upstream = await fetch(upstreamURL, {
                method: req.method,
                headers,
                body,
                redirect: 'manual',
                signal: controller.signal,
            });

            res.status(upstream.status);
            for (const [name, value] of upstream.headers.entries()) {
                if (!['content-length', 'content-encoding', 'transfer-encoding', 'connection'].includes(name.toLowerCase())) {
                    res.setHeader(name, value);
                }
            }
            res.setHeader('X-Accel-Buffering', 'no');
            res.flushHeaders?.();

            const contentType = upstream.headers.get('content-type') ?? '';
            const parser = createGenerationParser(state, event => broadcast(channel, event));
            const reader = upstream.body?.getReader();

            if (reader) {
                while (true) {
                    const { value, done } = await reader.read();
                    if (done) break;
                    res.write(Buffer.from(value));
                    parser.push(value, contentType);
                }
            }

            parser.finish();
            state.ended = true;
            res.end();
            broadcastEnd(channel, state);
        } catch (error) {
            if (!res.headersSent) res.status(502);
            if (!res.writableEnded) res.end();
            state.ended = true;
            state.finishReason ||= 'aborted';
            broadcastEnd(channel, state);
            console.error('[tavern-live-bridge] Proxy error:', error?.message ?? error);
        }
    });
}

export async function exit() {
    for (const clients of subscribers.values()) {
        for (const response of clients) response.end();
    }
    subscribers.clear();
    histories.clear();
}

function cleanChannel(value) {
    return typeof value === 'string' && /^[a-zA-Z0-9-]{8,128}$/.test(value) ? value : '';
}

function isAllowedTarget(value) {
    if (typeof value !== 'string' || !value.startsWith('/api/')) return false;
    if (value.startsWith('/api/plugins/tavern-live-bridge/')) return false;
    return value.includes('/generate')
        || value.includes('/chat-completions')
        || value.includes('/text-completions');
}

function copyHeaders(source) {
    const headers = new Headers();
    for (const [name, value] of Object.entries(source)) {
        if (Array.isArray(value)) {
            for (const item of value) headers.append(name, item);
        } else if (value != null) {
            headers.set(name, String(value));
        }
    }
    return headers;
}

function serializeBody(req) {
    if (Buffer.isBuffer(req.body)) return req.body;
    if (typeof req.body === 'string') return req.body;
    if (req.body != null && Object.keys(req.body).length > 0) {
        return JSON.stringify(req.body);
    }
    return undefined;
}

function createGenerationParser(state, emit) {
    const decoder = new TextDecoder();
    let buffer = '';
    let rawJSON = '';

    const processObject = object => {
        const reason = findFinishReason(object);
        if (reason) state.finishReason = reason;
        const text = findTextDelta(object);
        if (!text) return;

        if (looksLikeFullMessage(object, text)) {
            if (text.length >= state.text.length) state.text = text;
        } else {
            state.text += text;
        }
        emit({
            type: 'token',
            generationId: state.generationId,
            text: state.text,
            character: state.character,
        });
    };

    return {
        push(bytes, contentType) {
            const chunk = decoder.decode(bytes, { stream: true });
            if (contentType.includes('text/event-stream') || chunk.includes('data:')) {
                buffer += chunk;
                let newline;
                while ((newline = buffer.indexOf('\n')) >= 0) {
                    const line = buffer.slice(0, newline).trim();
                    buffer = buffer.slice(newline + 1);
                    if (!line.startsWith('data:')) continue;
                    const payload = line.slice(5).trim();
                    if (!payload || payload === '[DONE]') continue;
                    try { processObject(JSON.parse(payload)); } catch {}
                }
            } else {
                rawJSON += chunk;
                try {
                    processObject(JSON.parse(rawJSON));
                    rawJSON = '';
                } catch {}
            }
        },
        finish() {
            const tail = decoder.decode();
            if (tail) rawJSON += tail;
            if (rawJSON.trim()) {
                try { processObject(JSON.parse(rawJSON)); } catch {}
            }
        },
    };
}

function findTextDelta(value, depth = 0) {
    if (!value || depth > 6) return '';
    if (typeof value === 'string') return '';
    if (Array.isArray(value)) {
        for (const item of value) {
            const found = findTextDelta(item, depth + 1);
            if (found) return found;
        }
        return '';
    }

    const direct = [
        value?.choices?.[0]?.delta?.content,
        value?.choices?.[0]?.text,
        value?.delta?.text,
        value?.delta?.content,
        value?.content_block?.text,
        value?.token?.text,
        typeof value?.token === 'string' ? value.token : '',
        value?.choices?.[0]?.delta?.reasoning_content,
        value?.completion,
        value?.response,
        value?.candidates?.[0]?.content?.parts?.map?.(part => part?.text ?? '').join(''),
    ];
    for (const candidate of direct) {
        if (typeof candidate === 'string' && candidate) return candidate;
    }
    if (Array.isArray(value?.content)) {
        return value.content.map(item => typeof item?.text === 'string' ? item.text : '').join('');
    }
    return '';
}

function findFinishReason(value, depth = 0) {
    if (!value || depth > 6 || typeof value !== 'object') return '';
    const direct = value.finish_reason ?? value.stop_reason ?? value.done_reason;
    if (typeof direct === 'string' && direct) return direct;
    for (const child of Object.values(value)) {
        const found = findFinishReason(child, depth + 1);
        if (found) return found;
    }
    return '';
}

function looksLikeFullMessage(object, text) {
    return object?.message?.content === text
        || object?.choices?.[0]?.message?.content === text
        || object?.response === text;
}

function broadcastEnd(channel, state) {
    const trimmed = state.text.trim();
    const reason = classifyReason(state.finishReason, trimmed);
    broadcast(channel, {
        type: 'end',
        generationId: state.generationId,
        text: state.text,
        reason,
        character: state.character,
    });
    setTimeout(() => {
        if (histories.get(channel)?.generationId === state.generationId) histories.delete(channel);
    }, 5 * 60_000).unref?.();
}

function classifyReason(reason, text) {
    if (!text) return 'empty';
    const normalized = String(reason ?? '').toLowerCase();
    if (['length', 'max_tokens', 'max_output_tokens', 'token_limit', 'aborted', 'cancelled', 'canceled'].some(item => normalized.includes(item))) {
        return 'truncated';
    }
    return 'complete';
}

function broadcast(channel, event) {
    const clients = subscribers.get(channel);
    if (!clients) return;
    for (const response of clients) send(response, event);
}

function send(response, event) {
    if (!response.writableEnded) {
        response.write(`data: ${JSON.stringify(event)}\n\n`);
    }
}
