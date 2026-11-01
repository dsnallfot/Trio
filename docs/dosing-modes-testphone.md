# Behandlingslägen i ivar-dev-os

Implementerat 2026-10-31 med selektiva portar av:
- https://github.com/nightscout/Trio/pull/1511 (head 3365d4b6424bd4cec289f4a847ce09edb8329361)
- https://github.com/nightscout/Trio/pull/1556 (head ac4935a87d5a491cb9fa30a496c37f9094189ea6)

## Användning

Inställningar → Behandlingsläge. LGS och Basaltest visas när Swift-algoritmen är aktiverad. JavaScript kan inte väljas medan något av dessa två lägen är aktivt.

| Läge | Automatik | Overrides/tillfälliga mål |
| --- | --- | --- |
| Sluten loop | Befintligt beteende, inklusive SMB | Tillåtna |
| Öppen loop | Beräknar men skickar inga automatiska doser | Avslutade/blockerade |
| Låg-glukos-suspendering | Kan sänka/stoppa basal; ingen SMB eller temp över ordinarie basalprofil | Avslutade/blockerade |
| Basaltest | Ingen vanlig basaljustering eller dynamisk känslighetsanpassning; låg-glukos-suspenderingen kvar | Avslutade/blockerade |

Basaltest använder PR:ns befintliga kontroll för låg-glukos-suspendering: både aktuellt glukos och prognosen minGuardBG kan utlösa den. Tröskelinställningen för beräkningen blir minst 72 mg/dL (4,0 mmol/L); ett högre sparat värde sänks inte. Sparade inställningar skrivs inte över. LGS behåller PR:ns känslighetsanpassning, men resultatet har dessutom ett uttryckligt tak vid ordinarie basal och ingen SMB.

Lägesbyten väntar på pågående automatisk loop/pumpkommando. Vid byte till annat än closed loop avslutas aktiva overrides/mål; framtida schemalagda mål avbryts också. Presets behålls. Försök att aktivera justeringar blockeras i UI, shortcuts, APNS, Watch och vid Core Data-validering. Gamla schemalagda anrop ogiltigförklaras med en revisionsmarkör. Återgång till closed loop återaktiverar inte avslutade justeringar.

Vid inträde i öppen loop eller basaltest avbryts en pågående automatisk tempbasal. LGS behåller en reducerande temp men avbryter en som ligger över ordinarie basal. Manuella tempbasaler och manuell bolusfunktion finns kvar; basaltest kan inte startas medan en manuell tempbasal pågår. Om pumpen nekar avbrytningen visas ett fel och det nya läget sparas inte. Redan avslutade overrides/mål återställs inte efter ett sådant fel.

Den gamla loop-shortcuten finns kvar och använder samma lägesbytesfunktion: true → closed, false → open. LGS/basaltest väljs i appen.

## Nightscout och text

- Svenska befintliga reason-strängar, TDD/AF/SMB-ordningen och insulinForManualBolus behålls.
- Basaltest lägger till “Basaltest; ingen justering.” när den tidiga returvägen används.
- En eventuell begränsning av en för hög temp till ordinarie basal får en egen reason-text.
- Devicestatus får openaps.dosingMode: closed, open, lowGlucoseSuspend eller basalTesting.
- enacted rapporteras även i de två begränsade automatiska lägena.
- Legacy-fältet closedLoop finns kvar i inställningarnas JSON och är true endast i full closed loop.
- Befintliga oref2-fält behålls. Använd dosingMode för att skilja nya lägen från override-specifika SMB-inställningar.

## Anpassningen av #1556

Den gamla basaltexten visade den senast lagrade tempbasalens hastighet även efter avslut. Den nya visningen använder pumpens aktuella leveransstatus i första hand: ordinarie basal, temp, manuell temp eller pausad pump. Historik och basalprofil används som reserv. Utgångna tempbasaler återgår till rätt profilsegment och en pump-resume återupplivar inte en äldre temp.

Vår äldre Core Data-modell saknar upstreams exakta endDate/isScheduledBasal-fält. Därför porteras inte den nya historikmodellen; aktuell pumpstatus löser bland annat den lokala historikens bortfiltrerade avbrott. Vid övergångsstatus visas “Uppdaterar basal…”. Diagrammets profilritning på onAppear fanns redan lokalt. Ingen ny timer har lagts till: den befintliga, skärmbundna PresentationClockView driver texten.

## Verifiering

