# Plan: web-version til at kigge med ("kiggeversionen")

Status: plan, ikke startet. Skrevet 20. oktober 2026.

## Formål

Bedsteforældre og andre i familien uden iPhone (Android, pc, Mac) skal kunne **se** familiens minder i en
browser. Kun visning: ingen oprettelse, redigering eller sletning i første version.

## Grundidé

- En **statisk webside** (HTML/JS, ingen build-step), hostet på Cloudflare Pages ligesom familie.prehn.net.
  Forslag til adresse: `kig.familie.prehn.net` (alternativt `familie.prehn.net/kig`).
- Siden taler **direkte med iCloud** via Apples **CloudKit JS**. Der er ingen egen server og ingen database:
  data bliver i familiens iCloud, præcis som i appen.
- Man logger ind med sit **Apple-ID** i Apples eget login-vindue. Siden ser kun det, personen er inviteret til
  (samme deling som "Kun visning" i appen).
- Koster ingenting at drive (CloudKit og Cloudflare Pages er gratis i denne skala) og bruger **ingen
  GitHub-buildminutter**, fordi der ikke skal bygges en app.

## Den store forudsætning: Apple-ID

CloudKit-deling sker mellem iCloud-konti. En bedsteforælder på Android skal derfor have et **Apple-ID**.
Det er gratis og kan oprettes på appleid.apple.com uden en Apple-enhed, men det er et ekstra skridt.
Det er den vigtigste ting at beslutte, om vi kan leve med. Alternativet (et offentligt link uden login)
fraråder jeg: alle med linket ville kunne se børnenes billeder.

## Faser

### Fase 0 — Beslutninger (dig)
1. Er Apple-ID-kravet acceptabelt for jeres bedsteforældre?
2. Adresse: `kig.familie.prehn.net` eller noget andet.
3. Skal web-adgang være Premium? (Deling med bedsteforældre er allerede Premium, så det følger naturligt.)

### Fase 1 — Prøveside (½–1 dag)
Den usikre del først. En simpel side, der:
- logger ind med Apple-ID via CloudKit JS,
- accepterer en eksisterende "Kun visning"-deling,
- viser familiens navn og børnenes navne.
Virker den, er resten "bare" visning. Virker den ikke (fx hvis delte zoner ikke kan læses fra web),
stopper vi her uden at have brugt meget tid.

Du skal gøre én ting i CloudKit-konsollen: oprette en **API-token** til containeren
`iCloud.net.prehn.mindebog` med web-adressen som tilladt oprindelse. Jeg guider dig igennem.

### Fase 2 — Første rigtige version (2–4 dage)
Mobilvenlig, dansk, lyst/mørkt tema, samme udtryk som appen:
- **Hjem:** Seneste i familien og "På denne dag".
- **Børn:** oversigt → barnets side med højdepunkter, dagbog, billedserier (måned for måned, fødselsdage,
  tegninger, maven), milepæle og vaccinationer.
- **Familie:** minder, begivenheder, rejser, traditioner, opskrifter.
- Billeder i fuld skærm, video og lydnoter afspilles.
- Familie-vælger, hvis man er med i flere familier.
Ikke med: breve (forseglede), stamtræ-redigering, kommentarer/reaktioner (kan komme i fase 4).

### Fase 3 — Invitation og lancering (1 dag)
- I appen: invitationsskærmen får "Send link til web" ved siden af det almindelige delingslink, så en
  bedsteforælder på Android får et link, der åbner web-versionen og tager dem gennem login og accept.
- Kort hjælpeside: "Sådan opretter du et Apple-ID" for dem uden.
- API-token til **Production**-miljøet, privatlivspolitikken udvides med web-versionen.
- Nævnes i App Store-beskrivelsen ("bedsteforældre kan følge med fra Android og computer").

### Fase 4 — Senere (valgfrit)
- Reaktioner og kommentarer fra web.
- Tilføj billeder fra web (kræver skriveadgang og mere test).

## Risici

| Risiko | Konsekvens | Håndtering |
|---|---|---|
| CloudKit JS kan ikke acceptere/læse delte zoner som forventet | Projektet kan ikke lade sig gøre som planlagt | Fase 1 tester netop dette først |
| Apple-ID er en barriere for ældre på Android | Færre bruger det | Hjælpeside, og de kan få hjælp af familien én gang |
| Apple vedligeholder CloudKit JS langsomt | Fejl kan være svære at få rettet | Lille kodebase, få afhængigheder |
| Mange store billeder | Langsom side på mobil | Indlæs miniaturer først, fuld størrelse ved tryk |
| Midlertidige billed-links fra iCloud udløber | Billeder forsvinder efter et stykke tid på en åben side | Hent links igen ved behov |

## Hvad jeg skal bruge fra dig
- Svar på de tre beslutninger i fase 0.
- En test-bedsteforælder: et Apple-ID (gerne et ekstra af dit eget), der er inviteret med "Kun visning".
- 10 minutter i CloudKit-konsollen til API-token i fase 1.
