import { createContext, useContext, useEffect, useState, useCallback } from "react";
import { store } from "./store";

const AppContext = createContext(null);
const SESSION_KEY = "familieapp.session";

export function AppProvider({ children }) {
  const [user, setUser] = useState(null);
  const [ready, setReady] = useState(false);

  // Genskab session (hvilken bruger er "logget ind" lige nu).
  useEffect(() => {
    (async () => {
      const id = localStorage.getItem(SESSION_KEY);
      if (id) setUser(await store.getUser(id));
      setReady(true);
    })();
  }, []);

  const signIn = useCallback(async (name) => {
    const u = await store.signIn(name);
    localStorage.setItem(SESSION_KEY, u.id);
    setUser(u);
    return u;
  }, []);

  const switchUser = useCallback(async (id) => {
    const u = await store.getUser(id);
    if (u) {
      localStorage.setItem(SESSION_KEY, u.id);
      setUser(u);
    }
  }, []);

  const signOut = useCallback(() => {
    localStorage.removeItem(SESSION_KEY);
    setUser(null);
  }, []);

  return (
    <AppContext.Provider value={{ user, ready, store, signIn, switchUser, signOut }}>
      {children}
    </AppContext.Provider>
  );
}

export function useApp() {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error("useApp skal bruges inde i AppProvider");
  return ctx;
}

// Hook der genindlæser data når store'en ændrer sig (realtids-ish).
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
    window.addEventListener("storage", onChange); // ændringer fra andre faner
    return () => {
      window.removeEventListener("familieapp:changed", onChange);
      window.removeEventListener("storage", onChange);
    };
  }, [refresh]);

  return { data, loading, refresh };
}
