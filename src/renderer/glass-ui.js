(() => {
  const root = document.documentElement;
  const api = window.notchAPI;
  let state, revision = 0;
  const status = document.getElementById('glass-status');
  const slider = document.getElementById('glass-transparency');
  function render(value) {
    state = value;
    const mode = value.reducedTransparency ? 'system' : value.mode;
    const tone = value.theme === 'system' ? value.systemTheme : value.theme;
    root.dataset.appearanceMode = mode;
    root.dataset.appearanceTone = tone;
    // Only bundled defaults follow the theme; a user-selected cover stays intact.
    const defaultCover = tone === 'dark' ? 'assets/mirror-night.jpg' : 'assets/mirror-portrait.jpg';
    document.querySelectorAll('.mirror-photo, #settings-mirror-preview').forEach(image => {
      if (image.dataset.customCover !== 'true' && !(image.getAttribute('src') || '').startsWith('data:image/')) {
        image.src = defaultCover;
      }
    });
    root.style.setProperty('--glass-transparency', String((value.transparency[value.mode] ?? 0) / 100));
    document.querySelectorAll('[data-glass-mode]').forEach(button => {
      button.setAttribute('aria-pressed', String(button.dataset.glassMode === value.mode));
      button.disabled = button.dataset.glassMode === 'liquid' && !value.liquidSupported;
      button.title = button.disabled ? '液态玻璃需要 macOS 26 或更新版本' : '';
    });
    document.querySelectorAll('[data-glass-tone]').forEach(button => {
      button.setAttribute('aria-pressed', String(button.dataset.glassTone === value.theme));
      button.disabled = false;
    });
    slider.disabled = mode === 'system';
    slider.value = value.transparency[value.mode] ?? value.transparency.frosted;
    document.getElementById('glass-value').value = mode === 'system' ? '自动' : `${slider.value}%`;
    status.textContent = value.reducedTransparency ? '已遵循系统降低透明度设置' : value.theme === 'system' ? '颜色随系统变化' : value.theme === 'light' ? '已使用浅色外观' : '已使用深色外观';
  }
  function set(change) {
    const request = ++revision;
    const value = { mode: state.mode, theme: state.theme, tone: state.tone, transparency: { ...state.transparency }, ...change };
    render({ ...state, ...value });
    // Send each input immediately; the main process applies and atomically writes it synchronously.
    api.setAppearance(value).then(result => { if (request === revision) render(result); }).catch(async error => {
      if (request !== revision) return;
      render(await api.getAppearance());
      status.textContent = '未能保存，请重试';
      console.error(error);
    });
  }
  document.querySelectorAll('[data-glass-mode]').forEach(button => button.addEventListener('click', () => state && set({ mode: button.dataset.glassMode })));
  document.querySelectorAll('[data-glass-tone]').forEach(button => button.addEventListener('click', () => state && set({ theme: button.dataset.glassTone, ...(button.dataset.glassTone === 'system' ? {} : { tone: button.dataset.glassTone }) })));
  slider.addEventListener('input', () => state && set({ transparency: { ...state.transparency, [state.mode]: Number(slider.value) } }));
  // Read authoritative state after unsolicited theme events, keeping pending input previews intact.
  api.onAppearanceChanged(value => {
    if (!state || (value.mode === state.mode && value.tone === state.tone && value.theme === state.theme && JSON.stringify(value.transparency) === JSON.stringify(state.transparency))) render(value);
  });
  api.getAppearance().then(render).catch(error => { status.textContent = '外观设置读取失败'; console.error(error); });
})();
