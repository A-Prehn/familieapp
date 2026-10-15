import { useApp, useLiveData } from "../lib/AppContext";
import { daysUntil, ageFromBirth } from "../lib/constants";

const AVATAR = {
  boy: { cls: "blue", emoji: "👦" },
  girl: { cls: "pink", emoji: "👧" },
  unspecified: { cls: "", emoji: "🧒" },
};

function childSub(c) {
  if (!c.birthDate && c.dueDate) {
    const d = daysUntil(c.dueDate);
    return d != null && d > 0 ? `${d} dage til termin` : "Termin nået";
  }
  return ageFromBirth(c.birthDate) || "Ingen fødselsdato";
}

export default function HomeTab({ nav }) {
  const { familyId, store } = useApp();
  const { data: family } = useLiveData(() => store.getFamily(familyId), [familyId]);
  const { data: children } = useLiveData(() => store.listChildren(familyId), [familyId]);

  return (
    <>
      <div className="nav">
        <span style={{ width: 52 }} />
        <div className="title">{family?.name || "Hjem"}</div>
        <button className="action" onClick={() => nav.push("newChild")}>＋</button>
      </div>

      <div className="content">
        <h1 className="large-title">Vores børn</h1>

        {children == null ? null : (
          <div className="home-grid">
            {children.map((c) => {
              const a = AVATAR[c.gender] || AVATAR.unspecified;
              return (
                <div key={c.id} className="home-card" onClick={() => nav.push("child", { childId: c.id })}>
                  <div className={`avatar ${a.cls}`}>{a.emoji}</div>
                  <div className="home-card-name">{c.name}</div>
                  <div className="home-card-sub">{childSub(c)}</div>
                </div>
              );
            })}
            <div className="home-card add" onClick={() => nav.push("newChild")}>
              <div className="plus">＋</div>
              <div className="home-card-name">Tilføj barn</div>
            </div>
          </div>
        )}
      </div>
    </>
  );
}
