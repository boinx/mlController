'use strict';

// ── State ────────────────────────────────────────────────────────────────────

let lastStatus = null;

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
    render(data);
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

function render(data) {
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
    openDocsEl.innerHTML = openDocs.map(doc =>
      `<div class="doc-item">
        <span class="doc-icon">📄</span>
        <span class="doc-name" title="${esc(doc.name)}">${esc(doc.name)}</span>
        <span class="badge badge-open">open</span>
      </div>`
    ).join('');
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

// ── Init ──────────────────────────────────────────────────────────────────────

refresh();
setInterval(refresh, 5000);
