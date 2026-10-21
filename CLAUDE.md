# Projekt: Vores familie (iOS-app)

SwiftUI + CloudKit + StoreKit 2. Bygges uden Mac via GitHub Actions (`.github/workflows/ios-testflight.yml`,
startes manuelt med "Run workflow" på `develop`) til TestFlight.

## Grene

- `develop` — arbejdsgren. Alt arbejde committes og pushes hertil, og alle builds laves herfra.
- `main` — det, der ligger i App Store. Opdateres kun, når Apple har godkendt en version:
  `git checkout main && git merge develop && git tag vX.Y && git push origin main --tags && git checkout develop`
  (tag'et skal pege på det godkendte builds commit). Et push til main starter ikke et build.

## Backlog

GitHub Issues i A-Prehn/familieapp er den eneste liste (labels: bug, enhancement, test, udgivelse).
`BACKLOG.md` er kun en henvisning. Luk issues med en kommentar om build-nummeret, når de er bygget og bekræftet.

## Builds

GitHub-kvoten er gratis og begrænset (intet betalingskort): byg kun, når brugeren beder om det,
og saml flere ændringer i ét build.

## Hjemmeside

Support- og privatlivsside ligger på apps.prehn.net (repo A-Prehn/prehn-apps). Opdatér den i samme omgang,
når appens funktioner, Premium, tilladelser eller datahåndtering ændres.
