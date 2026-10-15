import { useState } from "react";
import { useApp, useLiveData } from "../lib/AppContext";
import { ScreenHeader, Modal, PhotoPicker, Lightbox } from "../components/ui";
import { MILESTONES, formatDate } from "../lib/constants";

export default function Milestones({ nav, childId }) {
  const { store } = useApp();
  const { data: child } = useLiveData(() => store.getChild(childId), [childId]);
  const ms = child?.milestones || {};
  const [edit, setEdit] = useState(null); // { m, value, photo }
  const [lb, setLb] = useState(null);

  function open(m) {
    setEdit({ m, value: ms[m.key] || "", photo: ms[m.key + "_photo"] || null });
  }
  async function save() {
    const { m, value, photo } = edit;
    await store.setChildField(childId, "milestones", m.key, value.trim ? value.trim() : value);
    await store.setChildField(childId, "milestones", m.key + "_photo", photo);
    setEdit(null);
  }

  function display(m) {
    const v = ms[m.key];
    if (!v) return "—";
    return m.type === "date" ? formatDate(v) : v;
  }

  return (
    <>
      <ScreenHeader title="Milepæle" onBack={nav.pop} backLabel={child?.name} />
      <div className="content">
        <div className="milestone-grid">
          {MILESTONES.map((m) => {
            const photo = ms[m.key + "_photo"];
            const filled = !!ms[m.key];
            return (
              <div key={m.key} className={`milestone ${filled ? "filled" : ""}`}>
                <div className="ms-media" onClick={() => (photo ? setLb(photo) : open(m))}>
                  {photo ? <img src={photo} alt={m.label} /> : m.icon}
                </div>
                <div className="ms-body" onClick={() => open(m)} style={{ cursor: "pointer" }}>
                  <div className="ms-label">{m.label}</div>
                  <div className="ms-value">{display(m)}</div>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {edit && (
        <Modal title={edit.m.label} onClose={() => setEdit(null)}>
          <label className="field">
            <span>{edit.m.type === "date" ? "Dato" : "Værdi"}</span>
            {edit.m.type === "date" ? (
              <input type="date" value={edit.value || ""} onChange={(e) => setEdit({ ...edit, value: e.target.value })} />
            ) : (
              <input value={edit.value || ""} onChange={(e) => setEdit({ ...edit, value: e.target.value })} placeholder="Skriv her…" />
            )}
          </label>
          <PhotoPicker value={edit.photo} onChange={(p) => setEdit({ ...edit, photo: p })} />
          <button className="btn" onClick={save} style={{ marginTop: 12 }}>Gem</button>
          <button className="btn ghost" onClick={() => setEdit(null)}>Annullér</button>
        </Modal>
      )}
      {lb && <Lightbox photos={[lb]} index={0} onClose={() => setLb(null)} />}
    </>
  );
}
