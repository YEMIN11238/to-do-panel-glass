// A small moving highlight; no position changes or work when the material is hidden.
(() => {
  const tabs = document.getElementById('tabs');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  let frame = 0, x = 50, y = 0;
  tabs.addEventListener('pointermove', event => {
    if (reduce.matches || document.documentElement.dataset.appearanceMode !== 'liquid' || !isExpanded) return;
    const box = tabs.getBoundingClientRect();
    x = (event.clientX - box.left) / box.width * 100;
    y = (event.clientY - box.top) / box.height * 100;
    if (!frame) frame = requestAnimationFrame(() => {
      frame = 0;
      tabs.style.setProperty('--gleam-x', `${x}%`);
      tabs.style.setProperty('--gleam-y', `${y}%`);
    });
  });
  tabs.addEventListener('pointerleave', () => {
    if (frame) cancelAnimationFrame(frame);
    frame = 0;
    tabs.style.removeProperty('--gleam-x'); tabs.style.removeProperty('--gleam-y');
  });
})();
