// localStorage sarmalayıcısı: gizli sekmede ya da engellenmiş depolamada sessizce varsayılana döner.
export const store = {
  get(key, fallback = null) {
    try {
      const v = localStorage.getItem(key);
      return v == null ? fallback : JSON.parse(v);
    } catch { return fallback; }
  },
  set(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* gizli sekme vb. */ }
  },
};
