import { useState } from "react";
import { useApp, useLiveData } from "../lib/AppContext";

// Deling ~ CKShare. I prototypen genereres en kode som partneren indtaster.
// I SwiftUI bliver dette et rigtigt CKShare-link (UICloudSharingController).
export default function ShareChild({ nav, childId }) {
  const { user, store } = useApp();
  const [code, setCode] = useState(null);
  const { data: members, refresh } = useLiveData(() => store.listMembers(childId), [childId]);

  async function generate() {
    setCode(await store.createInvite(user.id, childId));
  }

  return (
    <>
      <div className="nav">
        <button className="back" onClick={nav.pop}>‹ Tilbage</button>
        <div className="title">Del barn</div>
        <div className="spacer" />
      </div>

      <div className="content">
        <div className="card">
          <div className="row-title" style={{ marginBottom: 6 }}>Deltagere</div>
          {members?.map((m) => (
            <span key={m.id} className="member-pill">👤 {m.name}{m.id === user.id ? " (dig)" : ""}</span>
          ))}
        </div>

        <div className="card">
          <div className="row-title">Inviter den anden forælder</div>
          <p className="note" style={{ padding: 0 }}>
            Del koden med din partner. Når de indtaster den, kan I begge lægge op
            og se hinandens opslag i realtid.
          </p>
          {code ? (
            <>
              <div className="code-box">{code}</div>
              <p className="note" style={{ textAlign: "center" }}>Gyldig invitationskode</p>
            </>
          ) : (
            <button className="btn" onClick={generate} style={{ marginTop: 8 }}>
              Opret invitationskode
            </button>
          )}
        </div>

        <p className="note">
          Prototype-tip: log ud, log ind som en anden "forælder", og brug
          <b> "Har du fået en kode?"</b> på hjem-skærmen for at se delingen virke.
        </p>

        <button className="btn ghost" onClick={refresh} style={{ marginTop: 4 }}>
          Opdatér deltagere
        </button>
      </div>
    </>
  );
}
