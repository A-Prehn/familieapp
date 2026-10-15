import { useState, useEffect } from "react";

// Generiske line-art motiver i familiesidens varme, tynde streg.
// Bevidst IKKE familiespecifikke — appen er til alle familier.
const SLIDES = [
  {
    tagline: "Et sted til minder, milepæle og øjeblikke",
    art: (
      <>
        <path d="M100 78 C76 70 54 70 38 74 L34 110 C54 104 78 106 100 116 Z" />
        <path d="M100 78 C124 70 146 70 162 74 L166 110 C146 104 122 106 100 116 Z" />
        <path d="M100 78 L100 116" />
        <path d="M48 85 C64 82 82 84 92 88" />
        <path d="M46 95 C64 92 82 94 92 98" />
        <path d="M108 88 C118 84 136 82 152 85" />
        <path d="M108 98 C118 94 136 92 154 95" />
        <path d="M100 60 C100 52 93 46 85 46 C76 46 71 53 71 60 C71 69 83 76 100 86 C117 76 129 69 129 60 C129 53 124 46 115 46 C107 46 100 52 100 60 Z" />
        <path d="M136 40 L136 48 M132 44 L140 44" />
      </>
    ),
  },
  {
    tagline: "Jeres historie — samlet ét sted",
    art: (
      <>
        <path d="M28 88 L100 44 L172 88" />
        <path d="M46 82 L46 132 L154 132 L154 82" />
        <path d="M88 132 L88 104 Q100 97 112 104 L112 132" />
        <path d="M100 80 C100 76 96.5 72.5 92 72.5 C87 72.5 84 76 84 80 C84 86 92 91 100 97 C108 91 116 86 116 80 C116 76 113 72.5 108 72.5 C103.5 72.5 100 76 100 80 Z" />
        <path d="M126 64 L126 51 L136 51 L136 58" />
      </>
    ),
  },
  {
    tagline: "Se dem vokse — måned for måned",
    art: (
      <>
        <path d="M74 116 L80 140 L120 140 L126 116 Z" />
        <path d="M70 110 L130 110 L128 116 L72 116 Z" />
        <path d="M100 116 C98 102 102 92 100 78" />
        <path d="M100 96 C86 98 77 90 75 80 C88 80 97 86 100 96 Z" />
        <path d="M100 90 C114 92 123 84 125 74 C112 74 103 80 100 90 Z" />
        <path d="M100 78 C95 71 95 63 100 57 C105 63 105 71 100 78 Z" />
      </>
    ),
  },
  {
    tagline: "Gem øjeblikkene — del dem sammen",
    art: (
      <>
        <path d="M38 71 Q38 64 45 64 L72 64 L79 53 Q81 50 85 50 L115 50 Q119 50 121 53 L128 64 L155 64 Q162 64 162 71 L162 120 Q162 127 155 127 L45 127 Q38 127 38 120 Z" />
        <circle cx="100" cy="92" r="21" />
        <circle cx="100" cy="92" r="11" />
        <path d="M91 85 C93 82 96.5 80.5 100 80.5" />
        <circle cx="149" cy="75" r="2.4" />
      </>
    ),
  },
];

export default function Hero() {
  const [i, setI] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setI((p) => (p + 1) % SLIDES.length), 5000);
    return () => clearInterval(t);
  }, []);

  return (
    <div className="hero">
      <div className="hero-eyebrow">Mindebog</div>
      <div className="hero-tagline">{SLIDES[i].tagline}</div>
      <svg className="hero-art" viewBox="0 0 200 150" aria-hidden="true">
        {SLIDES[i].art}
      </svg>
      <div className="hero-dots">
        {SLIDES.map((_, idx) => (
          <button
            key={idx}
            className={`hero-dot ${idx === i ? "active" : ""}`}
            onClick={() => setI(idx)}
            aria-label={`Slide ${idx + 1}`}
          />
        ))}
      </div>
    </div>
  );
}
