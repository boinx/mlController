'use strict';

// ── State ────────────────────────────────────────────────────────────────────

let lastStatus = null;
let showTimerInterval = null;

// ── DOM Refs ─────────────────────────────────────────────────────────────────

const statusDot    = document.getElementById('status-dot');
const statusLabel  = document.getElementById('status-label');
const statusSub    = document.getElementById('status-sub');
const openDocsEl   = document.getElementById('open-docs');
const localDocsEl  = document.getElementById('local-docs');
const openCount    = document.getElementById('open-count');
const localCount   = document.getElementById('local-count');
const lastUpdated  = document.getElementById('last-updated');
const errorBanner  = document.getElementById('error-banner');
const btnStart     = document.getElementById('btn-start');
const btnStop      = document.getElementById('btn-stop');
const btnRestart   = document.getElementById('btn-restart');

// ── Fetch & Render ────────────────────────────────────────────────────────────

async function refresh() {
  try {
    const res = await fetch('/api/status');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    errorBanner.classList.remove('visible');
    dashboardRender(data);
    lastUpdated.textContent = 'Updated ' + new Date().toLocaleTimeString();
  } catch (e) {
    errorBanner.classList.add('visible');
    statusLabel.textContent = 'Connection Error';
    statusSub.textContent = 'mlController may not be running';
    statusDot.className = 'status-indicator stopped';
    setButtonState(false);
    lastUpdated.textContent = 'Failed at ' + new Date().toLocaleTimeString();
  }
}

function dashboardRender(data) {
  const running = !!data.running;

  // Status indicator
  statusDot.className = 'status-indicator ' + (running ? 'running' : 'stopped');
  statusLabel.textContent = running ? 'mimoLive is Running' : 'mimoLive is Stopped';
  const ver = data.selectedMimoLive && data.selectedMimoLive !== 'Default' ? ` · ${data.selectedMimoLive}` : '';
  statusSub.textContent = running
    ? `${data.openDocuments.length} document${data.openDocuments.length !== 1 ? 's' : ''} open${ver}`
    : `Click Start to launch mimoLive${ver}`;

  setButtonState(running);

  // Version picker (only shown when multiple installs found)
  const apps = data.availableMimoLiveApps || [];
  const versionRow = document.getElementById('version-row');
  const versionSelect = document.getElementById('version-select');
  if (apps.length > 1) {
    const currentPath = data.selectedMimoLivePath || '';
    // Rebuild options only when list changes
    if (versionSelect.dataset.count !== String(apps.length)) {
      versionSelect.innerHTML =
        '<option value="">Default</option>' +
        apps.map(a => `<option value="${esc(a.path)}">${esc(a.name)}</option>`).join('');
      versionSelect.dataset.count = apps.length;
    }
    versionSelect.value = currentPath;
    versionRow.style.display = '';
  } else {
    versionRow.style.display = 'none';
  }

  // Open documents
  const openDocs = data.openDocuments || [];
  openCount.textContent = openDocs.length;
  if (openDocs.length === 0) {
    openDocsEl.innerHTML = '<div class="empty-state">No documents open in mimoLive</div>';
  } else {
    openDocsEl.innerHTML = openDocs.map(doc => renderOpenDoc(doc)).join('');
  }

  // Local documents
  const localDocs = data.localDocuments || [];
  localCount.textContent = localDocs.length;
  if (localDocs.length === 0) {
    localDocsEl.innerHTML = '<div class="empty-state">No .tvshow files found in ~/Documents</div>';
  } else {
    const openPaths = new Set((data.openDocuments || []).map(d => d.path).filter(Boolean));
    localDocsEl.innerHTML = localDocs.map(path => {
      const name = baseName(path);
      const isOpen = openPaths.has(path);
      return `<div class="doc-item">
        <img src="/api/docicon" class="doc-icon-img" alt="">
        <span class="doc-name" title="${esc(path)}">${esc(name)}</span>
        ${isOpen
          ? '<span class="badge badge-open">open</span>'
          : `<button class="btn-open" onclick='openDoc(${JSON.stringify(path)})'>Open</button>`
        }
      </div>`;
    }).join('');
  }
}

