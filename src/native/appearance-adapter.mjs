/** Native whole-window backgrounds; renderer colors and application state remain caller-owned. */

/**
 * Applies a backdrop to a live, transparent BrowserWindow from the Electron main process.
 * @param {object} browserWindow Live BrowserWindow created with transparent: true and a clear background.
 * @param {{setAppearance: Function, setGlass: Function, setFrostedOpacity: Function}} addon Compiled native-glass.node exports.
 * @param {{mode: 'liquid'|'frosted'|'system', tone: 'light'|'dark', transparency: number}} options Percentage controls a conservative native frosted floor; CSS owns additional neutral fill.
 * @returns {{mode: string, tone: string, transparency: number, frostedViews: number}} Applied configuration and adjusted background-view count.
 */
export function applyNativeGlass(browserWindow, addon, { mode, tone, transparency } = {}) {
  if (mode !== 'liquid' && mode !== 'frosted' && mode !== 'system') throw new TypeError('Glass mode must be liquid, frosted, or system')
  if (tone !== 'light' && tone !== 'dark') throw new TypeError('Glass tone must be light or dark')
  if (!Number.isFinite(transparency) || transparency < 0 || transparency > 100) throw new TypeError('Glass transparency must be a number between zero and one hundred')
  if (process.platform !== 'darwin' || process.type !== 'browser') throw new Error('Native glass requires the macOS Electron main process')
  if (!browserWindow || browserWindow.isDestroyed()) throw new Error('Native glass requires a live BrowserWindow')
  if (!browserWindow.contentView?.setBackgroundColor) throw new Error('This Electron version needs a compatible BrowserWindow.contentView background API')
  for (const method of ['setAppearance', 'setGlass', 'setFrostedOpacity']) {
    if (typeof addon?.[method] !== 'function') throw new TypeError(`The native glass addon is missing ${method}; rebuild it from the supplied source`)
  }

  const handle = browserWindow.getNativeWindowHandle()
  browserWindow.setBackgroundColor('#00000000')
  browserWindow.contentView.setBackgroundColor('#00000000')
  for (const child of browserWindow.contentView.children) child.setBackgroundColor('#00000000')
  const nativeTone = mode === 'system' ? 'system' : tone
  addon.setAppearance(handle, nativeTone)
  browserWindow.setVibrancy(null, { animationDuration: 0 })
  addon.setGlass(handle, mode === 'liquid')

  let frostedViews = 0
  if (mode === 'frosted') {
    browserWindow.setVibrancy('sidebar', { animationDuration: 0 })
    // This local visual starting point retains blur instead of fading most of it away.
    frostedViews = addon.setFrostedOpacity(handle, 0.95 - transparency * 0.001)
    if (!frostedViews) throw new Error('No independent behind-window visual effect was found; inspect the native tree before changing any content-view alpha')
  }
  return { mode, tone: nativeTone, transparency, frostedViews }
}
