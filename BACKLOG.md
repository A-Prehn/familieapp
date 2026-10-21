# Backlog — Vores familie

Bugs og ønsker til appen. Skriv "Noter …" i chatten, så lægges punktet her og som GitHub-issue.
Issues: https://github.com/A-Prehn/familieapp/issues (labels: bug, enhancement, test, udgivelse). #N = issue-nummer.
Bugs tages før features. Når et punkt er lavet, flyttes det til "Lavet" med build-nummeret.

## Bugs

- [ ] #3 Mere → Premium-teksten nævner ikke "flere familier".
- [ ] #1 AFVIST 21. okt. (2.1b): køb startede ikke for Apples tester (iPad, build 80). Tjek Business → Agreements → Paid Apps = Active, og at begge produkter ikke mangler metadata. Paywallen prøver nu 3 gange + "Prøv igen" (klar til næste build). Derefter nyt build → Resubmit.
- [ ] #2 App Store-beskrivelsen: punkterne (•) står på én linje i hvert afsnit — sæt ét punkt pr. linje
      (rettes i App Store Connect, kræver intet build).

## Features og forbedringer

- [ ] #4 Web-version til at kigge med (fx bedsteforældre på Android eller computer): read-only via CloudKit JS.
      Første version uden egen server; login med Apple-konto. Plan: docs/web-kigger-plan.md (venter på 3 beslutninger).

## Til test

- [ ] #5 Lav et testopslag.
- [ ] #6 1.1: Del fra Fotos (1 og flere billeder, ét og flere børn), søg ("Skagen", "første", et barns navn), anmeldelses-dialog vises ikke i TestFlight (kun i App Store).
- [ ] #7 Build 79: "9 · 5 billeder" i Seneste i familien, tryk åbner fødselsdag 9 år.
- [ ] Build 79: tryk på notifikation (klokke og låseskærm) scroller til selve opslaget.
- [ ] Build 79: Mere → Påmindelser → Vinterferie uge 7/8.
- [x] Build 77+: "Året der gik" på barnets side, widget "På denne dag" med billede, "De første skridt" i en tom familie.
- [ ] #8 Juleferien 2026: kortet på Hjem i feriens sidste dage og ugens spørgsmål lørdagen efter.
- [ ] #9 Del ét barn med den anden forælder (på et testbarn).

## Udgivelse og firma

- [x] App ID net.prehn.mindebog.share oprettet med App Groups (20. okt. 2026).
- [ ] #10 1.0 (build 80) sendt til App Review. Når den er godkendt: sæt MARKETING_VERSION til 1.1 i ios/project.yml før næste build.
- [x] apps.prehn.net kører (GitHub A-Prehn/prehn-apps → Cloudflare Pages prehn-apps, main = produktion).
- [ ] #11 Efter godkendelse af 1.0: Privacy Policy URL → https://apps.prehn.net/vores-familie/privatliv/ og
      Support URL → https://apps.prehn.net/vores-familie/ i App Store Connect.
- [ ] #12 Appens link til privatlivspolitikken (AppLinks.privacy i PaywallView.swift) → ny adresse i 1.1.
- [ ] #13 Først når 1.1 er ude og adresserne er skiftet: familie.prehn.net/privatliv/ må fjernes (ingen viderestilling).
- [x] CVR 40316191 (Prehn apps, PMV, 20. okt. 2026). Skal IKKE i App Store Connect så længe kontoen er personlig og PMV ikke er momsregistreret — først ved momsregistrering eller skift til organisation-konto.
- [ ] #14 Aktivér Digital Post for "Prehn apps": virk.dk-login virker, men Digital Post giver HTTP 401 (20. okt.). Prøv igen 21.–22. okt. i Digital Post-appen eller mit.dk; virker det stadig ikke, ring til Digitaliseringsstyrelsens support.
- [ ] #15 NemKonto: dansk konto skal tilknyttes CVR 40316191 af banken (netbank → NemKonto, eller skriv til banken). nemkonto.dk viser kun status.
- [ ] #16 Tilmeld Apple Small Business Program (15 % i stedet for 30 %).
- [ ] #17 Forny PMV-registreringen inden oktober 2029.

## Parkeret

- Kommunale ferieplaner/kalenderabonnement — fravalgt; kun nationale skoleferier som anledning til minder.
- Lukket kendt risiko: samtidige skrivninger til notifikationsloggen fra app og udvidelse (sjældent, ufarligt).

## Lavet

- Klar til næste build: paywall prøver igen ved hentning af produkter; desuden (1.1): påmindelser, der swipes væk, kommer i klokken; milepæle, vaccinationer og interview åbner det rigtige punkt fra notifikationer; søg i alt (forstørrelsesglas på Hjem); del fra Fotos ("Del → Vores familie"); bed om anmeldelse efter 8 gemte minder.
- Build 80 (version 1.0): ny startskærm uden falsk Apple-login, iCloud-forklaring, prøv uden iCloud.

- Build 79: skoleferier, scroll til opslag, samlede billedopslag, fødselsdagsfane efter billedets alder.
- Build 77: eksport med opskrifter, De første skridt, import af første år, Året der gik, widget-billede,
  tryk på Seneste i familien, familie-menu i titlen, navne uden "ejer".
- Build 76: nedbrud ved tryk på notifikation fra låseskærmen.
