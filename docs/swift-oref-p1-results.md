# P1: byggbaslinje och JavaScript-replay

Datum: 2026-10-29. Branch: ivar-dev-os.
Baslinje: c3518648d0bb13f9c20c7cee37badd827699de6c.

## Resultat

- **BUILD SUCCEEDED**: Trio-workspace, scheme Trio, Debug, generic iOS Simulator,
  utan kodsignering. Ingen app installerades/startades och inga pumpkommandon skickades.
- **15 syntetiska kedjor, 150 lyckade modulkörningar**:
  Profile, Autosens, Meal, IOB och DetermineBasal, både kedjat och isolerat.
- **Riktad SMB-regression passerar**: lokal korrigering ger 0,9 E/h;
  en tillfällig kopia med korrigeringen återställd till det gamla felet ger 0,1 E/h.
  Båda avser 30 minuter och SMB 0,1 E. Testet kontrollerar uttryckligen dessa värden.
- Fel tidszon upptäcks och avvisas.
- Alla 249 referenshashar från förstudien överensstämmer efter bygge och test.
  Ingen versionshanterad produktionsfil eller submodul har ändrats.
- Inga senare Swift-fixar har importerats.

Miljö: macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Apple Swift 6.4.
Replay använder macOS JavaScriptCore. Det är samma motorfamilj som appen,
men detta är inte en verifiering på iOS/testtelefon eller ett test av APSManager,
Core Data, uppladdning, pumpkommunikation eller den kommande Swift-algoritmen.
Appens vanliga XCTest-svit har inte körts i denna etapp.
Bygget har befintliga varningar, bland annat om concurrency och deprecated API:er;
ett lyckat bygge innebär inte att dessa har åtgärdats.

## Kör om

Från repots rot:

```sh
python3 scripts/test-oref-replay.py
```

Kräver macOS, Xcode/Command Line Tools och Python 3. Inga Pythonpaket, npm,
nätverksanrop eller patientdata behövs. Kompilatet och Swift-modulcachen läggs
i en tillfällig katalog som tas bort efter körningen.

Byggkommandot som användes:

```sh
xcodebuild -workspace Trio.xcworkspace -scheme Trio -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/trio-ivar-dev-os-p1-build \
  -resultBundlePath /private/tmp/trio-ivar-dev-os-p1-build.xcresult \
  CODE_SIGNING_ALLOWED=NO build
```

Välj nytt resultBundlePath vid upprepad körning; Xcode skriver inte över en
befintlig xcresult. Projektets ordinarie byggfaser körs, inklusive formatteraren.
Vid denna körning ändrade de inga versionshanterade källfiler.

Lokala fullständiga byggbevis från denna körning:
- /private/tmp/trio-ivar-dev-os-p1-build.log
- /private/tmp/trio-ivar-dev-os-p1-build.xcresult

## Vad testverktyget gör

scripts/oref-replay/main.swift är en fristående process med en ny JSContext per
anrop. Den laddar samma prepare-/bundle-filer och i samma ordning som OpenAPS.
Ingen kopia av trio-oref/lib används som exekverbar algoritm.

Klockan fryses innan algoritmkoden laddas. Date(), new Date(), Date.now(),
Date.parse(), Date.UTC(), explicita datumargument och instanceof kontrolleras.
TZ sätts per process och JavaScripts getTimezoneOffset verifieras.
Detta fångar även wrapperns interna new Date() utan att ändra produktionsfilen.

Testernas anropskedja skapar en profil, räknar Autosens, Meal, IOB och
DetermineBasal. Det är en beräkningskedja över syntetiska snapshots, inte en
emulering av appens cache och ordning för Core Data-hämtning. Alla fem moduler
körs även isolerat med sparade indata så att en tidigare moduls avvikelse kan
skiljas från den aktuella modulens avvikelse.

Varje *.input.json innehåller syntetisk historik, preferenser, klocka och
tidszon. Varje *.expected.json innehåller inputhash, JS-källhashar samt exakta
modulargument och resultat, inklusive IOB-prognos, BG-prognoser, bolusfält,
TDD, insulinuppdelning och reason. TempBasalDuration föregår TempBasal vid
samma tidpunkt, enligt appens loadAndMapPumpEvents.

