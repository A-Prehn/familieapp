import { useState } from "react";
import { useApp } from "../lib/AppContext";

// Mock "Sign in with Apple". I den rigtige app kommer navnet fra Apple-ID'et.
export default function SignIn() {
  const { signIn } = useApp();
  const [name, setName] = useState("");

  return (
    <div className="center-screen">
      <div className="hero-emoji">👶</div>
      <h1 className="large-title" style={{ textAlign: "center", margin: "4px 0 8px" }}>
        Mindebog
      </h1>
      <p className="tagline">
        Saml milepæle, billeder og øjeblikke for jeres børn — og del dem med den
        du har dem sammen med.
      </p>

      <label className="field">
        <span>Dit navn (prototype — erstattes af Apple-ID)</span>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="F.eks. Mor eller Far"
        />
      </label>

      <button className="apple-btn" onClick={() => signIn(name)}>
         Fortsæt med Apple
      </button>
      <p className="note" style={{ textAlign: "center" }}>
        I prototypen opretter dette bare en lokal profil, så du kan afprøve
        flowet — også med to "forældre" i samme browser.
      </p>
    </div>
  );
}
