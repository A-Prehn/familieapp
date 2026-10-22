# Forretningsmodel — Vores familie

Gældende fra version 1.1 (oktober 2026). Historikken står nederst.

## Kort fortalt

Freemium: appen er gratis med to børn. Premium låser resten op for **hele familien** — kun én betaler.

| | Pris | Bemærkning |
|---|---|---|
| Månedligt abonnement | **19 kr/md** | `net.prehn.mindebog.premium.monthly` |
| Årligt abonnement | **179 kr/år** | `net.prehn.mindebog.premium.yearly` · **14 dages gratis prøveperiode** · fremhævet i paywallen (~21 % billigere end måned) |
| Premium for altid | **499 kr** én gang | `net.prehn.mindebog.premium.lifetime` · ~2,8 år på årsabonnement, så det er for de få |

- Måned og år ligger i samme abonnementsgruppe ("Vores familie Premium"); år står på level 1, måned på level 2.
- Prøveperioden er kun på året (Apples "introductory offer", én gang pr. Apple-ID i gruppen). Appen viser
  "14 dage gratis" automatisk, når kunden har den til gode (`Purchases.trialEligible`).
- Rækkefølgen i paywallen og på hjemmesiden: måned → år (fremhævet) → for altid (dæmpet).
- Dem, der købte "for altid" til 199 kr i 1.0, beholder Premium.

## Gratis og Premium

Svarer til koden (`AppState.freeChildLimit = 2`, `PaywallReason`) og App Store-teksten.

| Funktion | Gratis | Premium |
|---|---|---|
| Børn | **2** | Ubegrænset |
| Billeder | Ubegrænset | Ubegrænset |
| Alle sektioner (dagbog, højdepunkter, milepæle, Om dig, interview, breve, vækst, gallerier …) | ✅ | ✅ |
| Familie (minder, begivenheder, rejser, fødselsdage, traditioner, opskrifter, stamtræ) | ✅ | ✅ |
| Lydnoter, widgets, påmindelser, notifikationer, søgning | ✅ | ✅ |
| Deling med partneren | ✅ | ✅ |
| Deling med bedsteforældre, resten af familien og en forælder uden for familien | — | ✅ |
| Video (højdepunkter, videobreve, interview) | — | ✅ |
| Film af billedserierne og "Året der gik" | — | ✅ |
| PDF-mindebog (skærm og trykkeri) | — | ✅ |
| Flere familier og skift mellem dem | — | ✅ |
| "Eksportér alt" (ZIP) | ✅ | ✅ |

- **"Eksportér alt" er altid gratis** — løftet om, at minderne aldrig låses inde. (ZIP'en indeholder i dag
  også PDF-mindebogen uden Premium — se issue #36.)
- **Kun én i familien betaler.** Køberens telefon skriver `premiumUntil` på Family-recorden i iCloud, så
  alle i den delte familie får Premium. Apples Family Sharing er slået fra (unødvendig og ville give
  adgang uden for familien).

## Hvorfor sådan

- **Omkostninger er næsten nul.** Data ligger i brugernes egen iCloud — ingen serverregning, der vokser med
  brugerne. Faste udgifter: Apple Developer (~779 kr/år), domæne og tid.
- **Apple tager 15 %** med Small Business Program (ansøgt 22. okt. 2026, issue #16), ellers 30 %.
- **Konkurrenter** har serverudgifter: Tinybeans ~520 kr/år, FamilyAlbum ~410 kr/år, Qeepsake 330–670 kr/år,
  Keepli engangskøb ~350 kr. Vi kan ligge lavere.
- **Engangskøbet er dyrt med vilje.** 199 kr svarede kun til ~10 måneders abonnement, så næsten alle ville
  vælge det. 499 kr gør årsabonnementet til det naturlige valg (issue #30).
- **Gratis med to børn**, så en almindelig familie kan prøve hele appen. Betalingsmuren rammer dér, hvor
  værdien er tydelig: barn nr. 3, bedsteforældrene, video og bogen.
- **Vores vinkel:** "Jeres minder, jeres iCloud." Ingen reklamer, ingen sporing, ingen server.

## Teknisk

- StoreKit 2 (`ios/Mindebog/Store/Purchases.swift`): `Product.products`, `Transaction.currentEntitlements`.
  Ingen server — Apple signerer købene, og appen læser dem lokalt.
- Paywall: `ios/Mindebog/Views/PaywallView.swift`. Gates: `state.isPremium` + `PaywallReason`.

## Åbne spørgsmål

1. Skal ZIP-eksporten indeholde PDF-mindebogen uden Premium? (#36)
2. Fotobøger på print via en partner (høj margin, men kræver fx Peecho/Pixum-API)?
3. Premium uden børn, hvis Børn bliver valgfri (#28)?

---

## Historik

- **22. okt. 2026 (1.1):** årsabonnement 179 kr med 14 dages prøve; for altid hævet fra 199 til 499 kr;
  rækkefølge måned → år → for altid.
- **16. okt. 2026 (1.0):** 19 kr/md eller 199 kr for altid. Gratis hævet fra ét til to børn. Fotogrænsen på
  50 droppet (dyr at tælle på tværs af iCloud og føles som en mur). Partneren gratis.
- **15. okt. 2026:** første plan — 29 kr/md eller 199 kr/år, gratis med 1 barn og 50 fotos, deling med
  partneren som Premium.
