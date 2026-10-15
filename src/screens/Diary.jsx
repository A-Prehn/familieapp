import { useState } from "react";
import { useApp, useLiveData } from "../lib/AppContext";
import { ScreenHeader, EmptyState, Modal, Lightbox, PhotoPicker } from "../components/ui";
import { formatDate } from "../lib/constants";

export default function Diary({ nav, childId, autoAdd }) {
  const { store } = useApp();
  const { data: child } = useLiveData(() => store.getChild(childId), [childId]);
  const onTheWay = child && !child.birthDate && child.dueDate;
  const [adding, setAdding] = useState(!!autoAdd);
  const [lb, setLb] = useState(null);
  const [date, setDate] = useState("");
  const [text, setText] = useState("");
  const [photo, setPhoto] = useState(null);
  const [busy, setBusy] = useState(false);

  function reset() { setDate(""); setText(""); setPhoto(null); setAdding(false); }
  async function save() {
    setBusy(true);
    await store.addChildItem(childId, "diary", { date: date || null, text: text.trim(), photo });
    setBusy(false); reset();
  }

  const sorted = (child?.diary || []).slice().sort((a, b) => new Date(b.date || b.createdAt) - new Date(a.date || a.createdAt));

  return (
    <>
      <ScreenHeader title={onTheWay ? "Svangerskabsdagbog" : "Dagbog"} onBack={nav.pop} backLabel={child?.name} action={{ label: "＋", onClick: () => setAdding(true) }} />
      <div className="content">
        {sorted.length === 0 ? (
          <EmptyState emoji="📖">Ingen indlæg endnu.</EmptyState>
        ) : (
          sorted.map((d) => (
            <div key={d.id} className="card post">
              {d.photo && <img src={d.photo} alt="" onClick={() => setLb(d.photo)} style={{ cursor: "zoom-in" }} />}
              <div className="post-body">
                {d.date && <div className="post-meta"><span>{formatDate(d.date)}</span></div>}
                <div className="post-text">{d.text}</div>
              </div>
            </div>
          ))
        )}
      </div>

      {adding && (
        <Modal title="Nyt indlæg" onClose={reset}>
          <label className="field"><span>Dato</span>
            <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </label>
          <label className="field"><span>Tekst</span>
            <textarea value={text} onChange={(e) => setText(e.target.value)} placeholder="Skriv dit indlæg…" />
          </label>
          <PhotoPicker value={photo} onChange={setPhoto} />
          <button className="btn" disabled={busy || (!text.trim() && !photo)} onClick={save} style={{ marginTop: 12 }}>
            {busy ? "Gemmer…" : "Gem"}
          </button>
          <button className="btn ghost" onClick={reset}>Annullér</button>
        </Modal>
      )}
      {lb && <Lightbox photos={[lb]} index={0} onClose={() => setLb(null)} />}
    </>
  );
}
