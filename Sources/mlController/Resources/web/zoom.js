'use strict';

// ── State ────────────────────────────────────────────────────────────────────

let currentSources = [];
let currentParticipants = [];
let renderPending = false;    // true when a render was skipped due to open dropdown
let assignInFlight = false;   // true while an assignment API call is in progress

// ── DOM Refs ─────────────────────────────────────────────────────────────────

const zoomContainer      = document.getElementById('sources-container');
const meetingInfo        = document.getElementById('meeting-info');
const recordingWarning   = document.getElementById('recording-warning');
const joinSections       = document.getElementById('join-sections');
const meetingActiveCard  = document.getElementById('meeting-active-card');
const meetingActiveSub   = document.getElementById('meeting-active-sub');
const btnLeave           = document.getElementById('btn-leave');
const btnJoinDemo        = document.getElementById('btn-join-demo');
const joinDemoSub        = document.getElementById('join-demo-sub');
const btnJoinCustom      = document.getElementById('btn-join-custom');
const joinCustomSub      = document.getElementById('join-custom-sub');
const zoomMeetingId      = document.getElementById('zoom-meeting-id');
const zoomPasscode       = document.getElementById('zoom-passcode');
const zoomDisplayName    = document.getElementById('zoom-display-name');
const zoomAccountName    = document.getElementById('zoom-account-name');

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
      zoomRenderEmpty(srcData.error);
      return;
    }

    currentSources = srcData.sources || [];
    currentParticipants = (partData.participants || [])
      .filter(p => p.name)
      .sort((a, b) => a.name.localeCompare(b.name));

    errorBanner.classList.remove('visible');
    zoomRender();
    lastUpdated.textContent = 'Updated ' + new Date().toLocaleTimeString();
  } catch (e) {
    // Don't show error banner from zoom fetch — dashboard handles connection errors
  }
}

// ── Render ────────────────────────────────────────────────────────────────────

function isDropdownOpen() {
  const focused = document.activeElement;
  return focused && focused.classList.contains('source-select');
}