Jämförelsen är exakt per JSON-fält, med skillnad mellan null och saknad nyckel.
Ingen flyttalstolerans används. Numeriskt identiska JSON-tal som 1 och 1.0
accepteras. Första avvikelsen rapporteras med JSON-sökväg.
Jämföraren har negativa kontroller för ändrad dos, ändrad prognos, saknad
nyckel, bool kontra tal och små numeriska skillnader.

Golden-filerna är registrerade resultat från dagens JS-beteende, inte ett
oberoende bevis på medicinsk korrekthet. Vid registrering kördes varje modul
två gånger; därefter kördes den ordinarie verifieringen mot sparade resultat.
--record är endast för nya fixtures och vägrar skriva över befintliga goldens.
Den normala testkörningen uppdaterar aldrig förväntade resultat.

Reason innehåller befintliga svenska texter och kan även innehålla systemets
lokaliserade tidszonsnamn. En annan macOS-/språkmiljö kan därför kräva utredning
av en ren textavvikelse; uppdatera inte goldens automatiskt för att dölja den.

## Scenarier

| Fixture | Fokus |
| --- | --- |
| rising-bg | Normal kedja med stigande BG |
| falling-bg | Fallande BG och låg tempbasal |
| low-bg | Lågt BG, nolltemp och kolhydratbehov |
| meal-smb | Aktiv COB och faktisk SMB-rekommendation |
| dynamic-log | Logaritmisk Dynamic ISF och TDD |
| dynamic-sigmoid | Sigmoid Dynamic ISF och TDD |
| override-smb-off | Override, ändrat mål och avstängd SMB |
| sparse-glucose | Tre glukosvärden, Autosens felresultat och Meal-fallback |
| stale-glucose | Gammal glukosdata och tidig retur |
| mmol-profile | Profilkonvertering mmol/L till intern mg/dL |
| midnight | Dygnsgräns och basalprofil med två segment |
| dst-spring-before/after | Svensk övergång till sommartid |
| dst-fall-before/after | Svensk övergång till vintertid |
| smb-low-temp.json | Isolerad regression av den lokala SMB-korrigeringen |

72 glukosvärden används i normalfallen, vilket motsvarar den lokala hämtgränsen.
Underlaget täcker inte hela testmatrisen för den slutliga porteringen. Suspend/
resume, externa insulinposter, FPU, alla tidiga returer, fler profil-/targetfall,
cacheväxling, APNS och Nightscout får utökad täckning under P2–P5.

## Lokala algoritmanpassningar att behålla

Historiken och resursdiffen mot e757d5054^ visar tre ändrade exekverbara filer:
bundle/determine-basal.js, bundle/basal-set-temp.js och
prepare/determine-basal.js. Fullständiga resursfingeravtryck finns i
swift-oref-baseline.json; detta fryser även övriga moduler.

- **264391afe**: SMB low-temp-formeln är korrigerad från basal * duration / 30
  till basal * (30 - duration) / 30. Korrigeringen finns i bundlen, inte i den
  medföljande dokumentationskopian under trio-oref/lib.
- **8fe8ffe6c**: middleware avstängt i wrapper och OpenAPS; behåll detta.
- **e757d5054, 4bf425aea, 9b7237214 m.fl.**: SMB-status, MaxSMB med decimaler,
  alltid visad SMB Ratio och svenska reason-texter. Dessa texter är också
  del av det lokala app-/Nightscout-kontraktet.
- OpenAPS har dessutom lokal override-expiration, bolussimulering, reducerad
  loggning, separat JSContext per transaktion och Core Data-refaulting.
  Detta ligger runt beräkningskärnan och ska bevaras vid inkopplingen.
- Lokal manuell-bolus- och TDD-semantik ska behållas, även där skillnaden beror
  på äldre Trio-arkitektur snarare än en personligt skriven ändring.

### PR #1651 och enableDynamicCR

