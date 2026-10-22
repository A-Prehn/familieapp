# Vores familie

Mindebogen til hele familien på iPhone — fra Prehn apps. Børnenes højdepunkter, milepæle, det årlige
interview, breve, familiens minder, rejser, traditioner og opskrifter, delt med dem, man inviterer.
Alt ligger i familiens egen iCloud: ingen server, ingen reklamer, ingen sporing.

- App Store: version 1.0 er godkendt; 1.1 (årsabonnement m.m.) er til review.
- Hjemmeside: https://apps.prehn.net/vores-familie/ · support `/support/` · privatliv `/privatliv/`
- Backlog: [GitHub Issues](https://github.com/A-Prehn/familieapp/issues) (eneste liste)

Appen er **multi-tenant**: intet er hardcodet til én familie. Website-projektet familie.prehn.net var
oprindelig feature-reference.

## Repoet

| Sti | Hvad |
|---|---|
| `ios/` | Den rigtige app (SwiftUI + CloudKit + StoreKit 2) — se [ios/README.md](ios/README.md) |
| `ios/AppStore/` | App Store-tekst, skærmbilleder, header og review-billede |
| `docs/forretningsmodel.md` | Priser, gratis/Premium og baggrund |
| `docs/web-kigger-plan.md` | Plan for en web-version til at kigge med (issue #4) |
| `.github/workflows/` | TestFlight-build, simulator-build og skærmbilleder (alle manuelle) |
| `CLAUDE.md` | Arbejdsregler: grene, builds, backlog, hjemmeside |
| `src/`, `public/`, `index.html` | Den oprindelige React web-prototype (fase 1) — bruges ikke længere til appen |

## Grene

`develop` er arbejdsgrenen, og alle builds laves herfra. `main` er det, der ligger i App Store, og
flettes + tagges (fx `v1.0`), når Apple godkender en version.

## Forretningsmodel

Freemium: gratis med to børn; Premium (19 kr/md, 179 kr/år med 14 dages prøve, eller 499 kr for altid)
gælder for hele familien. Detaljer: [docs/forretningsmodel.md](docs/forretningsmodel.md).

## Web-prototypen (historisk)

```bash
npm install
npm run dev
```

Prototypen blev brugt til at ramme UI/UX i browseren, før appen blev bygget i SwiftUI. Datalaget
(`src/lib/store.js`) har samme interface som appens `Store`-protokol.
