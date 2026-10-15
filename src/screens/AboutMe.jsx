import { useState } from "react";
import { useApp, useLiveData } from "../lib/AppContext";
import { ScreenHeader, Modal } from "../components/ui";
import { ABOUT_ME_SECTIONS } from "../lib/constants";

export default function AboutMe({ nav, childId }) {
  const { store } = useApp();
  const { data: child } = useLiveData(() => store.getChild(childId), [childId]);
  const aboutMe = child?.aboutMe || {};
  const [editing, setEditing] = useState(null); // { question, value }

  async function save() {
    await store.setChildField(childId, "aboutMe", editing.question, editing.value.trim());
    setEditing(null);
  }

  return (
    <>
      <ScreenHeader title="Om dig" onBack={nav.pop} backLabel={child?.name} />
      <div className="content">
        {ABOUT_ME_SECTIONS.map((section) => (
          <div key={section.title}>
            <div className="section-label">{section.title}</div>
            <div className="card" style={{ padding: 0 }}>
              {section.questions.map((q) => {
                const ans = (aboutMe[q] || "").trim();
                return (
                  <div key={q} className="qa-row" style={{ cursor: "pointer" }} onClick={() => setEditing({ question: q, value: ans })}>
                    <div className="qa-q">{q}</div>
                    <div className={`qa-a ${ans ? "" : "empty"}`}>{ans || "Tryk for at svare"}</div>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>

      {editing && (
        <Modal title={editing.question} onClose={() => setEditing(null)}>
          <textarea value={editing.value} onChange={(e) => setEditing({ ...editing, value: e.target.value })} autoFocus placeholder="Skriv svaret…" />
          <button className="btn" onClick={save} style={{ marginTop: 12 }}>Gem</button>
          <button className="btn ghost" onClick={() => setEditing(null)}>Annullér</button>
        </Modal>
      )}
    </>
  );
}
