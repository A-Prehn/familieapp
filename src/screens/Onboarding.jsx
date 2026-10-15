import { useState } from "react";
import { useApp } from "../lib/AppContext";

export default function Onboarding() {
  const { user, store, setFamilyId } = useApp();
  const [mode, setMode] = useState("create");
  const [name, setName] = useState("");
  const [code, setCode] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function create() {
    setBusy(true);
    const fam = await store.createFamily(user.id, name);
    setFamilyId(fam.id);
  }
  async function join() {
    setError(""); setBusy(true);
    try {
      const fam = await store.acceptInvite(user.id, code);
      setFamilyId(fam.id);
    } catch (e) {
      setError(e.message); setBusy(false);
    }
  }

  return (
    <div className="content" style={{ paddingTop: 40 }}>
      <div className="hero-emoji">👨‍👩‍👧</div>
      <h1 className="large-title" style={{ textAlign: "center" }}>Din familie</h1>
      <p className="tagline">Opret en ny familie, eller deltag i en der allerede er delt med dig.</p>

      <div className="seg" style={{ marginBottom: 20 }}>
        <button className={mode === "create" ? "active" : ""} onClick={() => setMode("create")}>Opret ny</button>
        <button className={mode === "join" ? "active" : ""} onClick={() => setMode("join")}>Deltag</button>
      </div>

      {mode === "create" ? (
        <>
          <label className="field">
            <span>Familiens navn</span>
            <input value={name} onChange={(e) => setName(e.target.value)} placeholder="F.eks. Familien Hansen" autoFocus />
          </label>
          <button className="btn" disabled={busy} onClick={create}>Opret familie</button>
        </>
      ) : (
        <>
          <label className="field">
            <span>Invitationskode</span>
            <input value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} placeholder="F.eks. NNXKQ9" style={{ textAlign: "center", letterSpacing: 3 }} autoFocus />
          </label>
          {error && <p className="note" style={{ color: "#d4547a" }}>{error}</p>}
          <button className="btn" disabled={!code.trim() || busy} onClick={join}>Deltag i familie</button>
        </>
      )}
    </div>
  );
}