function zoomRender() {
  // Defer render while user is interacting with a dropdown or assignment is in-flight
  if (isDropdownOpen() || assignInFlight) {
    renderPending = true;
    return;
  }
  renderPending = false;

  // Toggle join / in-meeting sections based on participant count
  const inMeeting = currentParticipants.length > 0;
  joinSections.classList.toggle('hidden', inMeeting);
  meetingActiveCard.classList.toggle('hidden', !inMeeting);
  if (inMeeting) {
    const host = currentParticipants.find(p => p.userRole === 'Host');
    const count = currentParticipants.length;
    const parts = [];
    parts.push(`${count} participant${count !== 1 ? 's' : ''}`);
    if (host) parts.push(`Host: ${host.name}`);
    meetingActiveSub.textContent = parts.join(' · ');
  }

  if (currentSources.length === 0) {
    zoomRenderEmpty('No Zoom sources in the current document');
    recordingWarning.classList.remove('visible');
    return;
  }

  // Detect recording permission warning
  const awaitingPermission = currentSources.some(src =>
    (src['summary'] || '').includes('Awaiting Recording Permission')
  );
  recordingWarning.classList.toggle('visible', awaitingPermission);

  zoomContainer.innerHTML = currentSources.map(src => {
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

function zoomRenderEmpty(msg) {
  zoomContainer.innerHTML = `<div class="empty-state">${esc(msg)}</div>`;
  meetingInfo.textContent = '';
  recordingWarning.classList.remove('visible');
  joinSections.classList.remove('hidden');
  meetingActiveCard.classList.add('hidden');
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
  assignInFlight = true;

  let body = { sourceId };
  let optimisticName = '';

  if (value === 'auto') {
    body.selectionType = 2;
    optimisticName = 'Automatic';
  } else if (value === 'screenshare') {
    body.selectionType = 6;
    optimisticName = 'Screen Share';
  } else if (value.startsWith('p:')) {
    const userId = parseInt(value.slice(2), 10);
    body.selectionType = 1;
    body.userId = userId;
    // Find participant name for optimistic display
    const p = currentParticipants.find(pp => pp.id === userId);
    optimisticName = p ? p.name : '';
  }

  // Optimistic UI: immediately update the "Assigned:" label
  const card = selectEl.closest('.source-card');
  if (card && optimisticName) {
    const assignEl = card.querySelector('.source-assignment');
    if (assignEl) {
      const icon = value === 'auto' ? '🔄' : value === 'screenshare' ? '📺' : '📹';
      const label = value === 'auto' && optimisticName !== 'Automatic'
        ? `${optimisticName} (Automatic)` : optimisticName;
      assignEl.innerHTML = `${icon} Assigned: <strong>${esc(label)}</strong>`;
    }
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
    // Fetch fresh data after mimoLive resolves the username (~500ms)
    assignInFlight = false;
    setTimeout(fetchZoomData, 500);
  } catch (e) {
    console.error('Assign failed:', e);
    assignInFlight = false;
    // Refresh to revert select to actual state
    await fetchZoomData();
  }
}

// ── Join Meeting ─────────────────────────────────────────────────────────────

async function joinZoomDemo() {
  btnJoinDemo.disabled = true;
  joinDemoSub.textContent = 'Joining Zoom demo meeting…';
  try {
    const res = await fetch('/api/zoom/join', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        meetingId: 'Demo-Meeting-ID',
        passcode: 'Demo-Meeting-Passcode'
      })
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (data.error) throw new Error(data.error);
    joinDemoSub.textContent = 'Zoom demo meeting joined';
  } catch (e) {
    joinDemoSub.textContent = 'Failed to join: ' + e.message;
    console.error('Zoom join failed:', e);
  } finally {
    btnJoinDemo.disabled = false;
  }
}

async function joinZoomCustom() {
  const meetingId = zoomMeetingId.value.trim();
  if (!meetingId) {
    joinCustomSub.textContent = 'Meeting ID is required';
    return;
  }
  btnJoinCustom.disabled = true;
  joinCustomSub.textContent = 'Joining Zoom meeting…';
  try {
    const body = { meetingId, virtualCamera: true };
    if (zoomPasscode.value.trim())    body.passcode = zoomPasscode.value.trim();
    if (zoomDisplayName.value.trim()) body.displayName = zoomDisplayName.value.trim();
    if (zoomAccountName.value.trim()) body.zoomAccountName = zoomAccountName.value.trim();
    const res = await fetch('/api/zoom/join', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (data.error) throw new Error(data.error);
    joinCustomSub.textContent = 'Zoom meeting joined';
  } catch (e) {
    joinCustomSub.textContent = 'Failed to join: ' + e.message;
    console.error('Zoom custom join failed:', e);
  } finally {
    btnJoinCustom.disabled = false;
  }
}

// ── Leave Meeting ────────────────────────────────────────────────────────────

async function leaveZoomMeeting() {
  btnLeave.disabled = true;
  meetingActiveSub.textContent = 'Leaving meeting…';
  try {
    const res = await fetch('/api/zoom/leave', { method: 'POST' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (data.error) throw new Error(data.error);
    meetingActiveSub.textContent = 'Left meeting';
    setTimeout(fetchZoomData, 2000);
  } catch (e) {
    meetingActiveSub.textContent = 'Failed to leave: ' + e.message;
    console.error('Leave meeting failed:', e);
  } finally {
    btnLeave.disabled = false;
  }
}

// ── Request Recording Permission ─────────────────────────────────────────────

async function requestRecordingPermission() {
  const btn = document.getElementById('btn-request-recording');
  const status = document.getElementById('recording-request-status');
  btn.disabled = true;
  status.textContent = 'Requesting…';
  try {
    const res = await fetch('/api/zoom/request-recording', { method: 'POST' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (data.error) throw new Error(data.error);
    status.textContent = 'Permission requested — waiting for host to approve';
    setTimeout(fetchZoomData, 2000);
  } catch (e) {
    status.textContent = 'Failed: ' + e.message;
    console.error('Request recording permission failed:', e);
  } finally {
    btn.disabled = false;
  }
}

// ── Deferred Render Flush ─────────────────────────────────────────────────────
// When a dropdown closes without making a selection, flush any pending render.
document.addEventListener('focusout', (e) => {
  if (e.target && e.target.classList.contains('source-select') && renderPending) {
    // Small delay to let change event fire first if user made a selection
    setTimeout(() => { if (renderPending && !assignInFlight) zoomRender(); }, 100);
  }
});

// ── Zoom Field Persistence ────────────────────────────────────────────────────

const zoomFields = [
  { el: zoomMeetingId,   key: 'zoom_meetingId' },
  { el: zoomPasscode,    key: 'zoom_passcode' },
  { el: zoomDisplayName, key: 'zoom_displayName' },
  { el: zoomAccountName, key: 'zoom_accountName' },
];

// Restore saved values
zoomFields.forEach(({ el, key }) => {
  const saved = localStorage.getItem(key);
  if (saved) el.value = saved;
});

// Persist on every keystroke
zoomFields.forEach(({ el, key }) => {
  el.addEventListener('input', () => localStorage.setItem(key, el.value));
});
