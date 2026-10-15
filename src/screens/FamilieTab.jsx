import { useState } from "react";
import { Plus } from "lucide-react";
import { useApp, useLiveData } from "../lib/AppContext";
import { EmptyState, Modal, Lightbox, PhotoPicker } from "../components/ui";
import { MONTHS_SHORT, MONTHS_FULL, formatDate } from "../lib/constants";

const SUBS = [["events", "Begivenheder"], ["vacations", "Ferier"], ["birthdays", "Fødselsdage"]];

function nextBirthday(dateStr, today) {
  const d = new Date(dateStr);
  const next = new Date(today.getFullYear(), d.getMonth(), d.getDate());
  if (next < today) next.setFullYear(today.getFullYear() + 1);
  return next;
}

export default function FamilieTab() {
  const { familyId, store } = useApp();
  const [sub, setSub] = useState("events");
  const { data: family } = useLiveData(() => store.getFamily(familyId), [familyId]);
  const { data: children } = useLiveData(() => store.listChildren(familyId), [familyId]);
  const [adding, setAdding] = useState(false);
  const [lb, setLb] = useState(null);
  const [form, setForm] = useState({});
  const [busy, setBusy] = useState(false);

  function openAdd() { setForm({}); setAdding(true); }
  async function save() {
    setBusy(true);
    if (sub === "events") await store.addFamilyItem(familyId, "events", { title: form.title?.trim(), date: form.date || null, description: form.description?.trim() || "" });
    else if (sub === "vacations") await store.addFamilyItem(familyId, "vacations", { title: form.title?.trim(), startDate: form.startDate || null, endDate: form.endDate || null, description: form.description?.trim() || "", photo: form.photo || null });
    else await store.addFamilyItem(familyId, "birthdays", { name: form.name?.trim(), date: form.date || null, emoji: form.emoji?.trim() || "🎂" });
    setBusy(false); setAdding(false);
  }

  return (
    <>
      <div className="nav">
        <span style={{ width: 52 }} />
        <div className="title">{family?.name || "Familie"}</div>
        <button className="action" onClick={openAdd} aria-label="Tilføj"><Plus size={22} strokeWidth={1.8} /></button>
      </div>
      <div className="content">
        <div className="subnav">
          {SUBS.map(([k, l]) => (
            <button key={k} className={sub === k ? "active" : ""} onClick={() => setSub(k)}>{l}</button>
          ))}
        </div>

        {sub === "events" && <Events events={family?.events || []} />}
        {sub === "vacations" && <Vacations vacations={family?.vacations || []} onPhoto={setLb} />}
        {sub === "birthdays" && <Birthdays family={family} children={children || []} />}
      </div>

      {adding && (
        <Modal title={sub === "events" ? "Ny begivenhed" : sub === "vacations" ? "Ny ferie" : "Ny fødselsdag"} onClose={() => setAdding(false)}>
          {sub === "birthdays" ? (
            <>
              <label className="field"><span>Navn</span><input value={form.name || ""} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="F.eks. Mormor" autoFocus /></label>
              <label className="field"><span>Fødselsdato</span><input type="date" value={form.date || ""} onChange={(e) => setForm({ ...form, date: e.target.value })} /></label>
              <label className="field"><span>Emoji</span><input value={form.emoji || ""} onChange={(e) => setForm({ ...form, emoji: e.target.value })} placeholder="🎂" /></label>
              <button className="btn" disabled={busy || !form.name?.trim() || !form.date} onClick={save}>Gem</button>
            </>
          ) : sub === "events" ? (
            <>
              <label className="field"><span>Titel</span><input value={form.title || ""} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder="F.eks. Sommerfest" autoFocus /></label>
              <label className="field"><span>Dato</span><input type="date" value={form.date || ""} onChange={(e) => setForm({ ...form, date: e.target.value })} /></label>
              <label className="field"><span>Beskrivelse</span><textarea value={form.description || ""} onChange={(e) => setForm({ ...form, description: e.target.value })} /></label>
              <button className="btn" disabled={busy || !form.title?.trim()} onClick={save}>Gem</button>
            </>
          ) : (
            <>
              <label className="field"><span>Titel</span><input value={form.title || ""} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder="F.eks. Sommerhus i Skagen" autoFocus /></label>
              <label className="field"><span>Fra</span><input type="date" value={form.startDate || ""} onChange={(e) => setForm({ ...form, startDate: e.target.value })} /></label>
              <label className="field"><span>Til</span><input type="date" value={form.endDate || ""} onChange={(e) => setForm({ ...form, endDate: e.target.value })} /></label>
              <label className="field"><span>Beskrivelse</span><textarea value={form.description || ""} onChange={(e) => setForm({ ...form, description: e.target.value })} /></label>
              <PhotoPicker value={form.photo} onChange={(p) => setForm({ ...form, photo: p })} />
              <button className="btn" disabled={busy || !form.title?.trim()} onClick={save} style={{ marginTop: 12 }}>Gem</button>
            </>
          )}
          <button className="btn ghost" onClick={() => setAdding(false)}>Annullér</button>
        </Modal>
      )}
      {lb && <Lightbox photos={[lb]} index={0} onClose={() => setLb(null)} />}
    </>
  );
}

