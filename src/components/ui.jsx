import { useState, useEffect } from "react";
import { fileToResizedDataURL } from "../lib/photo";

export function ScreenHeader({ title, onBack, backLabel = "Tilbage", action }) {
  return (
    <div className="nav">
      {onBack ? (
        <button className="back" onClick={onBack}>‹ {backLabel}</button>
      ) : (
        <span style={{ width: 52 }} />
      )}
      <div className="title">{title}</div>
      {action ? (
        <button className="action" onClick={action.onClick}>{action.label}</button>
      ) : (
        <span style={{ width: 52 }} />
      )}
    </div>
  );
}

export function EmptyState({ emoji, children }) {
  return (
    <div className="empty">
      <span className="emoji">{emoji}</span>
      {children}
    </div>
  );
}

export function Modal({ title, children, onClose }) {
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        {title && <div className="row-title" style={{ marginBottom: 12 }}>{title}</div>}
        {children}
      </div>
    </div>
  );
}

// Foto-vælger: skalerer og giver dataURL tilbage (≈ CKAsset-upload).
export function PhotoPicker({ value, onChange, label = "📷 Vælg billede" }) {
  async function pick(e) {
    const file = e.target.files?.[0];
    if (file) onChange(await fileToResizedDataURL(file));
  }
  return (
    <div>
      {value && (
        <div className="card post" style={{ marginBottom: 8 }}>
          <img src={value} alt="" />
        </div>
      )}
      <label className="btn secondary" style={{ display: "block", textAlign: "center" }}>
        {value ? "Vælg et andet billede" : label}
        <input type="file" accept="image/*" onChange={pick} style={{ display: "none" }} />
      </label>
    </div>
  );
}

// Lightbox med swipe/pile mellem flere billeder.
export function Lightbox({ photos, index, onClose }) {
  const [i, setI] = useState(index || 0);
  useEffect(() => {
    const onKey = (e) => {
      if (e.key === "Escape") onClose();
      if (e.key === "ArrowRight") setI((p) => Math.min(p + 1, photos.length - 1));
      if (e.key === "ArrowLeft") setI((p) => Math.max(p - 1, 0));
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [photos.length, onClose]);

  return (
    <div className="lightbox" onClick={onClose}>
      <button className="lb-close" onClick={onClose}>✕</button>
      <img src={photos[i]} alt="" onClick={(e) => e.stopPropagation()} />
      {photos.length > 1 && (
        <>
          {i > 0 && <button className="lb-nav lb-prev" onClick={(e) => { e.stopPropagation(); setI(i - 1); }}>‹</button>}
          {i < photos.length - 1 && <button className="lb-nav lb-next" onClick={(e) => { e.stopPropagation(); setI(i + 1); }}>›</button>}
          <div className="lb-count">{i + 1} / {photos.length}</div>
        </>
      )}
    </div>
  );
}

// Tidslinje (højdepunkter + ferier) — vekslende sider, år-badges.
export function Timeline({ items, renderCard }) {
  let lastYear = null;
  return (
    <div className="timeline">
      {items.map((it, idx) => {
        const year = it.date || it.startDate ? new Date(it.date || it.startDate).getFullYear() : null;
        const showYear = year && year !== lastYear;
        if (year) lastYear = year;
        return (
          <div key={it.id || idx}>
            {showYear && <div className="tl-year">{year}</div>}
            <div className="tl-item">
              <div className="tl-dot" />
              <div className="tl-card">{renderCard(it)}</div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
