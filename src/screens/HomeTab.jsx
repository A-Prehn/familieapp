import { Star, BookOpen, Camera, CalendarHeart, Palmtree, Quote } from "lucide-react";
import { useApp, useLiveData } from "../lib/AppContext";
import { quoteOfTheDay } from "../lib/quotes";
import { formatDate } from "../lib/constants";
import { Modal, Lightbox } from "../components/ui";
import Hero from "../components/Hero";
import { useState } from "react";

// Hjem: hilsen, hurtig-tilføj, "På denne dag" (minder fra samme dato tidligere år)
// og seneste minder. Børnene ligger under Familie-fanen.
// Spejler ios/Mindebog/Views/HomeView.swift.

function greeting(user) {
  const h = new Date().getHours();
  const word = h >= 5 && h < 10 ? "Godmorgen" : h >= 10 && h < 18 ? "Hej" : "Godaften";
  const name = user?.name?.trim();
  return !name || name === "Forælder" ? word : `${word}, ${name}`;
}

export default function HomeTab({ nav }) {
  const { user, familyId, store } = useApp();
  const { data: children } = useLiveData(() => store.listChildren(familyId), [familyId]);
  const { data: family } = useLiveData(() => store.getFamily(familyId), [familyId]);
  const [choose, setChoose] = useState(null); // { kind } når der er flere børn
  const [lb, setLb] = useState(null);

  const kids = children || [];

  // Alle minder: højdepunkter + dagbog pr. barn, og fælles begivenheder + ferier.
  const memories = [];
  kids.forEach((c) => {
    const onTheWay = !c.birthDate && c.dueDate;
    (c.highlights || []).forEach((h) => memories.push({ id: "hl_" + h.id, who: c.name, childId: c.id, kind: "Højdepunkt", Icon: Star, date: h.date, sort: new Date(h.date || h.createdAt), text: h.text, photo: h.photos?.[0] || h.photo || null, screen: "highlights" }));
    (c.diary || []).forEach((d) => memories.push({ id: "dy_" + d.id, who: c.name, childId: c.id, kind: onTheWay ? "Svangerskabsdagbog" : "Dagbog", Icon: BookOpen, date: d.date, sort: new Date(d.date || d.createdAt), text: d.text, photo: d.photo || null, screen: "diary" }));
  });
  (family?.events || []).forEach((e) => memories.push({ id: "ev_" + e.id, who: "Fælles", kind: "Begivenhed", Icon: CalendarHeart, date: e.date, sort: new Date(e.date || e.createdAt), text: e.title, photo: e.photo || null }));
  (family?.vacations || []).forEach((v) => memories.push({ id: "va_" + v.id, who: "Fælles", kind: "Ferie", Icon: Palmtree, date: v.startDate, sort: new Date(v.startDate || v.createdAt), text: v.title, photo: v.photo || null }));

  // På denne dag: samme dag og måned i et tidligere år.
  const now = new Date();
  const onThisDay = memories
    .filter((m) => { if (!m.date) return false; const d = new Date(m.date); return d.getDate() === now.getDate() && d.getMonth() === now.getMonth() && d.getFullYear() < now.getFullYear(); })
    .map((m) => { const years = now.getFullYear() - new Date(m.date).getFullYear(); return { ...m, ago: years === 1 ? "For 1 år siden" : `For ${years} år siden` }; })
    .sort((a, b) => b.sort - a.sort);

  // Seneste minder: kun børnenes (det man selv lægger ind løbende).
  const recent = memories.filter((m) => m.childId).sort((a, b) => b.sort - a.sort).slice(0, 5);

  const row = (m, meta) => (
    <div key={m.id} className="card memory-row" onClick={m.screen ? () => nav.push(m.screen, { childId: m.childId }) : undefined} style={m.screen ? undefined : { cursor: "default" }}>
      {m.photo ? (
        <img src={m.photo} alt="" onClick={(e) => { e.stopPropagation(); setLb(m.photo); }} />
      ) : (
        <div className="memory-icon"><m.Icon size={22} strokeWidth={1.5} /></div>
      )}
      <div className="row-main">
        <div className="memory-meta">{meta}</div>
        <div className="memory-text">{m.text || "Uden tekst"}</div>
        {m.date && <div className="memory-date">{formatDate(m.date)}</div>}
      </div>
    </div>
  );

  function quickAdd(kind, child) {
    if (!child) {
      if (kids.length === 1) child = kids[0];
      else { setChoose({ kind }); return; }
    }
    setChoose(null);
    const onTheWay = !child.birthDate && child.dueDate;
    if (kind === "highlight") nav.push("highlights", { childId: child.id, autoAdd: true });
    else if (kind === "diary") nav.push("diary", { childId: child.id, autoAdd: true });
    else nav.push("gallery", { childId: child.id, kind: onTheWay ? "bellyGallery" : "monthlyGallery", autoAdd: true });
  }

  return (
    <>
      <div className="nav">
        <span style={{ width: 52 }} />
        <div className="title">Hjem</div>
        <span style={{ width: 52 }} />
      </div>

      <div className="content">
        <Hero />
        <div className="greeting">{greeting(user)}</div>
        <div className="quote-card">
          <Quote size={16} strokeWidth={1.6} className="quote-icon" />
          <div>{quoteOfTheDay()}</div>
        </div>

        {children == null ? null : kids.length === 0 ? (
          <div className="card" style={{ textAlign: "center", color: "var(--muted)", fontSize: 14 }}>
            Tilføj jeres første barn under <b>Familie</b>, så fylder vi forsiden med minder.
          </div>
        ) : (
          <>
            <div className="quick-row" style={{ marginTop: 18 }}>
              <button className="quick-btn" onClick={() => quickAdd("highlight")}><Star size={20} strokeWidth={1.6} style={{ color: "var(--rose)" }} /><span>Højdepunkt</span></button>
              <button className="quick-btn" onClick={() => quickAdd("diary")}><BookOpen size={20} strokeWidth={1.6} style={{ color: "var(--neutral-dark)" }} /><span>Dagbog</span></button>
              <button className="quick-btn" onClick={() => quickAdd("photo")}><Camera size={20} strokeWidth={1.6} style={{ color: "var(--tint)" }} /><span>Foto</span></button>
            </div>

            {onThisDay.length > 0 && (
              <>
                <div className="section-label">På denne dag</div>
                {onThisDay.map((m) => row(m, `${m.ago} · ${m.who} · ${m.kind}`))}
              </>
            )}

            {recent.length > 0 && (
              <>
                <div className="section-label">Seneste minder</div>
                {recent.map((m) => row(m, `${m.who} · ${m.kind}`))}
              </>
            )}
          </>
        )}
      </div>

      {choose && (
        <Modal title="Hvilket barn?" onClose={() => setChoose(null)}>
          {kids.map((c) => (
            <button key={c.id} className="btn secondary" style={{ display: "block", width: "100%", marginBottom: 8 }} onClick={() => quickAdd(choose.kind, c)}>{c.name}</button>
          ))}
          <button className="btn ghost" onClick={() => setChoose(null)}>Annullér</button>
        </Modal>
      )}
      {lb && <Lightbox photos={[lb]} index={0} onClose={() => setLb(null)} />}
    </>
  );
}