function Events({ events }) {
  const sorted = events.slice().sort((a, b) => new Date(b.date || 0) - new Date(a.date || 0));
  if (!sorted.length) return <EmptyState emoji="📅">Ingen begivenheder endnu.</EmptyState>;
  return (
    <div className="card" style={{ padding: "4px 16px" }}>
      {sorted.map((ev) => {
        const d = ev.date ? new Date(ev.date) : null;
        return (
          <div key={ev.id} className="event-item">
            <div className="event-datebox">
              <div className="event-month">{d ? MONTHS_SHORT[d.getMonth()] : "—"}</div>
              <div className="event-day">{d ? d.getDate() : "·"}</div>
            </div>
            <div className="event-main">
              <div className="event-title">{ev.title}</div>
              {ev.description && <div className="event-sub">{ev.description}</div>}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function Vacations({ vacations, onPhoto }) {
  const sorted = vacations.slice().sort((a, b) => new Date(b.startDate || 0) - new Date(a.startDate || 0));
  if (!sorted.length) return <EmptyState emoji="🏖️">Ingen ferier endnu.</EmptyState>;
  let lastYear = null;
  return (
    <div className="timeline">
      {sorted.map((v, idx) => {
        const year = v.startDate ? new Date(v.startDate).getFullYear() : null;
        const showYear = year && year !== lastYear;
        if (year) lastYear = year;
        const side = idx % 2 === 0 ? "tl-left" : "tl-right";
        return (
          <div key={v.id}>
            {showYear && <div className="tl-year"><span>{year}</span></div>}
            <div className="tl-item">
              <div className="tl-dot" />
              <div className={`tl-card ${side}`}>
                <div className="tl-title">{v.title}</div>
                {(v.startDate || v.endDate) && (
                  <div className="tl-date">{[v.startDate, v.endDate].filter(Boolean).map(formatDate).join(" – ")}</div>
                )}
                {v.description && <div className="tl-desc">{v.description}</div>}
                {v.photo && <img src={v.photo} alt="" onClick={() => onPhoto(v.photo)} />}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function Birthdays({ family, children }) {
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const entries = [];
  children.forEach((c) => { if (c.birthDate) entries.push({ name: c.name, date: c.birthDate, emoji: c.gender === "girl" ? "👧" : c.gender === "boy" ? "👦" : "🧒" }); });
  (family?.birthdays || []).forEach((b) => entries.push(b));

  const withDays = entries.map((e) => {
    const next = nextBirthday(e.date, today);
    const days = Math.round((next - today) / 86400000);
    const age = next.getFullYear() - new Date(e.date).getFullYear();
    return { ...e, days, age, d: new Date(e.date) };
  }).sort((a, b) => a.days - b.days);

  if (!withDays.length) return <EmptyState emoji="🎂">Ingen fødselsdage endnu.</EmptyState>;
  return (
    <div className="card" style={{ padding: "4px 16px" }}>
      {withDays.map((e, i) => (
        <div key={i} className="event-item">
          <div className="bday-count">
            {e.days === 0 ? <div className="n">🎉</div> : <><div className="n">{e.days}</div><div className="u">{e.days === 1 ? "dag" : "dage"}</div></>}
          </div>
          <div className="event-main">
            <div className="event-title">{e.emoji || "🎂"} {e.name}</div>
            <div className="event-sub">{e.d.getDate()}. {MONTHS_FULL[e.d.getMonth()]} · fylder {e.age}</div>
          </div>
        </div>
      ))}
    </div>
  );
}
