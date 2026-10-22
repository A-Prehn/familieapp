#!/bin/bash
# Laver web-versioner (WebP), delingsbilledet og App Store-headeren af skærmbillederne.
# Brug: compose.sh <out-mappe>  — forventer <out>/screenshots/6.9/*.png (fra ScreenshotTests).
# Kræver ImageMagick 7 (magick) og cwebp. Farver og skrift følger landingssiden (cream, Georgia).
set -eo pipefail   # ikke -u: tomme arrays fejler i macOS' bash 3.2
OUT="$1"
# Største størrelse med billeder (6,9" helst, ellers 6,3").
SRC=""
for size in 6.9 6.3; do
  if ls "$OUT/screenshots/$size"/*.png >/dev/null 2>&1; then SRC="$OUT/screenshots/$size"; break; fi
done
[ -n "$SRC" ] || { echo "Ingen skærmbilleder at arbejde med"; exit 1; }
echo "Bruger skærmbilleder fra $SRC"
for need in hjem barn familie-minder; do
  ls "$SRC"/*-"$need".png >/dev/null 2>&1 || { echo "Mangler skærmbilledet '$need' i $SRC"; ls -la "$SRC"; exit 1; }
done
WEB="$OUT/web"
mkdir -p "$WEB"

CREAM="#faf8f4"; INK="#2c2820"; MUTED="#7a6f60"; ROSE="#d4547a"
SERIF=/System/Library/Fonts/Supplemental/Georgia.ttf
SERIF_I="/System/Library/Fonts/Supplemental/Georgia Italic.ttf"
SANS=/System/Library/Fonts/Supplemental/Arial.ttf
# Skrifttyper som arrays, så stier med mellemrum ("Georgia Italic.ttf") ikke deles op.
F_SERIF=(); F_SERIF_I=(); F_SANS=()
[ -f "$SERIF" ] && F_SERIF=(-font "$SERIF")
if [ -f "$SERIF_I" ]; then F_SERIF_I=(-font "$SERIF_I"); else F_SERIF_I=("${F_SERIF[@]}"); fi
[ -f "$SANS" ] && F_SANS=(-font "$SANS")

shot() {   # første fil, der matcher navnet (fx "hjem")
  ls "$SRC"/*-"$1".png 2>/dev/null | head -1
}

# Skærmbillede → telefon: afrundede hjørner på skærmen, mørk ramme udenom, let skygge. $1 ind, $2 ud, $3 højde.
phone() {
  local in=$1 out=$2 h=$3
  local r=$(( h * 11 / 100 )) b=$(( h * 2 / 100 ))   # hjørneradius og rammetykkelse
  magick "$in" -resize x"$h" \
    \( +clone -alpha extract \
       -draw "fill black polygon 0,0 0,$r $r,0 fill white circle $r,$r $r,0" \
       \( +clone -flip \) -compose Multiply -composite \
       \( +clone -flop \) -compose Multiply -composite \) \
    -alpha off -compose CopyOpacity -composite "$out.screen.png"
  local w; w=$(magick identify -format %w "$out.screen.png")
  local fw=$(( w + 2*b )) fh=$(( h + 2*b )) fr=$(( r + b ))
  magick -size ${fw}x${fh} xc:none -fill "#1d1a16" \
    -draw "roundrectangle 0,0 $((fw-1)),$((fh-1)) $fr,$fr" \
    "$out.screen.png" -geometry +$b+$b -compose Over -composite \
    \( +clone -background black -shadow 35x40+0+30 \) +swap -background none -layers merge +repage "$out"
  rm -f "$out.screen.png"
}

# 1. Web-versioner af alle skærmbilleder (600 px brede WebP til landingssiden)
for f in "$SRC"/*.png; do
  name=$(basename "$f" .png)
  magick "$f" -resize 600x "$WEB/$name.png"
  cwebp -quiet -q 82 "$WEB/$name.png" -o "$WEB/$name.webp"
  rm "$WEB/$name.png"
done
# … og en "telefon"-udgave af forsiden til toppen af landingssiden
phone "$(shot hjem)" "$WEB/telefon-hjem.png" 1200
cwebp -quiet -q 85 "$WEB/telefon-hjem.png" -o "$WEB/telefon-hjem.webp"

# 2. Delingsbillede 1200×630 (Facebook/Instagram/iMessage)
phone "$(shot hjem)" "$OUT/og-phone.png" 700
magick -size 1200x630 xc:"$CREAM" \
  "${F_SANS[@]}" -pointsize 20 -fill "$ROSE" -kerning 4 -annotate +90+200 "MINDEBOG FOR HELE FAMILIEN" \
  "${F_SERIF[@]}" -pointsize 72 -fill "$INK" -annotate +88+300 "Vores familie" \
  "${F_SERIF_I[@]}" -pointsize 34 -fill "$MUTED" -annotate +90+360 "Mindebogen, der vokser med jer" \
  "${F_SANS[@]}" -pointsize 22 -fill "$MUTED" -annotate +90+420 "De første ord, ferierne og mormors opskrifter —" \
  -annotate +90+452 "privat i jeres egen iCloud." \
  "$OUT/og-phone.png" -geometry +780+70 -compose Over -composite \
  -quality 88 "$OUT/og-image.jpg"
rm -f "$OUT/og-phone.png"

# 3. App Store-header 3840×1646: tre telefoner til højre, tekst til venstre (som den nuværende header)
phone "$(shot hjem)" "$OUT/h-mid.png" 1240
phone "$(shot barn)" "$OUT/h-left.png" 1100
phone "$(shot familie-minder)" "$OUT/h-right.png" 1100
magick -size 3840x1646 xc:"$CREAM" \
  "${F_SANS[@]}" -pointsize 44 -fill "$ROSE" -kerning 10 -annotate +330+560 "MINDEBOG FOR HELE FAMILIEN" \
  "${F_SERIF[@]}" -pointsize 190 -fill "$INK" -annotate +322+770 "Vores familie" \
  "${F_SERIF_I[@]}" -pointsize 76 -fill "$MUTED" -annotate +330+900 "Jeres historie — samlet ét sted" \
  "${F_SANS[@]}" -pointsize 46 -fill "$MUTED" -annotate +332+1030 "Dagbog, milepæle, interview, minder og opskrifter." \
  -annotate +332+1100 "Alt i jeres egen iCloud." \
  "$OUT/h-left.png"  -geometry +1900+330 -compose Over -composite \
  "$OUT/h-right.png" -geometry +2760+330 -compose Over -composite \
  "$OUT/h-mid.png"   -geometry +2250+200 -compose Over -composite \
  "$OUT/header.png"
rm -f "$OUT"/h-*.png

echo "Færdig:"; ls -la "$OUT" "$WEB"