function setButtonState(running) {
  btnStart.disabled   = running;
  btnStop.disabled    = !running;
  btnRestart.disabled = !running;
}

// ── Commands ──────────────────────────────────────────────────────────────────

async function sendCommand(endpoint) {
  try {
    const res = await fetch(endpoint, { method: 'POST' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    // Refresh sooner after a command
    setTimeout(refresh, 1500);
    setTimeout(refresh, 4000);
  } catch (e) {
    console.error('Command failed:', e);
  }
}

async function selectVersion(path) {
  try {
    await fetch('/api/select', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path })
    });
    setTimeout(refresh, 300);
  } catch (e) {
    console.error('Select version failed:', e);
  }
}

async function openDoc(path) {
  try {
    const res = await fetch('/api/open', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path })
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    setTimeout(refresh, 2000);
  } catch (e) {
    console.error('Open doc failed:', e);
  }
}

// ── Document Rendering ───────────────────────────────────────────────────

function renderOpenDoc(doc) {
  const isLive = doc.liveState === 'live';
  const badge = isLive
    ? '<span class="badge badge-live">live</span>'
    : '<span class="badge badge-open">open</span>';

  // Build metadata items
  const meta = [];
  if (doc.resolution) {
    meta.push(`<span class="doc-meta-item"><span class="meta-icon">🖥</span> ${esc(doc.resolution)}</span>`);
  }
  if (doc.framerate) {
    meta.push(`<span class="doc-meta-item"><span class="meta-icon">⏱</span> ${doc.framerate} fps</span>`);
  }
  if (doc.sourceCount > 0) {
    meta.push(`<span class="doc-meta-item"><span class="meta-icon">📥</span> ${doc.sourceCount} source${doc.sourceCount !== 1 ? 's' : ''}</span>`);
  }
  if (doc.layerCount > 0) {
    meta.push(`<span class="doc-meta-item"><span class="meta-icon">◻️</span> ${doc.layerCount} layer${doc.layerCount !== 1 ? 's' : ''}</span>`);
  }
  // Build show control section
  const showControlHtml = renderShowControl(doc);

  // Build collapsible output destinations section
  const destinations = (doc.outputDestinations || []);
  let destHtml = '';
  if (destinations.length > 0) {
    const destId = 'dest-' + doc.id;
    const isExpanded = localStorage.getItem('outputDest_' + doc.id) === '1';
    const collClass = isExpanded ? '' : ' collapsed';
    destHtml = `<div class="output-destinations">
      <button class="output-dest-toggle${collClass}" onclick="toggleOutputDest('${esc(doc.id)}')">
        <span class="chevron">&#9660;</span> Outputs (${destinations.length})
      </button>
      <div class="output-dest-list${collClass}" id="${esc(destId)}">
        ${destinations.map(d => renderOutputDest(doc.id, d)).join('')}
      </div>
    </div>`;
  }

  return `<div class="doc-item-open">
    <div class="doc-header">
      <span class="doc-icon">📄</span>
      <span class="doc-name" title="${esc(doc.name)}">${esc(doc.name)}</span>
      ${badge}
    </div>
    ${meta.length ? '<div class="doc-meta">' + meta.join('') + '</div>' : ''}
    ${showControlHtml}
    ${destHtml}
  </div>`;
}

function outputLabel(type) {
  switch (type) {
    case 'record':     return 'Recording';
    case 'stream':     return 'Streaming';
    case 'playout':    return 'Playout';
    case 'fullscreen': return 'Fullscreen';
    default:           return type;
  }
}

// ── Show Control ─────────────────────────────────────────────────────────────