[PR #1651](https://github.com/nightscout/Trio/pull/1651) verifierades som den
motsvarande Swift-korrigeringen. Den mergades 2026-10-20, mergecommit
6f086a96bc22cc0fd7c3bdadad70e9ae5294244b.
Den ändrar DosingEngine till basal * (30 - durationRequired) / 30.
Detta är en **känd förväntad avvikelse** när den orörda #1141-kärnan jämförs
med vår redan korrigerade JS. Den får inte döljas genom justerade goldens.
Själva Swift-fixen ska fortfarande tas i separat senare steg enligt användaren.

Användaren bekräftade 2026-10-29 att **enableDynamicCR inte används** och får
utelämnas i Swift-vägen. Det är därför ett accepterat undantag från full
funktionsparitet. JS-vägen och dess inställningar ändras inte i P1.
Dynamic ISF (log/sigmoid) är ett separat krav och ska fortsatt stödjas.
Vid framtida motorval bör gamla sparade DynamicCR-inställningar hanteras
uttryckligen så att en användare inte får intrycket att Swift stöder dem.

## Modell- och hjälparberoenden inför P2

Samtliga 49 kärnfiler vid #1141-head har hämtats och inventerats utan att
läggas in i appens target. De importerar enbart Foundation, men är inte ett
självständigt paket: de använder följande omgivande typer och hjälpmetoder.
Fjorton relevanta upstreammodellfiler har jämförts med lokala versioner.
Inventeringen ersätter inte kompilatorns kontroll när integrationen påbörjas.

| Beroende | Lokal situation / åtgärd |
| --- | --- |
| Profile, computed targets/ISF, IobResult, GlucoseStatus, Forecast*, ComputedCarbs | Ingår i de 49 kärnfilerna; ComputedCarbs definieras i MealTotal.swift |
| JSON, RawJSON, JSONCoding, Formatter.iso8601* | Finns lokalt; testa datum, null, tomma objekt och avrundning |
| Preferences, InsulinCurve | Finns; enableDynamicCR saknas upstream och får utelämnas enligt användaren. Behåll lokala standardvärden |
| PumpSettings, BasalProfileEntry | Finns; verifiera DIA, basalavrundning och nollbasalvalidering |
| BGTargets, CarbRatios, InsulinSensitivities/Entry | Finns; adapter och profilgenerator måste bevara enheter och scheman |
| TempTarget, TempBasal, CarbsEntry | Finns; kontrollera JSON-nycklar, datum och optionalitet; återanvänd lokala modeller |
| Autosens | Saknar upstreams DebugInfo, debugInfo, deviationsUnsorted och error; komplettera selektivt |
| BloodGlucose | Lokal ID-/device-/value-hantering skiljer; upstream har legacyId/mbg. Importera inte modellen i klump |
| PumpHistoryEvent/EventType/TempType | Finns; upstream har extra isExternalInsulin och ändringar för eventkopior. Mappa lokal isExternal korrekt |
| TrioCustomOrefVariables | Saknas; adapter från Oref2_variables krävs, inklusive aktuell TDD |
| Determination/Predictions | Finns; flera let är var upstream, error-response tillkommer. Behåll lokala bolusfält och Insulin |
| Decimal-hjälpare | Kärnans rounding/jsRounded/clamp samt APS/Extensions/DecimalExtensions.swift behöver kontrolleras mot lokala extensions för överlapp |
| debug(.openAPS, ...) och andra logganrop | Finns i appen; standalone Swift-tester behöver lättviktsadapter |
| TrioSettings | Finns; minimal useSwiftOref-ändring först när motorn kopplas in |
| GlucoseStorage | Förekommer i kärnkommentarer, inte som skäl att importera upstreams lagringsrefaktor |

swift-oref-core-inventory.json låser alla 49 upstreamfiler med SHA-256 och
deklarerade typer samt de 14 modellfiler som granskats. Dessa källor är
forskningsunderlag från #1141, inte en import av dagens dev/main.

## Nästa steg

P1:s bygg- och replay-baslinje är etablerad. P2 kan nu importera Swift-kärnan
och tester selektivt. De sparade modulargumenten är underlag för JS/Swift-
jämförelser. Ingen Swift-paritet eller förbättrad batteritid är ännu verifierad.

