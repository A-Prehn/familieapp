import { useState } from "react";
import { useApp, useLiveData } from "../lib/AppContext";

const GENDER_AVATAR = {
  boy: { cls: "blue", emoji: "👦" },
  girl: { cls: "pink", emoji: "👧" },
  unspecified: { cls: "", emoji: "🧒" },
};

function age(birthDate) {
  if (!birthDate) return "";
  const b = new Date(birthDate);
  const now = new Date();
  let months = (now.getFullYear() - b.getFullYear()) * 12 + (now.getMonth() - b.getMonth());
  if (now.getDate() < b.getDate()) months -= 1;
  if (months < 0) return `Termin om ${Math.abs(months)} mdr.`;
  if (months < 24) return `${months} måneder`;
  return `${Math.floor(months / 12)} år`;
}

export default function ChildList({ nav }) {
  const { user, store, signOut } = useApp();
  const { data: children, refresh } = useLiveData(() => store.listChildren(user.id), [user.id]);
  const [redeeming, setRedeeming] = useState(false);
  const [code, setCode] = useState("");
  const [error, setError] = useState("");

  async function submitCode() {
    setError("");
    try {
      const child = await store.acceptInvite(user.id, code);
      setRedeeming(false);
      setCode("");
      await refresh();
      nav.push("child", { childId: child.id });
    } catch (e) {
      setError(e.message);
    }
  }

  return (
    <>
      <div className="nav">
        <button className="action" style={{ visibility: "hidden" }}>.</button>
        <div className="title">Hjem</div>
        <button className="action" onClick={() => nav.push("newChild")}>＋</button>
      </div>

      <div className="content">
        <h1 className="large-title">Mine børn</h1>

        {children == null ? null : children.length === 0 ? (
          <div className="empty">
            <span className="emoji">🍼</span>
            Opret dit første barn for at komme i gang.
          </div>
        ) : (
          children.map((c) => {
            const a = GENDER_AVATAR[c.gender] || GENDER_AVATAR.unspecified;
            const shared = c.memberIds.length > 1;
            return (
              <div key={c.id} className="card row-card" onClick={() => nav.push("child", { childId: c.id })}>
                <div className={`avatar ${a.cls}`}>{a.emoji}</div>
                <div className="row-main">
                  <div className="row-title">{c.name}</div>
                  <div className="row-sub">
                    {age(c.birthDate) || "Ingen fødselsdato"}
                    {shared && " · delt 👥"}
                  </div>
                </div>
                <div className="chevron">›</div>
              </div>
            );
          })
        )}

        <button className="btn secondary" onClick={() => nav.push("newChild")} style={{ marginTop: 8 }}>
          ＋ Tilføj barn
        </button>

        <button className="btn ghost" onClick={() => { setError(""); setRedeeming(true); }} style={{ marginTop: 4 }}>
          Har du fået en kode?
        </button>

        <div className="switcher">
          Logget ind som <b>{user.name}</b> · <button onClick={signOut}>log ud / skift</button>
        </div>
      </div>

      {redeeming && (
        <div className="modal-backdrop" onClick={() => setRedeeming(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="row-title" style={{ marginBottom: 4 }}>Indtast invitationskode</div>
            <p className="note" style={{ padding: 0, marginBottom: 12 }}>
              Koden du har fået af den anden forælder.
            </p>
            <input
              value={code}
              onChange={(e) => setCode(e.target.value.toUpperCase())}
              placeholder="F.eks. NNXKQ9"
              autoFocus
              style={{ textTransform: "uppercase", textAlign: "center", letterSpacing: 3 }}
            />
            {error && <p className="note" style={{ color: "#ff3b30", padding: 0 }}>{error}</p>}
            <button className="btn" disabled={!code.trim()} onClick={submitCode} style={{ marginTop: 12 }}>
              Deltag
            </button>
            <button className="btn ghost" onClick={() => setRedeeming(false)}>Annullér</button>
          </div>
        </div>
      )}
    </>
  );
}