function renderShowControl(doc) {
  const isLive = doc.liveState === 'live';
  const destinations = doc.outputDestinations || [];

  // Collect outputs relevant to the show
  const showOutputs = isLive
    ? destinations.filter(d => d.stopsWithShow)
    : destinations.filter(d => d.startsWithShow);

  const btn = isLive
    ? `<button class="btn-show btn-show-stop" onclick="toggleShow('${esc(doc.id)}', 'setOff')">■ Stop Show</button>`
    : `<button class="btn-show btn-show-start" onclick="toggleShow('${esc(doc.id)}', 'setLive')">▶ Start Show</button>`;

  const timerHtml = isLive
    ? `<span class="show-timer" id="show-timer-${esc(doc.id)}" data-show-start="${esc(doc.showStart || '')}">${esc(doc.formattedDuration || '00:00:00')}</span>`
    : '';

  const tagsHtml = showOutputs.length > 0
    ? '<div class="show-output-tags">' +
      showOutputs.map(d => `<span class="show-output-tag">${esc(d.title)}</span>`).join('') +
      '</div>'
    : '';

  // Start/stop the client-side timer
  startShowTimer(isLive ? doc.id : null, doc.showStart);

  return `<div class="show-control${isLive ? ' is-live' : ''}">
    ${btn}
    ${timerHtml}
    ${tagsHtml}
  </div>`;
}

async function toggleShow(docId, action) {
  try {
    const res = await fetch('/api/show/toggle', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ docId, action })
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (data.error) throw new Error(data.error);
    setTimeout(refresh, 500);
    setTimeout(refresh, 2000);
  } catch (e) {
    console.error('Toggle show failed:', e);
  }
}

// ── Show Timer ───────────────────────────────────────────────────────────────

function startShowTimer(liveDocId, showStart) {
  // Clear any existing timer
  if (showTimerInterval) {
    clearInterval(showTimerInterval);
    showTimerInterval = null;
  }
  if (!liveDocId || !showStart) return;

  const startTime = new Date(showStart).getTime();
  if (isNaN(startTime)) return;

  function updateTimer() {
    const el = document.getElementById('show-timer-' + liveDocId);
    if (!el) { clearInterval(showTimerInterval); showTimerInterval = null; return; }
    const elapsed = Math.floor((Date.now() - startTime) / 1000);
    const h = String(Math.floor(elapsed / 3600)).padStart(2, '0');
    const m = String(Math.floor((elapsed % 3600) / 60)).padStart(2, '0');
    const s = String(elapsed % 60).padStart(2, '0');
    el.textContent = `${h}:${m}:${s}`;
  }

  updateTimer();
  showTimerInterval = setInterval(updateTimer, 1000);
}

// ── Output Destinations ──────────────────────────────────────────────────────

function renderOutputDest(docId, dest) {
  const state = dest.liveState || 'off';
  const btnClass = state === 'live' ? 'is-live' : state === 'preview' ? 'is-preview' : 'is-off';
  const btnLabel = state === 'live' ? 'Live' : state === 'preview' ? 'Ready' : 'Off';
  // setLive to start, setOff to stop
  const action = state === 'live' ? 'setOff' : 'setLive';

  const disabledAttr = (!dest.readyToGoLive && state !== 'live') ? ' disabled title="Not ready to go live"' : '';

  return `<div class="output-dest-item">
    <div class="output-dest-info">
      <div class="output-dest-title">${esc(dest.title)}</div>
      ${dest.summary ? `<div class="output-dest-summary" title="${esc(dest.summary)}">${esc(dest.summary)}</div>` : ''}
    </div>
    <button class="btn-toggle-output ${btnClass}"
            onclick="toggleOutputDestination('${esc(docId)}', '${esc(dest.id)}', '${action}')"${disabledAttr}>
      ${btnLabel}
    </button>
  </div>`;
}

function toggleOutputDest(docId) {
  const list = document.getElementById('dest-' + docId);
  const toggle = list && list.previousElementSibling;
  if (!list || !toggle) return;
  const collapsed = toggle.classList.toggle('collapsed');
  list.classList.toggle('collapsed', collapsed);
  localStorage.setItem('outputDest_' + docId, collapsed ? '' : '1');
}

async function toggleOutputDestination(docId, outputId, action) {
  try {
    const res = await fetch('/api/output-destination/toggle', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ docId, outputId, action })
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (data.error) throw new Error(data.error);
    setTimeout(refresh, 500);
    setTimeout(refresh, 2000);
  } catch (e) {
    console.error('Toggle output destination failed:', e);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function esc(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function baseName(path) {
  const parts = path.split('/');
  const file = parts[parts.length - 1];
  const dot = file.lastIndexOf('.');
  return dot > 0 ? file.slice(0, dot) : file;
}
