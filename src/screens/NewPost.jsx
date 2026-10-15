import { useState } from "react";
import { useApp } from "../lib/AppContext";
import { fileToResizedDataURL } from "../lib/photo";

export default function NewPost({ nav, childId }) {
  const { user, store } = useApp();
  const [text, setText] = useState("");
  const [photo, setPhoto] = useState(null);
  const [saving, setSaving] = useState(false);

  async function pickPhoto(e) {
    const file = e.target.files?.[0];
    if (file) setPhoto(await fileToResizedDataURL(file));
  }

  async function post() {
    setSaving(true);
    await store.createPost(user.id, childId, { text, photo });
    nav.pop();
  }

  return (
    <>
      <div className="nav">
        <button className="back" onClick={nav.pop}>Annullér</button>
        <div className="title">Nyt opslag</div>
        <div className="spacer" />
      </div>

      <div className="content">
        <label className="field">
          <span>Billede</span>
          {photo ? (
            <div className="card post" style={{ marginBottom: 8 }}>
              <img src={photo} alt="" />
            </div>
          ) : null}
          <label className="btn secondary" style={{ display: "block", textAlign: "center" }}>
            {photo ? "Vælg et andet billede" : "📷 Vælg billede"}
            <input type="file" accept="image/*" onChange={pickPhoto} style={{ display: "none" }} />
          </label>
        </label>

        <label className="field">
          <span>Tekst</span>
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="Skriv om øjeblikket…"
          />
        </label>

        <button className="btn" disabled={saving || (!text.trim() && !photo)} onClick={post}>
          {saving ? "Lægger op…" : "Del opslag"}
        </button>
      </div>
    </>
  );
}
