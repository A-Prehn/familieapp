import { Star, BookOpen, Camera, ChevronRight } from "lucide-react";
import { useApp, useLiveData } from "../lib/AppContext";
import { formatDate } from "../lib/constants";
import { Modal, Lightbox } from "../components/ui";
import Hero from "../components/Hero";
import { useState } from "react";

// Hjem = "lige nu": hilsen, børnene i dag, hurtig-tilføj, seneste minder. Oversigten/strukturen ligger under Familie-fanen.
// Spejler ios/Mindebog/Views/HomeView.swift.

const AVATAR = { boy: { cls: "blue", emoji: "👦" }, girl: { cls: "pink", emoji: "👧" }, unspecified: { cls: "", emoji: "🧒" } };
const DAY = 86400000;
const startOfDay = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };

// Præcis alder "i dag": "Uge 31 · 62 dage til termin" / "4 mdr. og 3 dage" / "2 år og 1 md."
export function ageToday(c) {
  const today = startOfDay(new Date());
  if (!c.birthDate && c.dueDate) {
    const days = Math.round((startOfDay(c.dueDate) - today) / DAY);
    if (days <= 0) return "Termin nået";
    const week = Math.max(1, 40 - Math.ceil(days / 7) + 1);
    return `Uge ${week} · ${days} dage til termin`;
  }
  if (!c.birthDate) return "Ingen fødselsdato";
  const b = startOfDay(c.birthDate);
  let years = today.getFullYear() - b.getFullYear();
  let months = today.getMonth() - b.getMonth();
  let days = today.getDate() - b.getDate();
  if (days < 0) { months -= 1; days += new Date(today.getFullYear(), today.getMonth(), 0).getDate(); }
  if (months < 0) { years -= 1; months += 12; }
  if (years >= 2) return months === 0 ? `${years} år` : `${years} år og ${months} ${months === 1 ? "md." : "mdr."}`;
  const total = years * 12 + months;
  if (total === 0) return days === 1 ? "1 dag" : `${days} dage`;
  const m = `${total} ${total === 1 ? "md." : "mdr."}`;
  return days === 0 ? m : `${m} og ${days} ${days === 1 ? "dag" : "dage"}`;
}

function greeting(user) {
  const h = new Date().getHours();
  const word = h >= 5 && h < 10 ? "Godmorgen" : h >= 10 && h < 18 ? "Hej" : "Godaften";
  const name = user?.name?.trim();
  return !name || name === "Forælder" ? word : `${word}, ${name}`;
}

export default function HomeTab({ nav }) {
  const { user, familyId, store } = useApp();
  const { data: children } = useLiveData(() => store.listChildren(familyId), [familyId]);
  const [choose, setChoose] = useState(null); // { kind } når der er flere børn
  const [lb, setLb] = useState(null);

  const kids = children || [];

  // Seneste minder på tværs af børnene (højdepunkter + dagbog).
  const memories = [];
  kids.forEach((c) => {
    const onTheWay = !c.birthDate && c.dueDate;
    (c.highlights || []).forEach((h) => memories.push({ id: "hl_" + h.id, child: c, kind: "Højdepunkt", Icon: Star, date: h.date, sort: new Date(h.date || h.createdAt), text: h.text, photo: h.photos?.[0] || h.photo || null, screen: "highlights" }));
    (c.diary || []).forEach((d) => memories.push({ id: "dy_" + d.id, child: c, kind: onTheWay ? "Svangerskabsdagbog" : "Dagbog", Icon: BookOpen, date: d.date, sort: new Date(d.date || d.createdAt), text: d.text, photo: d.photo || null, screen: "diary" }));
  });
  const recent = memories.sort((a, b) => b.sort - a.sort).slice(0, 5);

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

        {children == null ? null : kids.length === 0 ? (
          <div className="card" style={{ textAlign: "center", color: "var(--muted)", fontSize: 14 }}>
            Tilføj jeres første barn under <b>Familie</b>, så fylder vi forsiden med minder.
          </div>
        ) : (
          <>
            <div className="section-label">I dag</div>
            {kids.map((c) => {
              const a = AVATAR[c.gender] || AVATAR.unspecified;
              return (
                <div key={c.id} className="card today-row" onClick={() => nav.push("child", { childId: c.id })}>
                  <div className={`avatar ${a.cls}`}>{a.emoji}</div>
                  <div className="row-main">
                    <div className="row-title serif">{c.name}</div>
                    <div className="row-sub">{ageToday(c)}</div>
                  </div>
                  <ChevronRight size={18} strokeWidth={1.6} className="chevron" />
                </div>
              );
            })}

            <div className="quick-row">
              <button className="quick-btn" onClick={() => quickAdd("highlight")}><Star size={20} strokeWidth={1.6} style={{ color: "var(--rose)" }} /><span>Højdepunkt</span></button>
              <button className="quick-btn" onClick={() => quickAdd("diary")}><BookOpen size={20} strokeWidth={1.6} style={{ color: "var(--neutral-dark)" }} /><span>Dagbog</span></button>
              <button className="quick-btn" onClick={() => quickAdd("photo")}><Camera size={20} strokeWidth={1.6} style={{ color: "var(--tint)" }} /><span>Foto</span></button>
            </div>

            {recent.length > 0 && (
              <>
                <div className="section-label">Seneste minder</div>
                {recent.map((m) => (
                  <div key={m.id} className="card memory-row" onClick={() => nav.push(m.screen, { childId: m.child.id })}>
                    {m.photo ? (
                      <img src={m.photo} alt="" onClick={(e) => { e.stopPropagation(); setLb(m.photo); }} />
                    ) : (
                      <div className="memory-icon"><m.Icon size={22} strokeWidth={1.5} /></div>
                    )}
                    <div className="row-main">
                      <div className="memory-meta">{m.child.name} · {m.kind}</div>
                      <div className="memory-text">{m.text || "Uden tekst"}</div>
                      {m.date && <div className="memory-date">{formatDate(m.date)}</div>}
                    </div>
                  </div>
                ))}
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
