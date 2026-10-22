# Mindebog — app-projekt

En **offentlig** familie-mindebog som iOS-app (iPhone/iPad). Flere familier skal
kunne bruge den — derfor er **intet hardcodet til én familie**. Al data hører til
den indloggede bruger, og et barn kan **deles** med den anden forælder, så begge
kan lægge op og se hinandens bidrag.

Website-projektet `familie.prehn.net` bruges som **feature-/UX-reference**, ikke
som datakilde.

## Status: React web-prototype (fase 1)

Denne prototype findes for at ramme UI/UX hurtigt i browseren, hvor flowet kan
køres og verificeres. Den **rigtige app bygges bagefter i SwiftUI + CloudKit**
(fase 2). Datalaget her er bevidst skrevet så det 1:1 kan erstattes af CloudKit.

### Bygget og verificeret
Hele website-strukturen fra familie.prehn.net er nu integreret, generaliseret til
flere familier:

- ✅ Log ind (mock Sign in with Apple) + onboarding (opret/deltag i familie)
- ✅ Bund-tabbar: **Hjem**, **Familie**, **Mere**
- ✅ Familie-enhed ejer børn + fælles indhold; deling på familie-niveau (kode)
- ✅ Pr. barn: Højdepunkter (tidslinje), Dagbog, Maven måned for måned,
  Måned for måned, Om dig (Q&A), Milepæle (stort gitter m. foto)
- ✅ Baby "på vej": termin-nedtælling
- ✅ Familie: Begivenheder, Ferier (tidslinje), Fødselsdage (auto + manuelle)
- ✅ Foto-upload + lightbox med swipe

## Kør lokalt
```bash
npm install
npm run dev
```

## Arkitektur — swapbart datalag

Alt dataadgang går gennem ét async interface i [`src/lib/store.js`](src/lib/store.js).
Prototypen bruger `LocalStore` (localStorage). I fase 2 skrives en `CloudKitStore`
med **samme metoder**, og UI-laget ændres ikke.

| Prototype (nu)                 | SwiftUI + CloudKit (fase 2)              |
| ------------------------------ | ---------------------------------------- |
| `LocalStore` + localStorage    | `CKContainer` privat DB + delt DB        |
| Mock `signIn(name)`            | Sign in with Apple / `CKUserIdentity`    |
| `child.memberIds[]`            | `CKShare` på en barn-record              |
| `createInvite` / `acceptInvite`| `UICloudSharingController` + share-URL   |
| Foto som dataURL               | `CKAsset`                                |
| `familieapp:changed`-event     | `CKSubscription` / push (realtids-sync)  |

### Datamodel (generisk, multi-tenant)
- **User** — `{ id, name }` (fra Apple-ID i rigtig app)
- **Child** — `{ id, name, birthDate, gender, ownerId, memberIds[] }`
- **Post** — `{ id, childId, authorId, authorName, text, photo, createdAt }`

## Næste skridt (bygges ovenpå)
- Milepæle, "maven måned for måned", "måned for måned", "om dig" Q&A, højdepunkter
- Foto-crop + galleri med swipe + lightbox (jf. website)
- Fase 2: SwiftUI-app, CloudKit-opsætning, GitHub Actions-/Xcode Cloud-build

## Must-haves (fordi den er offentlig)
- Privatlivspolitik + GDPR (data om **børn** → dataminimering, samtykke, sletteret)
- Apple Developer-abonnement (~$99/år), App Store-review, support

## Forretningsmodel
Freemium: gratis med to børn; Premium (19 kr/md, 179 kr/år med 14 dages prøve, eller
499 kr for altid) gælder for hele familien. Detaljer: [docs/forretningsmodel.md](docs/forretningsmodel.md).
