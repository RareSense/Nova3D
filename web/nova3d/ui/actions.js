// Single delegated dispatcher for the whole viewer. Modules register actions
// from their setup* functions; markup uses data-action / data-input-action
// instead of inline onclick=. One listener on .app catches both static and
// dynamically generated elements.

const registry = new Map();

export function registerAction(name, handler) {
  if (!name) return;
  if (registry.has(name)) {
    // Last writer wins, but warn during development so duplicates aren't silent.
    console.warn('[nova3d] action re-registered:', name);
  }
  registry.set(name, handler);
}

export function unregisterAction(name) {
  registry.delete(name);
}

export function listActions() {
  return Array.from(registry.keys()).sort();
}

function dispatch(el, eventName, evt) {
  const attr = eventName === 'input' ? 'inputAction' : 'action';
  const name = el?.dataset?.[attr];
  if (!name) return;
  const handler = registry.get(name);
  if (!handler) return;
  try {
    handler(el, evt);
  } catch (e) {
    console.error(`[nova3d] action "${name}" threw:`, e);
  }
}

export function installActionDelegation(root) {
  root.addEventListener('click', (evt) => {
    const el = evt.target.closest('[data-action]');
    if (!el || !root.contains(el)) return;
    dispatch(el, 'click', evt);
  });
  root.addEventListener('input', (evt) => {
    const el = evt.target.closest('[data-input-action]');
    if (!el || !root.contains(el)) return;
    dispatch(el, 'input', evt);
  });
  root.addEventListener('change', (evt) => {
    const el = evt.target.closest('[data-input-action]');
    if (!el || !root.contains(el)) return;
    dispatch(el, 'input', evt);
  });
}
