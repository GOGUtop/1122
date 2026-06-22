(() => {
  ['dog-actions','dog-translation','dog-error-panel','dog-card-toast','dog-card-panel'].forEach(id => document.getElementById(id)?.remove());
  document.getElementById('dog-lite-tools-style')?.remove();
  window.__tavernLiteTools = { nativeResult(){}, scanErrors(){}, hideAll(){} };
})();
