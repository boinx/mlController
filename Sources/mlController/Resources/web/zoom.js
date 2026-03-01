'use strict';

// ── State ────────────────────────────────────────────────────────────────────

let ws = null;
let pollTimer = null;
let currentSources = [];
let currentParticipants = [];

// ── DOM Refs ─────────────────────────────────────────────────────────────────

const container   = document.getElementById('sources-container');
const meetingInfo = document.getElementById('meeting-info');
const lastUpdated = document.getElementById('last-updated');
const errorBanner = document.getElementById('error-banner');

// ── Fetch Zoom Data ──────────────────────────────────────────────────────────

async function fetchZoomData() {
  try {
    const [srcRes, partRes] = await Promise.all([
      fetch('/api/zoom/sources'),
      fetch('/api/zoom/participants')
    ]);
    if (!srcRes.ok || !partRes.ok) throw new Error('API error');
    const srcData  = await srcRes.json();
    const partData = await partRes.json();

    if (srcData.error && !srcData.sources?.length) {
      currentSources = [];
      currentParticipants = [];
      renderEmpty(srcData.error);
      return;
    }

    currentSources = srcData.sources || [];
    currentParticipants = (partData.participants || [])
      .filter(p => p.name)
      .sort((a, b) => a.name.localeCompare(b.name));

    errorBanner.classList.remove('visible');
    render();
    lastUpdated.textContent = 'Updated ' + new Date().toLocaleTimeString();
  } catch (e) {
    errorBanner.classList.add('visible');
    lastUpdated.textContent = 'Error at ' + new Date().toLocaleTimeString();
  }
}

// ── Render ────────────────────────────────────────────────────────────────────

function render() {
  if (currentSources.length === 0) {
    renderEmpty('No Zoom sources in the current document');
    return;
  }

  container.innerHTML = currentSources.map(src => {
    const selType  = src['zoom-userselectiontype'] || 0;
    const userId   = src['zoom-userid'];
    const username = src['zoom-username'] || '';
    const summary  = src['summary'] || '';

    // Assignment display
    let assignIcon = '';
    let assignText = '';
    if (selType === 6) {
      assignIcon = '📺';
      assignText = summary || 'Screen Share';
    } else if (selType === 2) {
      assignIcon = '🔄';
      assignText = username ? `${username} (Automatic)` : 'Automatic';
    } else if (selType === 1 && username) {
      assignIcon = '📹';
      assignText = username;
    } else {
      assignIcon = '❓';
      assignText = summary || 'Unassigned';
    }

    // Build select options
    let options = '';

    // Special modes
    options += `<option value="auto" ${selType === 2 ? 'selected' : ''}>🔄 Automatic</option>`;
    options += `<option value="screenshare" ${selType === 6 ? 'selected' : ''}>📺 Screen Share</option>`;
    options += '<option disabled>──────────────</option>';

    // Participants
    for (const p of currentParticipants) {
      const flags = participantFlags(p);
      const label = flags ? `${p.name}  ${flags}` : p.name;
      const selected = (selType === 1 && userId === p.id) ? 'selected' : '';
      options += `<option value="p:${p.id}" ${selected}>${esc(label)}</option>`;
    }

    return `<div class="source-card">
      <div class="source-header">
        <span class="source-name">${esc(src.name)}</span>
      </div>
      <div class="source-body">
        <div class="source-assignment">${assignIcon} Assigned: <strong>${esc(assignText)}</strong></div>
        <select class="source-select" data-source-id="${esc(src.id)}" onchange="onAssign(this)">
          ${options}
        </select>
      </div>
    </div>`;
  }).join('');

  // Meeting info
  const total = currentParticipants.length;
  meetingInfo.textContent = total > 0
    ? `Meeting: ${total} participant${total !== 1 ? 's' : ''}`
    : 'No active Zoom meeting';
}

function renderEmpty(msg) {
  container.innerHTML = `<div class="empty-state">${esc(msg)}</div>`;
  meetingInfo.textContent = '';
}

function participantFlags(p) {
  const parts = [];
  if (p.isVideoOn)  parts.push('🎥');
  if (p.isAudioOn)  parts.push('🔊');
  if (p.isTalking)  parts.push('🗣');
  if (p.isRaisingHand) parts.push('✋');
  return parts.join('');
}

// ── Assignment ───────────────────────────────────────────────────────────────

async function onAssign(selectEl) {
  const sourceId = selectEl.dataset.sourceId;
  const value = selectEl.value;
  selectEl.disabled = true;

  let body = { sourceId };

  if (value === 'auto') {
    body.selectionType = 2;
  } else if (value === 'screenshare') {
    body.selectionType = 6;
  } else if (value.startsWith('p:')) {
    const userId = parseInt(value.slice(2), 10);
    body.selectionType = 1;
    body.userId = userId;
  }

  try {
    const res = await fetch('/api/zoom/assign', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (data.error) throw new Error(data.error);
    // Refresh after a short delay to let mimoLive resolve the assignment
    setTimeout(fetchZoomData, 1000);
  } catch (e) {
    console.error('Assign failed:', e);
    // Refresh to revert select to actual state
    await fetchZoomData();
  } finally {
    selectEl.disabled = false;
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function esc(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── WebSocket (triggers re-fetch on state change) ────────────────────────────

function connectWebSocket() {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(`${proto}//${location.host}/ws`);

  ws.onopen = () => {
    errorBanner.classList.remove('visible');
  };

  ws.onmessage = () => {
    // Any state change from server → re-fetch zoom data
    fetchZoomData();
  };

  ws.onclose = () => {
    ws = null;
    setTimeout(connectWebSocket, 2000);
  };

  ws.onerror = () => {};
}

// ── Polling Fallback ─────────────────────────────────────────────────────────

function startPolling() {
  if (!pollTimer) {
    pollTimer = setInterval(fetchZoomData, 3000);
  }
}

// ── Init ─────────────────────────────────────────────────────────────────────

fetchZoomData();
startPolling();
connectWebSocket();
