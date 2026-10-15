import { useState } from "react";
import { useApp } from "../lib/AppContext";

export default function NewChild({ nav }) {
  const { user, store } = useApp();
  const [name, setName] = useState("");
  const [birthDate, setBirthDate] = useState("");
  const [gender, setGender] = useState("unspecified");
  const [saving, setSaving] = useState(false);

  async function create() {
    setSaving(true);
    const child = await store.createChild(user.id, { name, birthDate, gender });
    nav.pop();
    nav.push("child", { childId: child.id });
  }

  return (
    <>
      <div className="nav">
        <button className="back" onClick={nav.pop}>‹ Tilbage</button>
        <div className="title">Nyt barn</div>
        <div className="spacer" />
      </div>

      <div className="content">
        <label className="field">
          <span>Navn</span>
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Barnets navn" autoFocus />
        </label>

        <label className="field">
          <span>Fødselsdato (eller termin)</span>
          <input type="date" value={birthDate} onChange={(e) => setBirthDate(e.target.value)} />
        </label>

        <label className="field">
          <span>Køn</span>
          <div className="seg">
            {[
              ["girl", "Pige"],
              ["boy", "Dreng"],
              ["unspecified", "Ikke angivet"],
            ].map(([val, label]) => (
              <button key={val} className={gender === val ? "active" : ""} onClick={() => setGender(val)}>
                {label}
              </button>
            ))}
          </div>
        </label>

        <button className="btn" disabled={!name.trim() || saving} onClick={create}>
          {saving ? "Opretter…" : "Opret barn"}
        </button>
      </div>
    </>
  );
}
