import { useState, useEffect } from "react";

// Generiske line-art motiver i familiesidens varme, tynde streg.
// Bevidst IKKE familiespecifikke — appen er til alle familier.
const SLIDES = [
  {
    tagline: "Et sted til minder, milepæle og øjeblikke",
    art: (
      <>
        <path d="M100 118 C78 104 50 104 34 110 L34 66 C50 60 78 60 100 74 C122 60 150 60 166 66 L166 110 C150 104 122 104 100 118 Z" />
        <path d="M100 74 L100 118" />
        <path d="M46 80 Q70 74 90 83 M46 93 Q70 87 90 96" />
        <path d="M110 83 Q130 74 154 80 M110 96 Q130 87 154 93" />
        <path d="M100 54 C100 48 94 42 86 42 C77 42 73 49 73 55 C73 64 86 71 100 79 C114 71 127 64 127 55 C127 49 123 42 114 42 C106 42 100 48 100 54 Z" />
      </>
    ),
  },
  {
    tagline: "Jeres historie — samlet ét sted",
    art: (
      <>
        <path d="M32 84 L100 40 L168 84" />
        <path d="M48 78 L48 130 L152 130 L152 78" />
        <path d="M86 130 L86 100 Q100 93 114 100 L114 130" />
        <path d="M100 68 C100 64 96 60 91 60 C85 60 82 65 82 69 C82 75 91 80 100 86 C109 80 118 75 118 69 C118 65 115 60 109 60 C104 60 100 64 100 68 Z" />
      </>
    ),
  },
  {
    tagline: "Se dem vokse — måned for måned",
    art: (
      <>
        <path d="M76 116 L82 140 L118 140 L124 116 Z" />
        <path d="M76 116 L124 116" />
        <path d="M100 116 C100 98 100 84 100 72" />
        <path d="M100 94 C86 94 78 84 76 72 C90 72 98 82 100 94" />
        <path d="M100 90 C114 90 122 80 124 68 C110 68 102 78 100 90" />
        <path d="M100 72 C96 64 96 56 100 50 C104 56 104 64 100 72" />
      </>
    ),
  },
  {
    tagline: "Gem øjeblikkene — del dem sammen",
    art: (
      <>
        <path d="M40 68 Q40 62 46 62 L74 62 L82 50 L118 50 L126 62 L154 62 Q160 62 160 68 L160 118 Q160 124 154 124 L46 124 Q40 124 40 118 Z" />
        <circle cx="100" cy="90" r="22" />
        <circle cx="100" cy="90" r="11" />
        <circle cx="146" cy="74" r="3" />
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
