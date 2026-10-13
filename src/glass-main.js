const { ipcMain, nativeTheme } = require('electron');
const { applyNativeGlass } = require('./native/appearance-adapter.cjs');
const addon = process.platform === 'darwin' ? require('./native/native-glass.node') : null;
const defaults = { mode: 'frosted', theme: 'system', tone: 'dark', transparency: { liquid: 85, frosted: 85 } };
let host, state, supported = false, reduced = false, initialized = false;
function normalize(value) {
  const v = value || {};
  return { mode: ['liquid','frosted','system'].includes(v.mode) ? v.mode : defaults.mode,
    theme: ['system','light','dark'].includes(v.theme) ? v.theme : ['light','dark'].includes(v.tone) ? v.tone : defaults.theme,
    tone: ['light','dark'].includes(v.tone) ? v.tone : defaults.tone,
    transparency: Object.fromEntries(['liquid','frosted'].map(mode => [mode,
      Number.isInteger(v.transparency?.[mode]) && v.transparency[mode] >= 0 && v.transparency[mode] <= 100 ? v.transparency[mode] : defaults.transparency[mode]])) };
}
function publicState() {
  return { ...state, transparency: { ...state.transparency }, systemTheme: nativeTheme.shouldUseDarkColors ? 'dark' : 'light', liquidSupported: supported, reducedTransparency: reduced };
}
function apply() {
  const win = host?.window();
  if (!win || win.isDestroyed()) return;
  const mode = host.mode() === 'expanded' && !reduced ? state.mode : 'system';
  if (addon) {
    const effectiveTone = state.theme === 'system' ? (nativeTheme.shouldUseDarkColors ? 'dark' : 'light') : state.theme;
    applyNativeGlass(win, addon, { mode, tone: effectiveTone, transparency: state.transparency[state.mode] ?? 0 });
    addon.setAppearance(win.getNativeWindowHandle(), state.theme);
    addon.setContour(win.getNativeWindowHandle(), host.mode() === 'expanded' ? 28 : 0);
  }
  win.webContents.send('appearance:changed', publicState());
}
function init(options) {
  host = options;
  if (initialized) { apply(); return; }
  initialized = true;
  state = normalize(host.read());
  if (addon) {
    const info = addon.inspect(host.window().getNativeWindowHandle());
    supported = info.glassSupported;
    reduced = info.reduceTransparency;
  }
  if (state.mode === 'liquid' && !supported) state.mode = 'frosted';
  ipcMain.handle('appearance:get', event => {
    if (event.sender !== host.window()?.webContents) throw new Error('Invalid appearance sender');
    return publicState();
  });
  ipcMain.handle('appearance:set', (event, value) => {
    if (event.sender !== host.window()?.webContents) throw new Error('Invalid appearance sender');
    if (!value || !['liquid','frosted','system'].includes(value.mode) || !['light','dark'].includes(value.tone)
      || (value.theme !== undefined && !['system','light','dark'].includes(value.theme))
      || !['liquid','frosted'].every(mode => Number.isInteger(value.transparency?.[mode]) && value.transparency[mode] >= 0 && value.transparency[mode] <= 100)) throw new Error('Invalid appearance preference');
    if (value.mode === 'liquid' && !supported) throw new Error('液态玻璃需要 macOS 26 或更新版本');
    const previous = state;
    state = normalize(value);
    try {
      apply();
      if (!host.write(state)) throw new Error('外观设置保存失败');
      return publicState();
    } catch (error) {
      state = previous;
      apply();
      throw error;
    }
  });
  nativeTheme.on('updated', () => {
    if (addon && host.window() && !host.window().isDestroyed()) reduced = addon.inspect(host.window().getNativeWindowHandle()).reduceTransparency;
    apply();
  });
  apply();
}
module.exports = { init, apply };
