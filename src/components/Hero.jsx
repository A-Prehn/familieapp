import { useState, useEffect } from "react";
import { BookHeart, House, Sprout, Camera } from "lucide-react";

// Hero-motiver fra Lucide (professionelt line-ikon-sæt) — generiske, passer alle familier.
const SLIDES = [
  { tagline: "Et sted til minder, milepæle og øjeblikke", Icon: BookHeart },
  { tagline: "Jeres historie — samlet ét sted", Icon: House },
  { tagline: "Se dem vokse — måned for måned", Icon: Sprout },
  { tagline: "Gem øjeblikkene — del dem sammen", Icon: Camera },
];

export default function Hero() {
  const [i, setI] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setI((p) => (p + 1) % SLIDES.length), 5000);
    return () => clearInterval(t);
  }, []);

  const { tagline, Icon } = SLIDES[i];
  return (
    <div className="hero">
      <div className="hero-eyebrow">Vores familie</div>
      <div className="hero-tagline">{tagline}</div>
      <div className="hero-art">
        <Icon size={60} strokeWidth={1.3} absoluteStrokeWidth aria-hidden="true" />
      </div>
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
