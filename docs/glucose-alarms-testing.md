# Lokala glukoslarm med AlarmKit

Implementerat i ivar-dev-new 2026-09-21. Avgränsad anpassning inspirerad av
[Trio #1203](https://github.com/nightscout/Trio/pull/1203) och
[Trio #1375](https://github.com/nightscout/Trio/pull/1375).

## Inställningarna är separata

- **Larm för lågt/högt glukos:** egna av/på-val, oavsett sensortyp, direktanslutning,
  eavesdropping eller annan glukoskälla. Gränserna är befintliga lowGlucose/highGlucose.
- **Larma genom tyst läge och Fokus:** väljer AlarmKit för aktiverade låg/hög-larm.
  Kräver separat iOS-behörighet. Avstängt/nekad behörighet innebär vanlig notis med
  valt ljud som reserv, inte ljud genom tyst läge/Fokus. Om iOS-notiser också är
  nekade finns ingen sådan reservleverans; detta visas i inställningsvyn.
- **Glukosnotiser – Avaktiverade / Alltid / Endast vid alarmgränser:** det gamla
  informationsflödet. Detta val stänger inte av de nya låg/hög-larmen. Notiserna
  har inget eget larmljud längre, för att undvika dubbla ljud.
- **Spela upp ljud för kolhydratbehov:** den tidigare useAlarmSound-inställningen
  behåller kolhydratljudet. Den styr inte de nya glukoslarmen.
- **Snoozetid:** separata val för låg/hög, 5–60 minuter i steg om 5.
  Stop pausar endast den kvitterade larmtypen. Tidigare gemensamt val blir startvärde
  för båda; utan tidigare val används 15 minuter.
  En redan påbörjad paus behåller sin sluttid om inställningen ändras.
- **notificationsRemote:** befintlig toggle och kommandonotiser är bevarade.

| Önskat beteende | Inställning |
| --- | --- |
| Bara AlarmKit-glukoslarm | Låg/hög på, AlarmKit på och tillåtet, Glukosnotiser avaktiverade. |
| Bara informationsnotiser utan glukoslarmljud | Låg/hög av, Glukosnotiser Alltid eller Endast vid alarmgränser. |
| Både informationsnotiser och AlarmKit | Låg/hög på, AlarmKit på och tillåtet, Glukosnotiser efter önskemål. |
| Glukoslarm med vanligt notisljud | Låg/hög på, AlarmKit av. Kräver tillåtna iOS-notiser. |

Vid första användningen sätts de nya låg/hög-reglagen på endast om gamla
useAlarmSound var på och glukosnotiser inte var avaktiverade. Därefter sparas och
ändras de nya reglagen självständigt. Gränser och notificationsRemote ändras inte.

## Fyra larmnivåer

Akut låg och akut hög har egna av/på-val, ljud, snoozetider (5–60 minuter) och
systemtestknappar. De börjar avstängda, med gränserna 40 respektive 400 mg/dL
som initiala väljarlägen och 15 minuters snooze. Välj önskade gränser när larmen aktiveras.
Befintliga låg/hög-val, ljud och snoozetider bevaras vid uppdatering.

Gränserna lagras i mg/dL och visas i användarens glukosenhet. Akut låg kan väljas
från 40 mg/dL (visas som 2,2 mmol/L) till den vanliga låggränsen. Akut hög kan
väljas från den vanliga höggränsen till 400 mg/dL (22,2 mmol/L). Ändras en vanlig
gräns begränsas den effektiva akuta gränsen även i larmutvärderingen, oberoende av UI.
Vanliga gränser är åtkomliga även med informationsnotiser avstängda.

Vid akut nivå väljs endast det akuta larmet om det är aktiverat; ett pågående
vanligt larm återkallas. Samma prioritet gäller vid lika gränser och när det akuta
larmet snoozats, så vanligt larm inte används som reserv under akut snooze.
Avstängt akut larm hindrar däremot inte ett aktiverat vanligt låg/hög-larm.
En paus för vanligt låg/hög blockerar aldrig eskalering till akut nivå. Alla fyra
pauser sparas separat och överlever omstart. Global snooze pausar alla fyra.
När värdet återgår till vanlig låg/hög-nivå gäller den larmtypens egna val och paus.

På testtelefonen: prova endast akuta togglar, sedan alla fyra; verifiera eskalering
från ett pågående respektive snoozat vanligt larm. Prova även akut snooze, omstart,
normalisering, lika gränser samt ändrad låg/hög-gräns. Använd kontrollerade testvärden
eller tillfälliga gränser på testinstallationen och återställ efteråt.

## Larmregler

- Ett positivt, aktuellt värde räcker; trend och delta behövs inte. Tidsstämpeln får
  inte ligga i framtiden och värdet får vara högst 12 minuter gammalt.
- Lågt är <= låggränsen; högt är >= höggränsen. Låggränsen måste vara lägre än höggränsen.
- Okvitterade larm upprepas vid nästa nyare, fortfarande aktuella glukosvärde,
  normalt var femte minut. Minimiintervallet är 4,5 minuter för att tåla variation i
  leveranstiden. En timer kan ompröva ett tidigt inkommet värde efter detta intervall,
  men samma redan larmade värde kan aldrig upprepas.
- Att systemlarmets ljud/UI löper ut startar ingen snooze. Endast kvittering via
  Stop/Pausa (eller öppnande av reservnotisen) startar den valda pausen, räknat från
  kvitteringstillfället. Global snooze gäller fortfarande separat.
- Stop-knappen pausar endast den aktuella larmtypen enligt dess snoozetid.
  En paus för högt glukos hindrar därför inte låglarm, och omvänt.
  Trios befintliga globala snooze pausar alla fyra typerna, även efter omstart.
  En redan aktiv gemensam paus från äldre larmkod gäller till sin ursprungliga sluttid.
- Normalisering återkallar aktivt larm. Ett nytt gränsöverskridande kan larma igen.
- Backfill utvärderas genom det senaste sparade värdet, inte genom varje rad i batchen.
  Samma tidsstämpel larmar inte igen. Ett historiskt men faktiskt senaste och ännu
  aktuellt värde kan däremot utvärderas.
- Radering som blottlägger ett äldre värde återkallar larmet och återaktiverar det
  inte från den äldre raden. Dubbletter och omstart återspelar inte samma larm.
- Avstängning av ett låg/hög-larm återkallar det pågående larmet. Byte av AlarmKit-läge
  stoppar det aktiva larmet; samma värde spelas inte genast upp en gång till.

## Implementation

`TrioAlertManager` sköter läsning av aktuellt glukos, leverans, system-ID:n och kvittering.
`GlucoseAlarmState` är den rena, testbara beslutslogiken. Inställningar och larmstatus
sparas i UserDefaults; ingen ytterligare Core Data-modell behövs.

Manager och inställningar använder huvudaktören. Core Data-objekt lämnar inte sin
context-kö. Endast ett värde och dess datum flyttas till beslutslogiken. En revision
förhindrar att en äldre asynkron läsning kör över en senare utvärdering. En kort
bakgrundsuppgift täcker läsning och schemaläggning vid Bluetooth-väckning.

En pågående asynkron schemaläggning återkallas om larmet hunnit stoppas. UUID:n
sparas före AlarmKit-anropet så att ersatta systemlarm kan städas efter omstart.
Stop-intenten hanterar exakt UUID och kan inte kvittera ett annat, senare larm.
Befintlig UserNotificationsManager behåller rollen som notisdelegate och routar
endast den nya kategorins svar till TrioAlertManager.

Alla 18 .caf-ljuden kommer från officiella Trios ljudkatalog och kopieras individuellt till
appbundlens rot. Förhandslyssning och AlarmKit-test är separata funktioner.

## Kontroll på fysisk testtelefon

1. Öppna glukosnotisinställningarna. Kontrollera att låg/hög inte oväntat slagits på,
   att gränserna är kvar och att sektionen har samma bakgrund som övriga inställningar.
2. Tillåt systemlarm. Välj ett ljud och tryck **Testa lågljud om 10 sekunder**.
   Lås telefonen före larmet. Prova även hög-ljudet, tyst läge och Fokus.
3. Stoppa med systemets knapp. Testlarm påverkar inga glukosvärden, ingen dosering
   och ingen pågående glukoslarmpaus. Testet kan också avbrytas i inställningsvyn.
4. Testa de fyra kombinationerna i tabellen ovan. Informationsnotis och larm kan
   båda visas om båda funktionerna är på, men informationsnotisen spelar inget extra ljud.
5. Kontrollera ett verkligt mottagningsflöde utan internet men med fungerande
   sensoranslutning. AlarmKit-testknappen verifierar ljudkanalen; den verifierar
   inte automatiskt sensormottagningen eller gränsutvärderingen.
6. Testa Stop/global snooze, omstart, backfill och radering med kontrollerade
   testvärden eller tillfälligt anpassade larmgränser på testinstallationen.
   Återställ gränserna efteråt. Verifiera att pump-/fjärrnotiser fungerar som tidigare.
7. Neka/återkalla AlarmKit-behörighet och kontrollera reservnotisen. Neka även
   vanliga notiser och kontrollera att begränsningen visas i inställningsvyn.

Ett redan schemalagt AlarmKit-larm levereras av iOS. Nya glukoslarm kräver fortfarande
att Trio tar emot och utvärderar ett värde. Detta inför inte något larm för utebliven
sensoranslutning eller utebliven loop. Stale/normaliserade larm kan återkallas först
när Trio får exekvering; AlarmKit övervakar inte databasens glukosvärden själv.

## Verifiering

Kör `bash scripts/test-glucose-alarms.sh` från projektroten. Det kör produktionskodens
beslutslogik och den riktiga Codable-lagringen för befintlig snooze, i en temporär
UserDefaults-domän. 205 kontroller täcker låg/hög, enstaka värden, av/på, tidsgränser,
upprepning, backfill, radering, kvittering, omstart och snooze.

Simulatorbygge har verifierat AlarmKit-/AppIntent-koden. Ljudfilerna i appbundlens
rot har kontrollerats byte för byte mot källfilerna (samtliga 18 ljud).
Hörbart ljud, systemets Stop-knapp och bakgrundsbeteende behöver fortfarande
verifieras på den fysiska telefonen.

Repetition på fysisk telefon: låt ett ordinarie larm ljuda utan Stop/Pausa och
kontrollera nästa två sensorvärden. Kvittera därefter och kontrollera att vald
snooze gäller hela perioden samt att eskalering till akut nivå fortfarande fungerar.
Testljudsknapparna testar endast ljudleveransen, inte denna repetitionslogik.
