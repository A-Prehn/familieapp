# Demo-familie og skærmbilleder (issue #20)

Appen kan startes med argumentet `-demo`. Så bruger den hukommelseslageret (aldrig iCloud) og
indlæser en fiktiv familie fra `ios/Mindebog/Demo/DemoFamily.swift`: Sheila og Martin, børnene
William (9), Nohr (4) og Liv (5 måneder), med højdepunkter, milepæle, interview, opskrifter,
traditioner og en rejse. Billederne læses fra mappen i miljøvariablen `DEMO_PHOTOS_DIR`
(i simulatoren kan appen læse direkte fra Mac'ens filsystem).

`.github/workflows/ios-screenshots.yml` (manuel) kører UI-testen `MindebogUITests/ScreenshotTests`
på en 6,9"- og en 6,3"-simulator, og `compose.sh` laver bagefter web-versioner, delingsbilledet
og App Store-headeren. Alt lander som zip under "Artifacts" på kørslen.

## Billeder (`photos/`)

Alle fra Pexels under [Pexels-licensen](https://www.pexels.com/license/): fri brug, også
kommercielt, uden kreditering. Valgt uden genkendelige ansigter.

| Fil | Pexels-id | Bruges til |
|---|---|---|
| cykel.jpg | 3932867 | Nohr: første tur på cyklen |
| gummistovler.jpg | 12932502 | Nohr: efterår i gummistøvler |
| forste-skridt.jpg | 36018292 | Nohr: første skridt (3 år siden i dag → "På denne dag") |
| kage-3.jpg | 38727904 | Nohr: 3-års fødselsdag |
| tegner.jpg | 7168894 | Nohr: tegning |
| regnbue.jpg | 8014300 | Nohr: tegning |
| lagkage.jpg | 35472148 | William: 9-års fødselsdag |
| finger.jpg | 19314748 | Liv: velkommen til verden |
| fodder-nyfodt.jpg | 28411877 | Liv: måned for måned (nyfødt) |
| fodder-strik.jpg | 39931477 | Liv: måned for måned (3 mdr.) |
| babysko.jpg | 20406227 | Liv: måned for måned (5 mdr.) |
| skagen-klit.jpg | 27038640 | Rejse: Skagen |
| strand-born.jpg | 14187609 | Rejse: Skagen |
| skov.jpg | 37240161 | Minde: efterårstur i Gribskov |
| aeblekage.jpg | 15781460 | Opskrift: Mormors æblekage |
| jul.jpg | 29749448 | Tradition: juleaften |

Adresse: `https://images.pexels.com/photos/<id>/pexels-photo-<id>.jpeg?auto=compress&cs=tinysrgb&w=1200`
