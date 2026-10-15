import { useState, useEffect } from "react";
import { House, Users, Settings } from "lucide-react";
import { AppProvider, useApp, useLiveData } from "./lib/AppContext";
import SignIn from "./screens/SignIn";
import Onboarding from "./screens/Onboarding";
import HomeTab from "./screens/HomeTab";
import FamilieTab from "./screens/FamilieTab";
import SettingsTab from "./screens/SettingsTab";
import ChildDetail from "./screens/ChildDetail";
import NewChild from "./screens/NewChild";
import Highlights from "./screens/Highlights";
import Diary from "./screens/Diary";
import Gallery from "./screens/Gallery";
import AboutMe from "./screens/AboutMe";
import Milestones from "./screens/Milestones";

const TABS = [
  { key: "home", label: "Hjem", Icon: House },
  { key: "familie", label: "Familie", Icon: Users },
  { key: "settings", label: "Mere", Icon: Settings },
];

function Shell() {
  const { user, familyId, ready, store } = useApp();
  const [tab, setTab] = useState("home");
  const [stack, setStack] = useState([]);

  const nav = {
    push: (name, params = {}) => setStack((s) => [...s, { name, params }]),
    pop: () => setStack((s) => s.slice(0, -1)),
    reset: () => setStack([]),
  };
  const switchTab = (t) => { setTab(t); setStack([]); };

  // Edge-swipe-tilbage (iOS-stil): swipe fra venstre kant mod højre → ét niveau tilbage.
  // I SwiftUI-appen (fase 2) kommer dette gratis via NavigationStack.
  useEffect(() => {
    if (stack.length === 0) return;
    let sx = 0, sy = 0, t = 0, tracking = false;
    const start = (e) => {
      const touch = e.touches[0];
      if (touch.clientX > 32) return; // kun fra venstre kant
      if (document.querySelector(".modal-backdrop, .lightbox")) return;
      sx = touch.clientX; sy = touch.clientY; t = Date.now(); tracking = true;
    };
    const end = (e) => {
      if (!tracking) return;
      tracking = false;
      const touch = e.changedTouches[0];
      const dx = touch.clientX - sx, dy = touch.clientY - sy, dt = Date.now() - t;
      if (dx > 70 && Math.abs(dy) < 60 && dt < 800) setStack((s) => s.slice(0, -1));
    };
    window.addEventListener("touchstart", start, { passive: true });
    window.addEventListener("touchend", end, { passive: true });
    return () => {
      window.removeEventListener("touchstart", start);
      window.removeEventListener("touchend", end);
    };
  }, [stack.length]);

  const { data: families } = useLiveData(
    () => (user ? store.listFamilies(user.id) : Promise.resolve([])),
    [user?.id]
  );

  if (!ready) return <div className="phone" />;
  if (!user) return <div className="phone"><SignIn /></div>;
  // Ingen familie endnu → onboarding (opret eller deltag via kode).
  if (families && families.length === 0 && !familyId) {
    return <div className="phone"><Onboarding /></div>;
  }

  // Drill-down skærme (tabbar skjult).
  if (stack.length) {
    const top = stack[stack.length - 1];
    const p = top.params;
    let screen;
    switch (top.name) {
      case "child": screen = <ChildDetail nav={nav} childId={p.childId} />; break;
      case "newChild": screen = <NewChild nav={nav} />; break;
      case "highlights": screen = <Highlights nav={nav} childId={p.childId} autoAdd={p.autoAdd} />; break;
      case "diary": screen = <Diary nav={nav} childId={p.childId} autoAdd={p.autoAdd} />; break;
      case "gallery": screen = <Gallery nav={nav} childId={p.childId} kind={p.kind} autoAdd={p.autoAdd} />; break;
      case "aboutMe": screen = <AboutMe nav={nav} childId={p.childId} />; break;
      case "milestones": screen = <Milestones nav={nav} childId={p.childId} />; break;
      default: screen = null;
    }
    return <div className="phone">{screen}</div>;
  }

  // Root-faner (med tabbar).
  let root;
  if (tab === "familie") root = <FamilieTab nav={nav} />;
  else if (tab === "settings") root = <SettingsTab nav={nav} />;
  else root = <HomeTab nav={nav} />;

  return (
    <div className="phone">
      <div className="tab-content">{root}</div>
      <nav className="tabbar">
        {TABS.map((t) => (
          <button
            key={t.key}
            className={`tabbar-btn ${tab === t.key ? "active" : ""}`}
            onClick={() => switchTab(t.key)}
          >
            <t.Icon className="tabbar-icon" size={23} strokeWidth={tab === t.key ? 2 : 1.6} />
            <span className="tabbar-label">{t.label}</span>
          </button>
        ))}
      </nav>
    </div>
  );
}

export default function App() {
  return (
    <AppProvider>
      <Shell />
    </AppProvider>
  );
}
