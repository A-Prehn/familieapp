import { useState } from "react";
import { useApp } from "../lib/AppContext";
import { ScreenHeader } from "../components/ui";

export default function NewChild({ nav }) {
  const { familyId, store } = useApp();
  const [name, setName] = useState("");
  const [born, setBorn] = useState(true);
  const [birthDate, setBirthDate] = useState("");
  const [dueDate, setDueDate] = useState("");
  const [gender, setGender] = useState("unspecified");
  const [saving, setSaving] = useState(false);

  async function create() {
    setSaving(true);
    const child = await store.createChild(familyId, {
      name,
      gender,
      birthDate: born ? birthDate : null,
      dueDate: born ? null : dueDate,
    });
    // Synk fødsels-/terminsdato ind i milepæle (som websitet).
    if (born && birthDate) await store.setChildField(child.id, "milestones", "birth_date", birthDate);
    if (!born && dueDate) await store.setChildField(child.id, "milestones", "due_date", dueDate);
    nav.pop();
    nav.push("child", { childId: child.id });
  }

  return (
    <>
      <ScreenHeader title="Nyt barn" onBack={nav.pop} />
      <div className="content">
        <label className="field">
          <span>Navn</span>
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Barnets navn" autoFocus />
        </label>

        <label className="field">
          <span>Status</span>
          <div className="seg">
            <button className={born ? "active" : ""} onClick={() => setBorn(true)}>Født</button>
            <button className={!born ? "active" : ""} onClick={() => setBorn(false)}>På vej</button>
          </div>
        </label>

        {born ? (
          <label className="field">
            <span>Fødselsdato</span>
            <input type="date" value={birthDate} onChange={(e) => setBirthDate(e.target.value)} />
          </label>
        ) : (
          <label className="field">
            <span>Terminsdato</span>
            <input type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          </label>
        )}

        <label className="field">
          <span>Køn</span>
          <div className="seg">
            {[["girl", "Pige"], ["boy", "Dreng"], ["unspecified", "Ikke angivet"]].map(([v, l]) => (
              <button key={v} className={gender === v ? "active" : ""} onClick={() => setGender(v)}>{l}</button>
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