- Fullständigt osignerat iOS Debug-bygge för fysisk enhet i en separat APFS-kopia. Den kopians formatteringsfas stängdes av för att inte formatera om användarens arbetsrepo. Thread/address sanitizer stängdes av för enhetsbygget.
- 12 nya native-tester: inställningsmigrering och JSON-roundtrip, Swift-krav, icke-destruktiva preferensbegränsningar, temp/SMB-tak och bevarade manuella bolusfält, sena aktiveringar, Core Data-aktivering/avbrytning, basaltest och basalvisning. Samtliga passerar.
- 228 ordinarie native-tester: 31 redan befintliga felande kontroller för äldre engelska reason-texter, inga nya fel. Sviten är alltså inte helt grön.
- 151 + 66 jämförelser mot frysta lokala Swift-resultat passerar. Dessa kör closed-loop-beteendet inklusive befintliga overrides och jämför hela numeriska resultat/reason-strängar.
- 14 golden-scenarier (70 modulresultat) och tidszonssviten passerar.
- Källgränstestet har en separat manifestfil för de nio avsiktligt ändrade integrationsfilerna. Det är ett hash-/källtest, inte ett verkligt APNS-/Nightscout-test.
- Ingen installation på telefon, verklig pumpkörning eller nätverksbaserad end-to-end-verifiering utförd här. Ingen commit/push.

## Testtelefon

1. Börja i sluten loop med Swift. Kontrollera normal reason-parsning och devicestatus.
2. Aktivera ett override eller tillfälligt mål och välj basaltest. Kontrollera att justeringen avslutas, läget visas i huvudvyn och gammal automatisk tempbasal avbryts. Basaltexten ska visa aktuell leverans, inte den gamla tempens hastighet.
3. Försök aktivera justeringar via UI, shortcuts och APNS i basaltest/LGS/öppen loop. De ska avvisas; avbryt-kommandon ska fortfarande fungera. Presets ska finnas kvar.
4. I basaltest: verifiera ingen vanlig tempjustering/SMB. Med simulerad låg prognos ska låg-glukos-suspenderingen fortfarande kunna föreslås. I LGS ska inga automatiska doser över ordinarie basal skickas.
5. Återgå till sluten loop: ordinarie sparade inställningar ska gälla igen, utan att tidigare overrides/mål återaktiveras.
6. Kontrollera devicestatus openaps.dosingMode, befintliga bolus-/oref2-fält och Nightscout-parsningen. Kontrollera särskilt pumpavbrott/fel vid lägesbyte och basaltext efter tempens utgång/resume.

Native-kommandon (från repots rot):

```sh
python3 scripts/oref-native/setup.py "$PWD" /private/tmp/trio-dosing-check
TZ=UTC swift test -c release -Xswiftc -enable-testing --package-path /private/tmp/trio-dosing-check --filter 'DosingMode|basalTesting|BasalDeliveryReadout'
TZ=Europe/Berlin swift test -c release -Xswiftc -enable-testing --package-path /private/tmp/trio-dosing-check --filter 'ParityGoldenTests|WallClockParityTests|ParityEnvironmentTests'
python3 scripts/test-oref-integration-boundaries.py
```

### Basalhistorik på testtelefonen efter porten av #1300

1. Vid övergång till basaltest medan en automatisk temp pågår, anteckna klockslaget och pumpens visade leveransläge. När pumpens slutrapport har kommit ska tempens fyllda segment sluta där och schemalagd basal visas ljusare fram till nästa beräkning.
2. Kontrollera motsvarande Temp Basal i test-Nightscouts treatments. Den korrigerade posten ska ha samma starttid och id, kortare varaktighet och bara förekomma en gång. Kontrollera Loop Follows visning efter att Nightscout fått korrigeringen.
3. För ett intervall med oförändrad profil kan du jämföra det schemalagda bidraget med profilens E/h gånger antalet timmar. Vid 0,35 E/h under tolv timmar är bidraget 4,2 E. Hela TDD är ett rullande dygn, så äldre insulin kan samtidigt falla ur summan.
4. Vid nästa podbyte, anteckna borttagning och när den nya podden börjar leverera. Jämför glappet med grafen och kontrollera att schemat börjar räknas igen. Ett rapporterat avbrott har företräde framför profilen. Vid ren kontaktförlust uppskattas schemalagd basal tills pumpen lämnar mer historik.

De ljusare segmenten beräknas ur pumpens händelser och den tillgängliga basalprofilen. Om profilen har redigerats under perioden behöver det vägas in i jämförelsen. Redan sparade äldre TDD-sammanställningar skrivs inte om.
