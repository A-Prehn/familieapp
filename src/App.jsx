import { useState } from "react";
import { AppProvider, useApp } from "./lib/AppContext";
import SignIn from "./screens/SignIn";
import ChildList from "./screens/ChildList";
import NewChild from "./screens/NewChild";
import ChildDetail from "./screens/ChildDetail";
import NewPost from "./screens/NewPost";
import ShareChild from "./screens/ShareChild";

function Router() {
  const { user, ready } = useApp();
  // Simpel navigationsstak: hvert element er { name, params }.
  const [stack, setStack] = useState([{ name: "home" }]);

  const push = (name, params = {}) => setStack((s) => [...s, { name, params }]);
  const pop = () => setStack((s) => (s.length > 1 ? s.slice(0, -1) : s));
  const reset = () => setStack([{ name: "home" }]);
  const nav = { push, pop, reset };

  if (!ready) return <div className="phone" />;
  if (!user) return <div className="phone"><SignIn /></div>;

  const top = stack[stack.length - 1];
  let screen;
  switch (top.name) {
    case "newChild": screen = <NewChild nav={nav} />; break;
    case "child": screen = <ChildDetail nav={nav} childId={top.params.childId} />; break;
    case "newPost": screen = <NewPost nav={nav} childId={top.params.childId} />; break;
    case "share": screen = <ShareChild nav={nav} childId={top.params.childId} />; break;
    default: screen = <ChildList nav={nav} />;
  }

  return <div className="phone">{screen}</div>;
}

export default function App() {
  return (
    <AppProvider>
      <Router />
    </AppProvider>
  );
}
