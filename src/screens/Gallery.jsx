import { useState } from "react";
import { useApp, useLiveData } from "../lib/AppContext";
import { ScreenHeader, EmptyState, Modal, Lightbox, PhotoPicker } from "../components/ui";

const META = {
  bellyGallery: { title: "Maven måned for måned", capLabel: "Uge/måned", capPlaceholder: "F.eks. Uge 24" },
  monthlyGallery: { title: "Måned for måned", capLabel: "Måned", capPlaceholder: "F.eks. 3 måneder" },
};

export default function Gallery({ nav, childId, kind, autoAdd }) {
  const meta = META[kind] || META.monthlyGallery;
  const { store } = useApp();
  const { data: child } = useLiveData(() => store.getChild(childId), [childId]);
  const [adding, setAdding] = useState(!!autoAdd);
  const [lb, setLb] = useState(null);
  const [caption, setCaption] = useState("");
  const [photo, setPhoto] = useState(null);
  const [busy, setBusy] = useState(false);

  const items = child?.[kind] || [];

  function reset() { setCaption(""); setPhoto(null); setAdding(false); }
  async function save() {
    setBusy(true);
    await store.addChildItem(childId, kind, { caption: caption.trim(), photo });
    setBusy(false); reset();
  }

  return (
    <>
      <ScreenHeader title={meta.title} onBack={nav.pop} backLabel={child?.name} action={{ label: "＋", onClick: () => setAdding(true) }} />
      <div className="content">
        {items.length === 0 ? (
          <EmptyState emoji="📷">Ingen fotos endnu.</EmptyState>
        ) : (
          <div className="photo-grid">
            {items.map((it, i) => (
              <div key={it.id} className="photo-cell">
                {it.photo && <img src={it.photo} alt="" onClick={() => setLb(items.filter((x) => x.photo).map((x) => x.photo).indexOf(it.photo))} />}
                {it.caption && <div className="photo-cap">{it.caption}</div>}
              </div>
            ))}
          </div>
        )}
      </div>

      {adding && (
        <Modal title="Nyt foto" onClose={reset}>
          <label className="field"><span>{meta.capLabel}</span>
            <input value={caption} onChange={(e) => setCaption(e.target.value)} placeholder={meta.capPlaceholder} />
          </label>
          <PhotoPicker value={photo} onChange={setPhoto} />
          <button className="btn" disabled={busy || !photo} onClick={save} style={{ marginTop: 12 }}>
            {busy ? "Gemmer…" : "Gem"}
          </button>
          <button className="btn ghost" onClick={reset}>Annullér</button>
        </Modal>
      )}
      {lb != null && lb >= 0 && (
        <Lightbox photos={items.filter((x) => x.photo).map((x) => x.photo)} index={lb} onClose={() => setLb(null)} />
      )}
    </>
  );
}
