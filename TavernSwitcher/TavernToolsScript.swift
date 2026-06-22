import Foundation

enum TavernToolsScript {
    static let source = #"""
(() => {
  // v3.0：关闭不稳定的网页内划词卡片、划词翻译和红色报错自动翻译。
  // 保留一个安全的空对象，避免旧页面或原生端调用时报错。
  const removeDogTools = () => {
    try {
      ['dog-actions','dog-translation','dog-error-panel','dog-card-toast','dog-card-panel'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.remove();
      });
      const style = document.getElementById('dog-lite-tools-style');
      if (style) style.remove();
    } catch (_) {}
  };
  removeDogTools();
  if (window.__tavernLiteToolsDisabledInstalled) return;
  window.__tavernLiteToolsDisabledInstalled = true;
  window.__tavernLiteTools = {
    nativeResult() {},
    scanErrors() {},
    hideAll() { removeDogTools(); }
  };
})();
"""#
}
