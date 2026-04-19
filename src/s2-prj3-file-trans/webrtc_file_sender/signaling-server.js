const { WebSocketServer } = require('ws');

const wss = new WebSocketServer({ port: 9000 });

// Keep all clients, but relay signaling messages only between a paired offerer/answerer.
// The offerer triggers pairing by sending:
//   { type: 'pair_request', targetIP: '...' }
const clientsByIP = new Map(); // ip -> ws

function buildPeerListFor(ws) {
  const peers = [];
  for (const [peerKey, peerWs] of clientsByIP.entries()) {
    if (peerWs !== ws && peerWs.readyState === 1) {
      peers.push({ ip: peerKey, name: peerKey });
    }
  }
  return peers;
}

function sendPeerList(ws) {
  if (!ws || ws.readyState !== 1) return;
  ws.send(JSON.stringify({ type: 'peers', peers: buildPeerListFor(ws) }));
}

function broadcastPeerLists() {
  for (const ws of clientsByIP.values()) {
    sendPeerList(ws);
  }
}

console.log('[signaling] Listening on ws://localhost:9000');

wss.on('connection', (ws) => {
  const addr = ws._socket.remoteAddress || 'unknown';
  const port = ws._socket.remotePort || 0;
  const key = port ? `${addr}:${port}` : addr;
  ws._clientIP = key;
  ws._pairPartner = null;

  clientsByIP.set(key, ws);
  console.log('[signaling] Client connected:', key);
  broadcastPeerLists();

  ws.on('message', (raw) => {
    let p;
    try { p = JSON.parse(raw.toString()); } catch (e) { return; }
    if (!p || typeof p.type !== 'string') return;

    // --- pair_request：发起方（A）请求与列表里某个 targetIP（B）配对，建立一对一信令隧道 ---
    // 流程概览：校验目标 → 校验双方空闲 → 双向绑定 _pairPartner → 下发 role → 仅给 offerer 发 peer_joined 触发 createOffer
    if (p.type === 'pair_request') {
      const targetIP = p.targetIP; // 客户端在 peers 列表里看到的对方 key（addr:port）
      const targetWs = clientsByIP.get(targetIP); // 在 Map 里查该 key 对应的 WebSocket，即“被叫”连接

      // 目标无效：没填 targetIP、对方不在线、或不能连自己
      if (!targetIP || !targetWs || targetWs === ws) {
        ws.send(JSON.stringify({ type: 'error', reason: 'target_not_found' }));
        return;
      }

      // 任一方已在配对中：避免重复 pair_request 或三方插入（服务端会回 busy）
      if (ws._pairPartner || targetWs._pairPartner) {
        ws.send(JSON.stringify({ type: 'error', reason: 'busy' }));
        return;
      }

      // 双向记住对端：之后非 pair_request 的信令（offer/answer/candidate）只转发给 partner
      ws._pairPartner = targetWs;
      targetWs._pairPartner = ws;

      // 给发起方 ws：你是 offerer，并带上本机在信令侧的 selfIP（RTCClient 里可当 selfIP 用）
      ws.send(JSON.stringify({ type: 'role', role: 'offerer', selfIP: ws._clientIP }));
      // 给被叫 targetWs：你是 answerer，带上 selfIP 与对端 peerIP（便于展示/逻辑，但 answerer 不依赖 peer_joined）
      targetWs.send(JSON.stringify({
        type: 'role',
        role: 'answerer',
        selfIP: targetWs._clientIP,
        peerIP: ws._clientIP
      }));

      // 延迟 200ms 再给 offerer 发 peer_joined：注释写的是等 answerer 侧 role 处理完再让 A 发 offer（简单时序缓冲）
      setTimeout(() => {
        if (ws.readyState === 1) {
          // 仅发给 offerer（ws）：通知“对端已就绪”，RTCClient 里 isOfferer 为 true 时在此触发 createOffer
          ws.send(JSON.stringify({ type: 'peer_joined', peerIP: targetWs._clientIP }));
          console.log('[signaling] paired', ws._clientIP, '->', targetWs._clientIP);
        }
      }, 200);

      return; // pair_request 处理完毕，不再走后面的 partner 转发逻辑
    }

    if (p.type === 'list_peers') {
      sendPeerList(ws);
      return;
    }

    const partner = ws._pairPartner;
    if (!partner || partner.readyState !== 1) return;

    if (p.type === 'peer_left') return;
    partner.send(JSON.stringify(p));
  });

  ws.on('close', () => {
    console.log('[signaling] Client disconnected:', ws._clientIP);

    const partner = ws._pairPartner;
    ws._pairPartner = null;

    if (clientsByIP.get(ws._clientIP) === ws) {
      clientsByIP.delete(ws._clientIP);
    }

    if (partner && partner.readyState === 1) {
      partner._pairPartner = null;
      partner.send(JSON.stringify({ type: 'peer_left' }));
    }

    broadcastPeerLists();
  });
});
