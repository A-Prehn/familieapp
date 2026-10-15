// Dagens citat på Hjem. Egne linjer — ingen kendte citater.
// Samme liste som ios/Mindebog/Models/DailyQuotes.swift
export const QUOTES = [
  "De små øjeblikke bliver de store minder.",
  "Et hjem er ikke et sted, men de mennesker, man savner, når de ikke er der.",
  "Kærlighed måles ikke i store ord, men i små hverdage.",
  "I dag er en dag, I kommer til at ønske, I kunne huske. Skriv den ned.",
  "Børn husker ikke, hvad de fik, men hvordan det føltes.",
  "Familie er der, hvor man altid har en plads ved bordet.",
  "Det rodede hjem er fyldt med levede dage.",
  "Den bedste gave er tid sammen.",
  "Små hænder, store aftryk.",
  "Et kram kan sige det, ord ikke kan.",
  "Grin er det sprog, alle i familien taler.",
  "De lange nætter bliver til korte år.",
  "Hver dag er en side i jeres fælles historie.",
  "Kærlighed vokser, når den bliver delt.",
  "Man bliver ikke færdig med at være forælder, man bliver bare klogere.",
  "Det vigtigste, I kan give hinanden, er nærvær.",
  "Ingen dag er for almindelig til at blive husket.",
  "En familie er et hold, der hepper på hinanden.",
  "Godnathistorier bliver til livshistorier.",
  "Tålmodighed er kærlighed i slowmotion.",
  "Der findes ikke perfekte familier, kun ægte.",
  "Det er de små ritualer, der binder dage sammen.",
  "At blive set er at blive elsket.",
  "Fodspor i sandet, mærker på dørkarmen, minder i hjertet.",
  "Sammen er et af de smukkeste ord.",
  "Den første latter, det første skridt, det første ord — og alt det imellem.",
  "Tryghed er at vide, at nogen altid kommer hjem.",
  "Et barns nysgerrighed er en invitation til at se verden igen.",
  "Kærlighed er at være der — også på de grå dage.",
  "Gem øjeblikket, før det bliver til i går.",
  "Hjemme er der, hvor man kan være helt sig selv.",
  "Familie er de første, man ringer til, og de sidste, der giver op.",
  "Små skridt er også fremskridt.",
  "Det bedste ved i dag er, at I har den sammen.",
  "Et minde er et stykke tid, man får lov at beholde.",
  "Hverdagen er der, hvor livet sker.",
  "Hvert barn bringer sit eget lys med ind i et hjem.",
  "Det er ikke størrelsen på huset, men varmen i det.",
  "Der er altid plads til én mere i et hjerte.",
  "Tak for i dag — og for alt det, I er for hinanden."
];

export function quoteOfTheDay(date = new Date()) {
  const day = Math.floor(new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime() / 86400000);
  return QUOTES[((day % QUOTES.length) + QUOTES.length) % QUOTES.length];
}
