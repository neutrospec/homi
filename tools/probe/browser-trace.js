(() => {
  const comparison = location.protocol === 'file:' && location.pathname.endsWith('/tools/probe/browser.html');
  const clien = location.hostname === 'www.clien.net' && location.pathname === '/service/board/regist';
  if (!comparison && !clien)
    return JSON.stringify({ status: 'skipped', reason: 'active tab changed' });
  const rich = document.querySelector(comparison ? '#editable-rich' : '.fr-element[contenteditable=true]');
  const title = comparison ? null : document.getElementById('subject');
  if (!rich) return JSON.stringify({ status: 'skipped', reason: 'editor missing' });
  window.__homiImeTrace?.stop();
  const rows = [];
  const listeners = [];
  const jquery = window.jQuery;
  const version = jquery?.FroalaEditor?.VERSION ?? jquery?.FE?.VERSION ?? window.FroalaEditor?.VERSION ?? 'unknown';
  let active = true;
  function field(target) {
    if (comparison) {
      const name = target.closest?.('[data-probe]')?.id;
      return ['plain-input', 'plain-textarea', 'editable-plain', 'editable-rich'].includes(name) ? name : null;
    }
    if (target === rich || rich.contains(target)) return 'rich';
    if (target === title) return 'title';
    return null;
  }
  function record(event, phase, name) {
    if (!active) return;
    const selection = getSelection();
    const control = event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement;
    rows.push({
      time: Date.now(), event: event.type, phase, field: name,
      inputType: event.inputType ?? null,
      isComposing: typeof event.isComposing === 'boolean' ? event.isComposing : null,
      trusted: event.isTrusted, defaultPrevented: event.defaultPrevented,
      selectionInRich: !!selection?.anchorNode && rich.contains(selection.anchorNode),
      selectionCollapsed: control ? event.target.selectionStart === event.target.selectionEnd : selection?.isCollapsed ?? null,
      focusedRich: document.activeElement === rich
    });
    if (rows.length > 240) rows.shift();
  }
  function listen(target, type, callback) {
    target.addEventListener(type, callback, { capture: true, passive: true });
    listeners.push(() => target.removeEventListener(type, callback, true));
  }
  for (const type of ['focus', 'blur', 'compositionstart', 'compositionupdate',
    'compositionend', 'beforeinput', 'input']) {
    listen(document, type, event => {
      const name = field(event.target);
      if (!name) return;
      record(event, 'capture', name);
      if (type === 'beforeinput' || type === 'compositionend')
        queueMicrotask(() => record(event, 'after dispatch', name));
    });
  }
  for (const type of ['focus', 'blur'])
    listen(window, type, event => {
      if (event.target === window) record(event, 'capture', 'window');
    });
  window.__homiImeTrace = {
    version,
    read: () => rows.slice(),
    clear: () => { rows.length = 0; },
    stop: () => { active = false; listeners.forEach(remove => remove()); }
  };
  return JSON.stringify({ status: 'watching', version, records: 'event and state only' });
})()
