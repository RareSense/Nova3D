// Global keyboard shortcuts. Bound to window once at boot; ignores key events
// while the focus is on text inputs or while the viewer is in compact mode
// (except Escape, which always closes flyouts / leaves sculpt).

import { state } from '@nova/state.js';
import { popUndo, popRedo, pushUndoSnapshot } from '@nova/history.js';
import { setMode } from '@nova/scene.js';
import { updateMeshList } from '@nova/selection.js';
import { deleteSelected, duplicateSelection } from '@nova/model.js';
import { isFullUi, closeFlyouts } from '@nova/ui/flyouts.js';
import { toggleSculptMode } from '@nova/sculpt.js';

export function setupKeyboard() {
  window.addEventListener('keydown', e => {
    if (e.target?.tagName === 'INPUT' || e.target?.tagName === 'TEXTAREA') return;
    if (!isFullUi() && e.key !== 'Escape') return;
    const key = e.key.toLowerCase();
    if ((e.ctrlKey || e.metaKey) && key === 'z') { e.preventDefault(); e.shiftKey ? popRedo() : popUndo(); return; }
    if ((e.ctrlKey || e.metaKey) && key === 'y') { e.preventDefault(); popRedo(); return; }
    if (key === 'd' && e.shiftKey) { e.preventDefault(); duplicateSelection(); return; }
    switch (key) {
      case 'g': setMode('translate'); break;
      case 'r': setMode('rotate');    break;
      case 's': if (!e.ctrlKey) setMode('scale'); break;
      case 'o': setMode('orbit'); break;
      case 'escape':
        setMode('orbit');
        if (state.sculptMode) toggleSculptMode();
        closeFlyouts();
        break;
      case 'h':
        if (state.selectedMeshIndices.size) {
          pushUndoSnapshot('hide');
          state.selectedMeshIndices.forEach(i => { state.loadedMeshes[i].mesh.visible = false; });
          updateMeshList();
        }
        break;
      case 'x':
      case 'delete':
        deleteSelected();
        break;
      case 'u':
        if (e.shiftKey) popUndo();
        break;
    }
  });
}
