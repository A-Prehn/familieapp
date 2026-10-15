import { useState } from "react";
import { useApp, useLiveData } from "../lib/AppContext";
import { ScreenHeader, EmptyState, Modal, Lightbox } from "../components/ui";
import { fileToResizedDataURL } from "../lib/photo";
import { formatDate } from "../lib/constants";

export default function Highlights({ nav, childId }) {
  const { store } = useApp();
  const { data: child } = useLiveData(() => store.getChild(childId), [childId]);
  const [adding, setAdding] = useState(false);
  const [lb, setLb] = useState(null);

  const [date, setDate] = useState("");
  const [text, setText] = useState("");
  const [photos, setPhotos] = useState([]);
  const [busy, setBusy] = useState(false);

  async function addPhoto(e) {
    const file = e.target.files?.[0];
    if (file) {
      const dataUrl = await fileToResizedDataURL(file);
      setPhotos((p) => [...p, dataUrl]);
    }
    e.target.value = "";
  }
  function resetForm() { setDate(""); setText(""); setPhotos([]); setAdding(false); }
  async function save() {
    setBusy(true);
    await store.addChildItem(childId, "highlights", { date: date || null, text: text.trim(), photos });
    setBusy(false); resetForm();
  }

  const sorted = (child?.highlights || []).slice().sort((a, b) => new Date(b.date || 0) - new Date(a.date || 0));
  let lastYear = null;

  return (
    <>
      <ScreenHeader title="Højdepunkter" onBack={nav.pop} backLabel={child?.name} action={{ label: "＋", onClick: () => setAdding(true) }} />
      <div className="content">
        {sorted.length === 0 ? (
          <EmptyState emoji="⭐">Ingen højdepunkter endnu.</EmptyState>
        ) : (
          <div className="timeline">
            {sorted.map((h, idx) => {
              const year = h.date ? new Date(h.date).getFullYear() : null;
              const showYear = year && year !== lastYear;
              if (year) lastYear = year;
              const pics = h.photos?.length ? h.photos : h.photo ? [h.photo] : [];
              const side = idx % 2 === 0 ? "tl-left" : "tl-right";
              return (
                <div key={h.id}>
                  {showYear && <div className="tl-year"><span>{year}</span></div>}
                  <div className="tl-item">
                    <div className="tl-dot" />
                    <div className={`tl-card ${side}`}>
                      {h.date && <div className="tl-date">{formatDate(h.date)}</div>}
                      <div className="tl-title">{h.text}</div>
                      {pics.map((p, i) => (
                        <img key={i} src={p} alt="" onClick={() => setLb({ photos: pics, index: i })} />
                      ))}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {adding && (
        <Modal title="Nyt højdepunkt" onClose={resetForm}>
          <label className="field"><span>Dato</span>
            <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </label>
          <label className="field"><span>Tekst</span>
            <textarea value={text} onChange={(e) => setText(e.target.value)} placeholder="Hvad skete der?" />
          </label>
          {photos.map((p, i) => (
            <div key={i} className="card post" style={{ marginBottom: 8 }}><img src={p} alt="" /></div>
          ))}
          <label className="btn secondary" style={{ display: "block", textAlign: "center" }}>
            ＋ Tilføj billede
            <input type="file" accept="image/*" onChange={addPhoto} style={{ display: "none" }} />
          </label>
          <button className="btn" disabled={busy || (!text.trim() && !photos.length)} onClick={save} style={{ marginTop: 12 }}>
            {busy ? "Gemmer…" : "Gem"}
          </button>
          <button className="btn ghost" onClick={resetForm}>Annullér</button>
        </Modal>
      )}
      {lb && <Lightbox photos={lb.photos} index={lb.index} onClose={() => setLb(null)} />}
    </>
  );
}
