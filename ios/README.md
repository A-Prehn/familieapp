# Mindebog — iOS-app (fase 2)

SwiftUI-app'en, bygget uden Mac: Xcode-projektet genereres fra `project.yml` med
**XcodeGen**, og **GitHub Actions** (macOS-runner) kompilerer den. Datalaget deler
interface med web-prototypen og skiftes fra `MemoryStore` til `CloudKitStore`, når
iCloud-containeren er sat op.

## Status
- ✅ Skelet der bygger i CI: SignIn → Onboarding → TabView (Hjem/Familie/Mere)
- ✅ Opret familie, opret barn, højdepunkter, begivenheder — via `MemoryStore`
- ✅ SF Symbols som UI-ikoner, farvetema fra familie.prehn.net
- ⏳ `CloudKitStore` (ægte sync, CKShare, CKAsset) — stub, implementeres i fase 2b
- ⏳ Sign in with Apple, resterende sektioner (milepæle, Om dig, gallerier, ferier, fødselsdage)

## Byg lokalt (kræver Mac + Xcode)
```bash
brew install xcodegen
cd ios
xcodegen generate
open Mindebog.xcodeproj
```

## Byg i CI
Push til `develop`/`main` der rører `ios/` → workflow'et `iOS build` bygger appen
til simulator uden signering. Rigtig signering + TestFlight tilføjes med en Apple
Developer-konto.

## Struktur
- `project.yml` — XcodeGen-definition (target, settings, deployment)
- `Mindebog/Models` — datamodeller
- `Mindebog/Store` — `Store`-protokol, `MemoryStore`, `CloudKitStore` (stub)
- `Mindebog/Views` — SwiftUI-skærme
- `Mindebog/Theme.swift` — farver/typografi
- `Mindebog/Mindebog.entitlements` — CloudKit/push (anvendes først ved signering)
