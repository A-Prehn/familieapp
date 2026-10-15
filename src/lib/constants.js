// Faste data overført fra familie.prehn.net. Generiske — intet familiespecifikt.

export const MONTHS_FULL = [
  "januar", "februar", "marts", "april", "maj", "juni",
  "juli", "august", "september", "oktober", "november", "december",
];
export const MONTHS_SHORT = [
  "JAN", "FEB", "MAR", "APR", "MAJ", "JUN",
  "JUL", "AUG", "SEP", "OKT", "NOV", "DEC",
];

// Milepæle / "Første år" — hvert barn.
export const MILESTONES = [
  { icon: "📅", label: "Terminsdato", key: "due_date", type: "date" },
  { icon: "🌱", label: "Fødselsdag", key: "birth_date", type: "date" },
  { icon: "⏰", label: "Tidspunkt", key: "birth_time", type: "text" },
  { icon: "⚖️", label: "Fødselsvægt", key: "birth_weight", type: "text" },
  { icon: "📏", label: "Fødselslængde", key: "birth_length", type: "text" },
  { icon: "👁️", label: "Øjenfarve", key: "eye_color", type: "text" },
  { icon: "✨", label: "Hårfarve", key: "hair_color", type: "text" },
  { icon: "🚗", label: "Første biltur hjem", key: "first_car_ride", type: "date" },
  { icon: "🩺", label: "Første lægebesøg", key: "first_doctor", type: "date" },
  { icon: "💉", label: "Første vaccination", key: "first_vaccine", type: "date" },
  { icon: "👨‍👩‍👧", label: "Møder bedsteforældre", key: "meets_grandparents", type: "date" },
  { icon: "🐶", label: "Møder familiens dyr", key: "meets_pets", type: "date" },
  { icon: "👀", label: "Genkender forældre", key: "recognizes_parents", type: "date" },
  { icon: "😊", label: "Første smil", key: "first_smile", type: "date" },
  { icon: "😄", label: "Første grin", key: "first_laugh", type: "date" },
  { icon: "🌙", label: "Sover igennem", key: "sleeps_through", type: "date" },
  { icon: "🤸", label: "Vender sig selv", key: "turns_over", type: "date" },
  { icon: "🤒", label: "Første sygdom", key: "first_sick", type: "date" },
  { icon: "🪑", label: "Sidder selv", key: "sits_alone", type: "date" },
  { icon: "🥄", label: "Første mad", key: "first_food", type: "date" },
  { icon: "🥄", label: "Spiser med ske", key: "eats_spoon", type: "date" },
  { icon: "🦷", label: "Første tand", key: "first_tooth", type: "date" },
  { icon: "🧎", label: "Kravler", key: "crawls", type: "date" },
  { icon: "🥤", label: "Drikker fra kop", key: "drinks_cup", type: "date" },
  { icon: "👏", label: "Klapper i hænderne", key: "claps", type: "date" },
  { icon: "👋", label: "Vinker farvel", key: "waves", type: "date" },
  { icon: "🧍", label: "Står med støtte", key: "stands_support", type: "date" },
  { icon: "📣", label: "Siger mor/far", key: "says_mom_dad", type: "date" },
  { icon: "💬", label: "Første ord", key: "first_word", type: "text" },
  { icon: "👣", label: "Første skridt", key: "first_steps", type: "date" },
  { icon: "🚶", label: "Går selv", key: "walks", type: "date" },
  { icon: "🍼", label: "Amning/flaske slut", key: "nursing_ended", type: "date" },
  { icon: "😴", label: "Yndlingssovestilling", key: "sleep_position", type: "text" },
  { icon: "🧸", label: "Yndlingsbamse", key: "fav_toy", type: "text" },
  { icon: "🎵", label: "Yndlingssang", key: "fav_song", type: "text" },
  { icon: "🎄", label: "Første jul", key: "first_christmas", type: "date" },
  { icon: "✈️", label: "Første flyvetur", key: "first_flight", type: "date" },
  { icon: "🏖️", label: "Første strand", key: "first_beach", type: "date" },
  { icon: "🏊", label: "Første bad i hav/pool", key: "first_swim", type: "date" },
  { icon: "👶", label: "Navnedag/dåb", key: "first_baptism", type: "date" },
  { icon: "🎂", label: "Første fødselsdag", key: "first_birthday", type: "date" },
];

// "Om dig" — Q&A, faste temaer og spørgsmål.
export const ABOUT_ME_SECTIONS = [
  { title: "Om graviditeten", questions: ["Hvornår fandt vi ud af at du var på vej?", "Hvad var vores første reaktion?", "Hvad håbede vi at du ville blive?", "Hvad kaldte vi dig mens du var i maven?"] },
  { title: "Din personlighed", questions: ["Hvad får dig til at grine?", "Hvad er du allermest nysgerrig på?", "Er du mest genert eller frembrusende?", "Hvad er du stolt af?", "Hvad er du bange for?", "Hvad trøster dig når du er ked af det?", "Hvad gør du når du er træt?", "Er du et morgenmenneske eller en natteravn?"] },
  { title: "Dine favoritter", questions: ["Hvad er din yndlingsfarve?", "Hvad er din yndlingsmad?", "Hvad er dit yndlingsdyr?", "Hvad er dit yndlingsstuffe / bamse?", "Hvad er din yndlingsfilm / -serie?", "Hvad er dit yndlingsord?", "Hvad er din yndlingsleg udenfor?"] },
  { title: "Dine vaner og rutiner", questions: ["Hvordan vil du helst falde i søvn?", "Hvad kan du ikke sove uden?", "Hvad er det første du gør om morgenen?", "Hvad siger du altid inden du sover?", "Hvad er din bedste undskyldning for ikke at ville sove?"] },
  { title: "Dit forhold til os", questions: ["Hvad kalder du os?", "Hvad gør du når du vil have opmærksomhed?", "Hvad er dit yndlingskram?", "Hvad siger du når du er glad for os?", "Hvad gør vi der irriterer dig allermest?", "Hvad gør vi der gør dig allermest glad?"] },
  { title: "Dit forhold til verden", questions: ["Hvad vil du gerne være når du bliver stor?", "Hvad tror du der bor under sengen?", "Hvad mener du er uretfærdigt?", "Hvad synes du er det bedste ved at være barn?", "Hvad er det sværeste?", "Hvad ville du gøre hvis du bestemte alting?"] },
  { title: "Sjove citater", questions: ["Hvad er det morsomste du har sagt?", "Hvad har du gjort som vi aldrig glemmer?", "Hvad har du sagt der overraskede os?", "Hvad har du forklaret os på din helt egen måde?"] },
];

// Dato-hjælpere
export function daysUntil(dateStr) {
  if (!dateStr) return null;
  const now = new Date(); now.setHours(0, 0, 0, 0);
  const d = new Date(dateStr); d.setHours(0, 0, 0, 0);
  return Math.round((d - now) / 86400000);
}

export function formatDate(dateStr) {
  if (!dateStr) return "";
  const d = new Date(dateStr);
  return `${d.getDate()}. ${MONTHS_FULL[d.getMonth()]} ${d.getFullYear()}`;
}

export function ageFromBirth(birthDate) {
  if (!birthDate) return null;
  const b = new Date(birthDate);
  const now = new Date();
  let months = (now.getFullYear() - b.getFullYear()) * 12 + (now.getMonth() - b.getMonth());
  if (now.getDate() < b.getDate()) months -= 1;
  if (months < 0) return null;
  if (months < 24) return `${months} mdr.`;
  return `${Math.floor(months / 12)} år`;
}
