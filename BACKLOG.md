# Backlog — Vores familie

Bugs og ønsker til appen. Skriv "Noter …" i chatten, så lægges punktet her.
Bugs tages før features. Når et punkt er lavet, flyttes det til "Lavet" med build-nummeret.

## Bugs

- [ ] App Store-beskrivelsen: punkterne (•) står på én linje i hvert afsnit — sæt ét punkt pr. linje
      (rettes i App Store Connect, kræver intet build).

## Features og forbedringer

- [ ] Påmindelser, der swipes væk på låseskærmen, kommer ikke med i klokken på Hjem
      (kræver en liste over planlagte påmindelser i App Group'en).
- [ ] Versionsnummer: appen hedder 0.1.0 internt — sæt til 1.1 til næste App Store-version.
- [ ] Milepæle og årligt interview: tryk fra notifikation åbner skærmen, men scroller ikke til det enkelte punkt.
- [ ] Web-version til at kigge med (fx bedsteforældre på Android eller computer): read-only via CloudKit JS.
      Første version uden egen server; login med Apple-konto. Se idénoten fra tidligere.

## Til test

- [ ] Build 79: "9 · 5 billeder" i Seneste i familien, tryk åbner fødselsdag 9 år.
- [ ] Build 79: tryk på notifikation (klokke og låseskærm) scroller til selve opslaget.
- [ ] Build 79: Mere → Påmindelser → Vinterferie uge 7/8.
- [x] Build 77+: "Året der gik" på barnets side, widget "På denne dag" med billede, "De første skridt" i en tom familie.
- [ ] Juleferien 2026: kortet på Hjem i feriens sidste dage og ugens spørgsmål lørdagen efter.
- [ ] Del ét barn med den anden forælder (på et testbarn).

## Udgivelse og firma

- [ ] 1.0 (build 71) genindsendt med EULA-link — venter på App Review. Derefter 1.1 med det nyeste build.
- [ ] CVR-nummer (sag B26-FL-00-UD) → App Store Connect: Business/skat og DAC7.
- [ ] Tilmeld Apple Small Business Program (15 % i stedet for 30 %).
- [ ] Forny PMV-registreringen inden oktober 2029.

## Parkeret

- Kommunale ferieplaner/kalenderabonnement — fravalgt; kun nationale skoleferier som anledning til minder.
- Lukket kendt risiko: samtidige skrivninger til notifikationsloggen fra app og udvidelse (sjældent, ufarligt).

## Lavet

- Build 79: skoleferier, scroll til opslag, samlede billedopslag, fødselsdagsfane efter billedets alder.
- Build 77: eksport med opskrifter, De første skridt, import af første år, Året der gik, widget-billede,
  tryk på Seneste i familien, familie-menu i titlen, navne uden "ejer".
- Build 76: nedbrud ved tryk på notifikation fra låseskærmen.
