import { useState } from "react";
import { useApp, useLiveData } from "../lib/AppContext";

export default function SettingsTab() {
  const { user, familyId, store, signOut } = useApp();
  const { data: family } = useLiveData(() => store.getFamily(familyId), [familyId]);
  const { data: members } = useLiveData(() => store.listMembers(familyId), [familyId]);
  const [code, setCode] = useState(null);

  async function invite() {
    setCode(await store.createInvite(user.id, familyId));
  }

  return (
    <>
      <div className="nav">
        <span style={{ width: 52 }} />
        <div className="title">Mere</div>
        <span style={{ width: 52 }} />
      </div>
      <div className="content">
        <h1 className="large-title">Indstillinger</h1>

        <div className="section-label">Familie</div>
        <div className="card">
          <div className="row-title">{family?.name}</div>
          <div style={{ marginTop: 10 }}>
            {members?.map((m) => (
              <span key={m.id} className="member-pill">👤 {m.name}{m.id === user.id ? " (dig)" : ""}</span>
            ))}
          </div>
        </div>

        <div className="section-label">Del med den anden forælder</div>
        <div className="card">
          <p className="note" style={{ padding: 0 }}>
            Del koden, så I begge kan lægge op og se alt i realtid (CKShare i den rigtige app).
          </p>
          {code ? (
            <>
              <div className="code-box">{code}</div>
              <p className="note" style={{ textAlign: "center" }}>Gyldig invitationskode</p>
            </>
          ) : (
            <button className="btn" onClick={invite} style={{ marginTop: 10 }}>Opret invitationskode</button>
          )}
        </div>

        <div className="section-label">Konto</div>
        <div className="card">
          <div className="row-sub">Logget ind som <b style={{ color: "var(--text)" }}>{user.name}</b></div>
          <button className="btn ghost" onClick={signOut} style={{ marginTop: 6 }}>Log ud / skift bruger</button>
        </div>

        <p className="note">Prototype: data ligger lokalt i browseren. I den rigtige app gemmes alt i din egen iCloud via CloudKit.</p>
      </div>
    </>
  );
}
