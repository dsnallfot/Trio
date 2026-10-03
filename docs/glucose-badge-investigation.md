# Glukosbadge: uppdateringar i bakgrunden

Undersökt 2026-09-22 efter rapport om att appikonens glukosvärde slutar uppdateras
efter några timmar. Ingen logg från felögonblicket finns ännu, så grundorsaken är
inte verifierad på fysisk telefon.

## Observerat i tidigare kod

- GlucoseStorage skickar updatePublisher efter genomförd batchinsert.
- UserNotificationsManager flyttade eventet till en bakgrundsprioriterad kö och
  startade en fristående Task. FetchGlucoseManager kunde avsluta sin bakgrundstid
  innan denna Task och badge-anropen var klara.
- sendGlucoseNotification satte först badge till noll, före await av databasläsning.
  Därefter köades det nya värdet separat på huvudkön. Flera anrop kunde överlappa.
  Ett avbrott eller läsfel mellan stegen kunde lämna badgen nollställd.
- Hämtning av objekt-ID:n följdes av en separat upplösning i viewContext. Ett fel
  på någon rad avbröt uppdateringen, efter nollställningen. Den extra läsningen
  behövs inte för att få värde, datum och trend.
- Ingen badgeuppdatering vid återgång till förgrunden eller ändrade badge/enhetsval.
- Ingen fast "några timmar"-timeout hittades. 20-minuterspredikatet beräknas om vid
  varje hämtning. Inga andra lokala badge-skrivare hittades i Trio-koden.

## Ändring

Läs scalarvärden på Core Datas egen kö, kör en badgeuppdatering i taget, vänta på
setBadgeCount och håll en kort egen bakgrundsuppgift under arbetet. Nollställ endast
när inställningen är avstängd eller en lyckad läsning saknar värden från senaste
20 minuterna. Ett läsfel loggas och skriver inte över badgen.

Vid återgång till appen och ändrade badge/enhetsval uppdateras badgen utan extra
informationsnotis. Den gamla mmol/L-visningen (t.ex. 65 för 6,5) är bevarad.

## Fysisk verifiering

Kör med badge på och låt telefonen vara låst över flera sensorvärden och över den
period då felet tidigare uppstod. Jämför badge mot senaste värdet i Trio. Kontrollera
också av/på och enhetsbyte samt återgång till appen. Ingen automatisk test här kan
verifiera SpringBoards synliga badge eller verklig suspension efter flera timmar.

Sök i loggen efter `Glucose badge`:

- `refresh started`: uppdateringskedjan har startat.
- `updated`: iOS har slutfört anropet utan fel; datum visar vilket värde som skickades.
  Detta bevisar inte att SpringBoard faktiskt har ritat om ikonen.
- `failed` / `fetch failed`: systemets eller databasens fel.
- `background time expired` / `unavailable`: begränsad bakgrundsexekvering.

Om nytt glukos lagras men ingen refresh startar, undersök händelseleverans/suspension.
Om rätt värde loggas som updated men ikonen förblir gammal, undersök iOS badgebehörighet,
Fokus/hemskärm och eventuella externa push-payloads som innehåller badge.
