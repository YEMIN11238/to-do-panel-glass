// Vertical reveal gesture. The native window remains centered at the original top anchor.
(() => {
  const api = window.notchAPI;
  const header = document.querySelector('.topbar');
  let gesture = null, suppressClick = false;
  const clamp = value => Math.max(0, Math.min(1, value));
  const paint = (g, p) => {
    if (g.painted === p) return;
    g.painted = p;
    app.style.setProperty('--pull-offset', `${-(1-p)*g.metrics.expanded.height}px`);
    api.updatePanelPull(p);
  };
  const update = g => {
    if (!g.metrics) return;
    const span = g.metrics.expanded.height - g.metrics.collapsed.height;
    g.progress = clamp((g.open ? 1 : 0) + (g.y - g.startY) / Math.max(1, span * .65));
    if (!g.frame) g.frame = requestAnimationFrame(() => {
      g.frame = null;
      if (!g.finishing && gesture === g) paint(g, g.progress);
    });
  };
  const settle = async (g, cancelled = false) => {
    if (gesture !== g || g.finishing) return;
    g.finishing = true;
    if (!g.metrics) { g.cancelled = cancelled; return; }
    const dy = g.y - g.startY;
    // A short stationary press keeps the original click-to-open behavior.
    const tap = Math.abs(dy) <= 8;
    const target = cancelled ? g.open : g.open ? !(dy <= -8) : tap || dy > 32;
    const from = g.progress, to = target ? 1 : 0, began = performance.now();
    try {
    await new Promise(resolve => {
      const frame = now => {
        const t = Math.min(1, (now - began) / 130), eased = 1 - Math.pow(1 - t, 3);
        const p = from + (to - from) * eased;
        paint(g, p);
        if (t < 1) requestAnimationFrame(frame); else resolve();
      };
      requestAnimationFrame(frame);
    });
    await api.finishPanelPull(target);
    isExpanded = target;
    app.classList.remove('pulling', 'expanded', 'collapsed', 'opening', 'closing');
    app.classList.add(target ? 'expanded' : 'collapsed');
    app.style.removeProperty('--pull-width');
    app.style.removeProperty('--pull-height');
    app.style.removeProperty('--pull-progress');
    app.style.removeProperty('--pull-offset');
    if (!target) stopMirror();
    syncPanelAccessibility(target);
    if (!target && document.hasFocus()) notch.focus({ preventScroll: true });
    if (target) {
      requestAnimationFrame(positionIndicator);
      if (activeTab === 'clip') renderClipList();
    }
    document.dispatchEvent(new CustomEvent('notch:modechange', { detail: { expanded: target } }));
    } finally {
    gesture = null;
    modeBusy = false;
    }
    if (pendingMode !== null) {
      const next = pendingMode;
      pendingMode = null;
      if (next !== isExpanded) setMode(next);
    }
  };
  const begin = async event => {
    if (event.button !== 0 || gesture || modeBusy || event.target.closest('button, input, textarea, select, [contenteditable="true"]')) return;
    const g = { pointer: event.pointerId, startY: event.screenY, y: event.screenY, open: isExpanded, progress: isExpanded ? 1 : 0, finishing: false };
    gesture = g;
    modeBusy = true;
    suppressClick = true;
    try { event.currentTarget.setPointerCapture(event.pointerId); } catch {}
    const metrics = await api.beginPanelPull().catch(() => null);
    if (!metrics) { gesture = null; modeBusy = false; suppressClick = false; return; }
    if (!g.open) {
      const openingTab = window.NotchDomain.resolveDefaultPanelTab(defaultOpenTab, TABS);
      if (activeTab !== openingTab) await setActiveTab(openingTab); else applyTabDom(openingTab);
    }
    g.metrics = metrics;
    app.style.setProperty('--pull-width', `${metrics.expanded.width}px`);
    app.style.setProperty('--pull-height', `${metrics.expanded.height}px`);
    app.classList.remove('collapsed', 'opening', 'closing');
    app.classList.add('expanded', 'pulling');
    update(g);
    if (g.finishing) { g.finishing = false; settle(g, g.cancelled); }
  };
  for (const handle of [notch, header, document.querySelector('.panel-bottom-pull')].filter(Boolean)) {
    handle.addEventListener('pointerdown', begin);
    handle.addEventListener('pointermove', event => {
      const g = gesture;
      if (!g || g.finishing || event.pointerId !== g.pointer) return;
      g.y = event.screenY;
      update(g);
    });
    handle.addEventListener('pointerup', event => {
      if (!gesture || event.pointerId !== gesture.pointer) return;
      gesture.y = event.screenY;
      update(gesture);
      settle(gesture);
    });
    // Native button tracking completes pulls even after pointer capture is lost.
    handle.addEventListener('click', event => {
      if (!suppressClick) return;
      suppressClick = false;
      event.preventDefault();
      event.stopImmediatePropagation();
    }, true);
  }
  api.onEdgePull(value => {
    if (value.kind === 'start') {
      begin({ button: 0, pointerId: 'edge', screenY: value.y, target: { closest: () => false }, currentTarget: { setPointerCapture() {} } });
    } else if (gesture && !gesture.finishing) {
      gesture.y = value.y;
      update(gesture);
      if (value.kind === 'end') settle(gesture);
    }
  });
  api.onPanelPullCancel(() => { if (gesture) settle(gesture, true); });
})();
