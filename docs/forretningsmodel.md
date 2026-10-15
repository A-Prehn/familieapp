# Forretningsmodel — Mindebog

Udkast, oktober 2026. Et oplæg til beslutning, ikke en færdig plan.

## Udgangspunkt

- **Omkostninger er næsten nul.** Data ligger i brugernes egen iCloud, så der er ingen
  serverregning der vokser med antal brugere. Faste udgifter: Apple Developer (~$99/år),
  domæne, evt. tid til support.
- **Apple tager 15 %** af al in-app-betaling (Small Business Program, under $1M omsætning/år).
- **Konkurrenter** (Tinybeans, Qeepsake, FamilyAlbum, Lifecake): typisk gratis med abonnement
  på 30–80 kr/md eller 300–600 kr/år. Flere af dem lever af reklamer eller sælger fotobøger.
- **Vores vinkel:** "Dine minder, din iCloud." Ingen reklamer, ingen servere, intet der kan lække.
  Det er et reelt salgsargument for forældre, der er varsomme med børnedata.

## Tre modeller

### A. Engangskøb (fx 149 kr)
- ✅ Simpelt, sympatisk, ingen "abonnementstræthed".
- ❌ Ingen løbende indtægt til vedligehold; iOS-opdateringer kræver arbejde hvert år.
- ❌ Lav konvertering hvis prisen sidder foran prøvning.

### B. Freemium + abonnement (anbefalet)
- Gratis: 1 barn, alle sektioner, begrænset antal fotos (fx 50).
- Premium: ubegrænsede børn og fotos, deling med partner, eksport/PDF-mindebog.
- Pris: **29 kr/md eller 199 kr/år** (årlig = ~43 % rabat, driver årsabonnement).
- ✅ Prøv før du betaler, løbende indtægt, Apple håndterer alt (StoreKit 2).
- ❌ Kræver tydelig "hvad får jeg"-skærm, ellers føles det som en mur.

### C. Freemium + engangs-"lifetime" som alternativ til abonnement
- Som B, men med en tredje knap: "Lifetime 499 kr".
- ✅ Fanger dem der hader abonnement. Mange apps ser 20–30 % vælge lifetime.
- ❌ Lidt mere kompleksitet i StoreKit og i App Store-review.

## Anbefaling

Start med **B**, tilføj lifetime (C) efter de første måneder hvis brugere beder om det.
Hold den gratis version reelt brugbar — en forælder skal kunne føre bog om ét barn uden
at betale. Betalingsmuren rammer dér, hvor værdien er tydelig: barn nr. 2, deling med
partner, og de store fotomængder.

## Hvad der låses bag Premium (forslag)

| Funktion | Gratis | Premium |
|---|---|---|
| Børn | 1 | Ubegrænset |
| Fotos | 50 | Ubegrænset |
| Alle sektioner (milepæle, Om dig, dagbog, gallerier) | ✅ | ✅ |
| Familie (begivenheder, ferier, fødselsdage) | ✅ | ✅ |
| Deling med partner | — | ✅ |
| Eksport til PDF-bog | — | ✅ |
| Push-sync i realtid | — | ✅ |

Deling bag Premium er den stærkeste driver: det er præcis det, to forældre vil have.

## Teknisk

- **StoreKit 2** i SwiftUI: `Product`, `Transaction.currentEntitlements`. Ingen server nødvendig
  for at verificere — Apple signerer kvitteringen, og appen læser den lokalt.
- Entitlement-status gemmes i `AppState` (`isPremium`). Gates implementeres som én funktion:
  `state.canAddChild`, `state.canAddPhoto`, `state.canShare`.
- Familien ejer abonnementet: hvis ejeren har Premium, får partneren adgang til det delte
  indhold (det er ejerens iCloud der betaler). Partneren skal ikke købe selv.
- Apple Family Sharing for abonnementet kan slås til i App Store Connect senere.

## Åbne spørgsmål

1. Skal den gratis version have deling, så begge forældre kan prøve det før køb?
2. Pris i andre markeder (Apple foreslår automatisk, men bør tjekkes).
3. Vil vi lave fotobøger på print (høj margin, men kræver partner som fx Peecho/Pixum-API)?
4. Navnet "Mindebog" — tjek varemærke og App Store-tilgængelighed før lancering.

## Næste skridt

1. Beslut model (A/B/C) og priser.
2. Opret abonnementsprodukter i App Store Connect.
3. Implementér StoreKit 2 + paywall-skærm + gates.
4. TestFlight-test af købsflow med Sandbox-konto.
