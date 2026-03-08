'use strict';

// ── Tab Switching ────────────────────────────────────────────────────────────

const tabBar       = document.getElementById('tab-bar');
const tabBtnZoom   = document.getElementById('tab-btn-zoom');
const tabDashboard = document.getElementById('tab-dashboard');
const tabZoom      = document.getElementById('tab-zoom');
let activeTab      = 'dashboard';
let mimoRunning    = false;

function switchTab(tabName) {
  if (tabName === 'zoom' && !mimoRunning) return;
  activeTab = tabName;

  // Update tab buttons
  tabBar.querySelectorAll('.tab-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tab === tabName);
  });

  // Update tab content
  tabDashboard.classList.toggle('active', tabName === 'dashboard');
  tabZoom.classList.toggle('active', tabName === 'zoom');
}

tabBar.addEventListener('click', (e) => {
  const btn = e.target.closest('.tab-btn');
  if (btn && btn.dataset.tab) {
    switchTab(btn.dataset.tab);
  }
});

// ── Zoom Tab Visibility ──────────────────────────────────────────────────────

function updateZoomTabVisibility(running) {
  mimoRunning = running;
  tabBtnZoom.style.display = running ? '' : 'none';
  // If zoom tab is active but mimoLive stopped, switch to dashboard
  if (!running && activeTab === 'zoom') {
    switchTab('dashboard');
  }
}

// ── Shared WebSocket ─────────────────────────────────────────────────────────

let ws = null;
let pollTimer = null;

function connectWebSocket() {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(`${proto}//${location.host}/ws`);

  ws.onopen = () => {
    stopPolling();
    errorBanner.classList.remove('visible');
  };

  ws.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data);
      errorBanner.classList.remove('visible');

      // Route to dashboard
      dashboardRender(data);
      lastUpdated.textContent = 'Updated ' + new Date().toLocaleTimeString();

      // Update zoom tab visibility
      updateZoomTabVisibility(!!data.running);

      // Trigger zoom data refresh
      if (data.running) {
        fetchZoomData();
      }
    } catch (e) {
      console.error('WebSocket parse error:', e);
    }
  };

  ws.onclose = () => {
    ws = null;
    startPolling();
    setTimeout(connectWebSocket, 2000);
  };

  ws.onerror = () => {};
}

// ── Polling Fallback ─────────────────────────────────────────────────────────

function startPolling() {
  if (!pollTimer) {
    pollTimer = setInterval(() => {
      refresh();
      fetchZoomData();
    }, 3000);
  }
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

// ── Init ─────────────────────────────────────────────────────────────────────

refresh();
fetchZoomData();
startPolling();
connectWebSocket();
