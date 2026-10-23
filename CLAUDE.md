# Projekt: Vores familie (iOS-app)

SwiftUI + CloudKit + StoreKit 2. Bygges uden Mac via GitHub Actions (`.github/workflows/ios-testflight.yml`,
startes manuelt med "Run workflow" på `develop`) til TestFlight.

## Grene

- `develop` — arbejdsgren. Alt arbejde committes og pushes hertil, og alle builds laves herfra.
- `main` — det, der ligger i App Store. Opdateres kun, når Apple har godkendt en version:
  `git checkout main && git merge develop && git tag vX.Y && git push origin main --tags && git checkout develop`
  (tag'et skal pege på det godkendte builds commit). Et push til main starter ikke et build.
- `release/X.Y` — oprettes fra det indsendte builds commit, mens en version er til review (fx `release/1.1`
  = build 87, commit 48952a2). Afviser Apple versionen, rettes fejlen her og bygges herfra ("Run workflow"
  på grenen); rettelsen flettes også ind i develop. Imens har develop næste version (`MARKETING_VERSION`).

## Backlog

GitHub Issues i A-Prehn/familieapp er den eneste liste (labels: fejl, forbedring, test, udgivelse — alle labels er på dansk).
`BACKLOG.md` er kun en henvisning. Luk issues med en kommentar om build-nummeret, når de er bygget og bekræftet,
og sæt versionens milestone (fx `1.2`) på dem. En åben milestone = lavet, men ikke udgivet; den lukkes, når Apple
har godkendt versionen, og den er ude i App Store. Brug `gh` (logget ind som A-Prehn) til issues, builds og logs.

## Builds

Repoet er offentligt (siden 22. okt. 2026), så GitHub Actions-minutterne er gratis. Byg stadig kun, når
brugeren beder om det, og saml flere ændringer i ét build. Build-nummeret = kørselsnummeret på
"iOS TestFlight". Xcode Cloud er forberedt (`ios/ci_scripts/`), men kræver en Mac én gang (issue #38).
Ingen hemmeligheder i repoet: certifikat og nøgle ligger kun lokalt i `ios/signing/` (gitignored) og i GitHub Secrets.

## Skærmbilleder og App Store-materiale

Workflowet "Skærmbilleder (demo-familie)" (`.github/workflows/ios-screenshots.yml`, manuelt) starter appen med
`-demo` (fiktiv familie, kun i hukommelsen — `ios/Mindebog/Demo/DemoFamily.swift`) og tager skærmbilleder med
UI-testen `ios/MindebogUITests`. Resultatet (skærmbilleder, header, og-image, web-WebP) ligger som artifact.
Det gældende materiale ligger i `ios/AppStore/` (se README dér). Billeder: kun Pexels uden ansigter
(`ios/Demo/photos`), aldrig rigtige billeder af børn.

## Priser og Premium

Se `docs/forretningsmodel.md`: gratis = 2 børn; Premium 19 kr/md, 179 kr/år (14 dages prøve) eller 499 kr for altid.

## Hjemmeside

apps.prehn.net (repo A-Prehn/prehn-apps): landingsside `/vores-familie/`, support `/vores-familie/support/`,
privatliv `/vores-familie/privatliv/`. Opdatér i samme omgang, når appens funktioner, Premium, tilladelser
eller datahåndtering ændres.
