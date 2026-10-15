import { Star, BookOpen, Baby, Images, MessageCircleHeart, Milestone } from "lucide-react";
import { useApp, useLiveData } from "../lib/AppContext";
import { ScreenHeader } from "../components/ui";
import { daysUntil, ageFromBirth, MONTHS_FULL, MILESTONES } from "../lib/constants";

const AVATAR = {
  boy: { cls: "blue", emoji: "👦" },
  girl: { cls: "pink", emoji: "👧" },
  unspecified: { cls: "", emoji: "🧒" },
};

export default function ChildDetail({ nav, childId }) {
  const { store } = useApp();
  const { data: child } = useLiveData(() => store.getChild(childId), [childId]);
  if (!child) return <ScreenHeader title="" onBack={nav.pop} backLabel="Hjem" />;

  const a = AVATAR[child.gender] || AVATAR.unspecified;
  const onTheWay = !child.birthDate && child.dueDate;
  const due = daysUntil(child.dueDate);
  const dueM = child.dueDate ? new Date(child.dueDate) : null;
  const filledMs = MILESTONES.filter((m) => child.milestones?.[m.key]).length;
  const answered = Object.values(child.aboutMe || {}).filter((v) => v && v.trim()).length;

  const sections = [
    { key: "highlights", wide: true, Icon: Star, bg: "var(--rose-soft)", color: "var(--rose)", title: "Højdepunkter", sub: `${child.highlights.length} ${child.highlights.length === 1 ? "højdepunkt" : "højdepunkter"}`, go: () => nav.push("highlights", { childId }) },
    { key: "diary", Icon: BookOpen, bg: "var(--neutral-soft)", color: "var(--neutral-dark)", title: onTheWay ? "Svangerskabsdagbog" : "Dagbog", sub: `${child.diary.length} indlæg`, go: () => nav.push("diary", { childId }) },
    { key: "belly", Icon: Baby, bg: "var(--neutral-soft)", color: "var(--neutral-dark)", title: "Maven måned for måned", sub: `${child.bellyGallery.length} fotos`, go: () => nav.push("gallery", { childId, kind: "bellyGallery" }) },
    { key: "monthly", Icon: Images, bg: "var(--tint-soft)", color: "var(--tint-dark)", title: "Måned for måned", sub: `${child.monthlyGallery.length} ${child.monthlyGallery.length === 1 ? "måned" : "måneder"}`, go: () => nav.push("gallery", { childId, kind: "monthlyGallery" }) },
    { key: "about", Icon: MessageCircleHeart, bg: "var(--rose-soft)", color: "var(--rose)", title: "Om dig", sub: `${answered} svar`, go: () => nav.push("aboutMe", { childId }) },
    { key: "milestones", Icon: Milestone, bg: "var(--green-soft)", color: "var(--green)", title: "Milepæle", sub: `${filledMs} udfyldt`, go: () => nav.push("milestones", { childId }) },
  ];

  return (
    <>
      <ScreenHeader title={child.name} onBack={nav.pop} backLabel="Hjem" />
      <div className="content">
        <div className="card">
          <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
            <div className={`avatar-lg avatar ${a.cls}`}>{a.emoji}</div>
            <div>
              <div style={{ fontFamily: "'Lora',serif", fontSize: 22, fontWeight: 500 }}>{child.name}</div>
              <div style={{ fontSize: 14, color: "var(--muted)", marginTop: 2 }}>
                {onTheWay ? "På vej" : ageFromBirth(child.birthDate) || "—"}
              </div>
            </div>
          </div>

          {onTheWay && (
            <div className="countdown">
              <div className="countdown-number">{due > 0 ? due : 0}</div>
              <div>
                <div className="countdown-label">dage til termin</div>
                {dueM && <div className="countdown-detail">Termin: {MONTHS_FULL[dueM.getMonth()]} {dueM.getFullYear()}</div>}
              </div>
            </div>
          )}
        </div>

        <div className="section-grid">
          {sections.map((s) => (
            <button key={s.key} className={`section-btn ${s.wide ? "wide" : ""}`} onClick={s.go}>
              <div className="section-ico" style={{ background: s.bg, color: s.color }}><s.Icon size={19} strokeWidth={1.8} /></div>
              <div>
                <div className="s-title">{s.title}</div>
                <div className="s-sub">{s.sub}</div>
              </div>
            </button>
          ))}
        </div>
      </div>
    </>
  );
}
