# Vores familie — iOS-app

SwiftUI + CloudKit + StoreKit 2. Bygges uden Mac: Xcode-projektet genereres fra `project.yml` med
**XcodeGen**, og **GitHub Actions** (macOS-runner) bygger, signerer og uploader til TestFlight.

## Status

- I App Store: version 1.0 (build 82, tag `v1.0`). Version 1.1 (build 87) er sendt til review.
- Data i brugerens egen iCloud (`CloudKitStore`); `MemoryStore` bruges uden iCloud og til demo-familien.
- Betaling med StoreKit 2: måned, år (14 dages prøve) og for altid — se `../docs/forretningsmodel.md`.

## Mapper

| Mappe | Indhold |
|---|---|
| `project.yml` | XcodeGen: app, widget, notifikations- og del-udvidelse, UI-test, skema |
| `Mindebog/` | Appen (`Models`, `Store`, `Views`, `Book`, `Demo`, `Theme.swift`) |
| `Widget/`, `NotificationService/`, `ShareExtension/`, `Shared/` | Udvidelser og fælles kode |
| `MindebogUITests/` | UI-testen, der tager App Store-skærmbilleder |
| `Demo/` | Fotos (Pexels) og `compose.sh` til demo-familien og App Store-materialet |
| `AppStore/` | Gældende App Store-materiale: tekst, skærmbilleder, header, review-billede |
| `CloudKit/schema.ckdb` | CloudKit-skemaet (importeres i CloudKit Console og deployes til Production) |
| `ci_scripts/` | Xcode Cloud (genererer projektet med XcodeGen efter clone) |
| `signing/` | Lokalt certifikat og nøgle — **gitignored**, aldrig i repoet |

## Workflows (`.github/workflows/`, alle manuelle)

- **iOS TestFlight** — signerer og uploader til TestFlight fra `develop`. Build-nr. = kørselsnummer.
- **iOS build** — bygger til simulator uden signering (hurtig kompileringstest).
- **Skærmbilleder (demo-familie)** — skærmbilleder på 6,9" og 6,3" + header, og-image og web-billeder.

## Byg lokalt (kræver Mac + Xcode)

```bash
brew install xcodegen
cd ios
xcodegen generate
open Mindebog.xcodeproj
```

Demo-familien: kør appen med argumentet `-demo` og miljøvariablen `DEMO_PHOTOS_DIR=<sti til ios/Demo/photos>`.
