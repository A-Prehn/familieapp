import { createContext, useContext, useEffect, useState, useCallback } from "react";
import { store } from "./store";

const AppContext = createContext(null);
const SESSION_KEY = "familieapp.session";
const FAMILY_KEY = "familieapp.family";

export function AppProvider({ children }) {
  const [user, setUser] = useState(null);
  const [familyId, setFamilyIdState] = useState(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    (async () => {
      const id = localStorage.getItem(SESSION_KEY);
      if (id) {
        const u = await store.getUser(id);
        setUser(u);
        if (u) {
          const fams = await store.listFamilies(u.id);
          const savedFam = localStorage.getItem(FAMILY_KEY);
          const pick = fams.find((f) => f.id === savedFam) || fams[0];
          if (pick) setFamilyIdState(pick.id);
        }
      }
      setReady(true);
    })();
  }, []);

  const setFamilyId = useCallback((id) => {
    if (id) localStorage.setItem(FAMILY_KEY, id);
    else localStorage.removeItem(FAMILY_KEY);
    setFamilyIdState(id);
  }, []);

  const signIn = useCallback(async (name) => {
    const u = await store.signIn(name);
    localStorage.setItem(SESSION_KEY, u.id);
    setUser(u);
    setFamilyIdState(null);
    return u;
  }, []);

  const switchUser = useCallback(async (id) => {
    const u = await store.getUser(id);
    if (!u) return;
    localStorage.setItem(SESSION_KEY, u.id);
    setUser(u);
    const fams = await store.listFamilies(u.id);
    setFamilyId(fams[0]?.id || null);
  }, [setFamilyId]);

  const signOut = useCallback(() => {
    localStorage.removeItem(SESSION_KEY);
    localStorage.removeItem(FAMILY_KEY);
    setUser(null);
    setFamilyIdState(null);
  }, []);

  return (
    <AppContext.Provider value={{ user, familyId, ready, store, signIn, switchUser, signOut, setFamilyId }}>
      {children}
    </AppContext.Provider>
  );
}

export function useApp() {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error("useApp skal bruges inde i AppProvider");
  return ctx;
}

// Genindlæser data når store'en ændrer sig (realtids-ish).
export function useLiveData(loader, deps = []) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    const result = await loader();
    setData(result);
    setLoading(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(() => {
    refresh();
    const onChange = () => refresh();
    window.addEventListener("familieapp:changed", onChange);
    window.addEventListener("storage", onChange);
    return () => {
      window.removeEventListener("familieapp:changed", onChange);
      window.removeEventListener("storage", onChange);
    };
  }, [refresh]);

  return { data, loading, refresh };
}
