# Swift Oref till ivar-dev-os

Datum: 2026-10-29. Status: P0 och P1 klara; motor och inställningar ännu inte ändrade. Se swift-oref-p1-results.md.

## Mål och avgränsning

Portera algoritmkörningen till Swift med bibehållen personlig funktionalitet.
JavaScript förblir standard och finns kvar som valbart alternativ.
Arbetet sker i /Users/daniel/Github/Trio-ivar-dev-os på ivar-dev-os.
LoopFollow, Nightscout och den tidigare Trio-arbetsmappen ska inte behöva ändras.

Underlaget är endast [nightscout/Trio PR #1141](https://github.com/nightscout/Trio/pull/1141).
Senare Swift Oref-buggfixar är uttryckligen en separat etapp.
Detta innebär inte att senare kända fel kan ignoreras vid beslut om skarp användning.

Låsta revisioner:
- Lokal utgångspunkt: c3518648d0bb13f9c20c7cee37badd827699de6c.
- PR base: fdbf70ea2858b1e70fe70d4dea64ab6ee481c285.
- PR head: 2062173891762a538650e1695a13afa3f4f285f4.
- Mergecommit: e4e35d936e3dc369dfd6a9a65edfc4004b20376c.

PR:n omfattar 108 filer, 18 985 tillagda och 256 borttagna rader:
49 filer under OpenAPSSwift och 29 under OpenAPSSwiftTests.
Vi tar kod från den låsta PR-revisionen, inte dagens dev/main.
Enskilda relevanta filer och beroenden har granskats; detta är inte en fullständig
rad-för-rad-revision av alla algoritmmoduler.

## Verifierad lokal utgångspunkt

ivar-dev-os var ren inklusive submoduler vid genomgången. HEAD överensstämmer
med ivar-dev-new. Den gamla arbetsmappen har dock okommitterade ändringar i
G7SensorKit, MedtrumKit, OmnipodKit, project.pbxproj och CustomProgressView.swift.
Brancherna är därför identiska på commitnivå, inte som kompletta arbetsmappar.
Dessa ändringar kopieras inte implicit.

Xcode 27.0 (27A266a) är installerat. Inget appbygge eller algoritmtest har körts
i denna förstudie. Ett baslinjebygge är första implementationens kontrollpunkt.

Den kompletterande JSON-filen innehåller SHA-256 för versionshanterade filer vid
denna genomgång, inklusive JavaScript-resurser, modeller, integrationskod och
projektkonfiguration. Den innehåller inga patientdata.

## Arkitektur som ska bevaras

Befintlig kedja:
APSManager -> profil/autosens -> OpenAPS -> Meal + IOB + DetermineBasal
-> Determination -> lagring/observatörer -> befintlig dosering och uppladdning.

Byt beräkningsfunktionerna bakom OpenAPS. Behåll APSManager:s validering,
pumpkontroller, leveransflöde, Core Data-lagring, observers och integrationer.
Båda motorerna ska leverera samma lokala Determination-kontrakt.

Swift-implementationens naturliga gräns är makeProfile, iob, meal, autosense
och determineBasal. JSONBridge kan initialt användas som adapter för att hålla
ändringsytan liten. Det tar bort algoritmens JS-körning men inte nödvändigtvis
all JSON-serialisering. Ytterligare optimering kommer efter verifierad paritet.

Motorn väljs en gång för hela beräkningsomgången och skickas vidare explicit.
En inställningsändring mitt i en körning får inte blanda JS och Swift.
Profiluppdateringar och simuleringar ska använda samma princip.
Autosens återanvänds i dag i upp till 30 minuter: motorbyte behöver därför
antingen separata cachevärden per motor eller explicit ogiltigförklaring och
omräkning. Även profilcache och samtidiga profiluppdateringar måste hanteras.

## Konkreta skillnader som blockerar direkt merge

### 1. Manuell bolus

PR:n tar bort insulinForManualBolus och manualBolusErrorString från
Determination och lagring. Lokalt används insulinForManualBolus av
BolusCalculationManager och TreatmentsStateModel; fälten skickas även vidare
av NightscoutManager.

Behåll lokala modellfält och lagring. Portera motsvarande JS-beräkningar och
returgrenar till Swift-kompatibilitetslagret. Ersätt inte bortfall med noll eller
med insulinReq: semantiken måste verifieras per returgren, även tidiga returer.

### 2. TDD, Dynamic ISF och insulinuppdelning

Lokala Oref2_variables saknar currentTDD, som upstreams
TrioCustomOrefVariables och DynamicISF förutsätter.
Lokal JS räknar TDD ur pumphistoriken, inklusive hantering av ofullständig
historik, samt returnerar insulin.bolus, insulin.temp_basal och
insulin.scheduled_basal. OpenAPS sparar uppdelningen i Core Data.
Lokal oref2() beräknar historiska medelvärden över tio dagar och två timmar.

Swift-portens DetermineBasalGenerator skapar i de granskade returvägarna
Determination med tdd: nil. Upstreams omgivande TDD-arkitektur kan alltså inte
antas finnas i denna branch.

Portera den lokala TDD-beräkningen till Swift och mata Swift-kärnan via en
tydlig adapter. Bevara aktuell TDD, viktad TDD och historiska medelvärden som
skilda begrepp, tillsammans med insulinuppdelningen. Kontrollera även reason
och vad som faktiskt överlever lagring och läsning tillbaka.
Att bara byta namn på Oref2_variables eller använda senaste sparade TDD som
ersättning för aktuell beräkning räcker inte.

### 3. Glukosunderlag

Lokalt hämtas högst 72 glukosposter. PR:n ändrar determineBasal till ett
tidsfönster baserat på maxMealAbsorptionTime + 0,5 timmar, utan samma gräns.
Dess bas förutsätter också andra parametrar för glukoshämtning.

Behåll först lokalt underlag i båda motorerna för en rättvis jämförelse.
Om Swift kräver ändrat underlag ska det redovisas och testas separat som en
beteendeskillnad. Ta inte med hämtning/smoothing-refaktoreringen slentrianmässigt.

### 4. Tid, JSON och fel

prepare/determine-basal.js skriver över clock med new Date().
Replay behöver frysa Date i testets JS-context, inklusive Date.now och
konstruktorbeteende, och ge Swift samma tid och tidszon.
Testa även sommartid, dygnsgränser och profil-/overridegränser.

Granska null, saknade nycklar, tomma objekt, datumformat, avrundning,
Decimal kontra Double, NaN/icke-finita värden och enheter.
JSONBridge kräver exempelvis meal och autosens för determineBasal, medan den
lokala anroparen kan skicka null för autosens. Beteendet måste uttryckligen
jämföras och anpassas.

Ingen tyst blandning av motorer vid ett fel. Ett Swift-fel ska gå genom
befintlig felhantering och inte skapa en ny dosrekommendation.
En eventuell framtida automatisk återgång till JS kräver egen design och test.

### 5. Andra ändringar i PR:n

PR:n normaliserar dubbla suspend/resume-händelser före IOB, även för JS.
Den ändringen ska klassificeras och provas separat; den befintliga JS-vägen
ska vara en stabil referens.

Importera inte projektfilen, Package.resolved, hela lokaliseringen, CGM-,
Treatments-, JSONImporter- eller lagringsändringar i klump.
Varje nödvändigt modell-/hjälpberoende hanteras uttryckligen.
Behåll det lokalt avstängda middleware-beteendet och befintlig override-expiration.

## Föreslagen patchserie

### P0 — Underlag och baslinje (denna leverans)

- Dokumentera källrevisioner, kompatibilitetsproblem och testkrav.
- Spara referenshashar för JS, modeller, integrationsfiler och submodulrevisioner.
- Ingen ändring av appens beräkningsbeteende.

### P1 — Byggbaslinje och replay (klar 2026-10-29)

- Bygg den nya arbetsmappen och dokumentera eventuella befintliga byggfel.
- Inventera samtliga lokala algoritmanpassningar och Swift-kärnans modellberoenden.
- Skapa lokala, deterministiska testfall mot de faktiska bundlade JS-filerna.
  trio-oref/lib är dokumentationskällor; de är inte i sig bevis på vad appen kör.
- Skapa jämförelser för profil, IOB, Meal, Autosens och DetermineBasal, separat
  samt genom hela kedjan. Spara indata, klocka, tidszon och versionsidentitet.
- Börja med syntetiska data. Upstreams stora replay-databas är inte bifogad PR:n
  och ska inte antas vara tillgänglig.
- Klart när JS-baslinjen går att reproducera utan nätverk eller pump.

### P2 — Swift-kärna och upstreamtester

- Importera de 49 kärnfilerna selektivt från låst PR-head.
- Lägg in relevanta upstreamtester och testresurser med lokal projektanpassning.
- Anpassa endast nödvändiga typer, extensions och testtarget-beroenden.
- Håll motorn frånkopplad från appens aktiva körning tills anpassningen är klar.
- Klart när kärnan bygger och tillämpliga tester körs; eventuella exkluderade
  tester och skälen till detta dokumenteras.

### P3 — Lokal beteendekompatibilitet

- Implementera TDD-/insulinuppdelning och manuell-bolus-fälten i Swift.
- Mappa Oref2_variables, overrides, temp targets, SMB-avstängning och scheman.
- Verifiera Profile/Preferences-mappning inklusive personliga inställningar.
- Testa beräkningsresultat, tidiga returer och hela lagrings-/JSON-kontraktet.
- Klassificera avvikelser mot lokal JS: integrationsfel, lokal anpassning,
  skillnad som redan finns i introduktions-PR:n eller numerisk skillnad.
- Ingen generell tolerans som döljer skillnader i doseringsbeslut.

### P4 — Motorval och tydlig status

- useSwiftOref i TrioSettings, default false även vid läsning av äldre JSON.
- Toggle i befintliga avancerade algoritminställningar och markering av
  faktiskt använd motor för senaste körning.
- Koppla alla fem beräkningsstegen, profiluppdateringar och simulering.
- Lås motorval per omgång och hantera cache vid växling/omstart.
- Låt båda vägarna använda samma befintliga lagrings-, doserings- och
  uppladdningsflöde.
- Klart när båda lägena samt byte åt båda håll och omstart fungerar.

### P5 — Integration och testtelefon

- Kör differentialtester och relevanta befintliga regressionstester.
- Lägg testfall för APNS, shortcuts, lokala behandlingar och samtidiga triggers.
- Verifiera Nightscout-kontraktet för suggested/enacted, IOB/COB, prognoser,
  TDD, insulinuppdelning, bolusfält, timestamps, reason och received.
- Kontrollera samma inputs genom lagring och återläsning, inte enbart rå JSON.
- Använd valbart shadow-läge eller offline-replay för jämförelser.
  Shadow ska endast anropa rena beräkningsfunktioner över samma snapshot:
  simulation:true på hela dagens OpenAPS räcker inte som isolering eftersom
  oref2() fortfarande sparar till storage. Shadow får aldrig skicka pumpkommandon,
  publicera determinations eller skriva till ordinarie lagring/uppladdningskö.
- Mät först fristående Swift mot JS. Shadow dubbelkör och duger inte som mått
  på den slutliga batteriförbrukningen.
- Leverera testbygge, testprotokoll och lista över återstående avvikelser.
  Därefter följer användarens längre provperiod på dedikerad testtelefon.

## Testmatris och acceptans

| Område | Minsta relevanta täckning |
| --- | --- |
| Profil | mg/dL/mmol/L, dygnsbyte, sommartid, basal/ISF/CR, temp target, HBT |
| IOB | bolus/SMB, extern insulinpost, temp basal, suspend/resume, dubbletter, långa pauser |
| Meal | måltid, redigering/radering, FPU, gamla kolhydrater, CGM-luckor, absorptionstid |
| Autosens | saknat värde, 8/24h-underlag, cache, gränser, motorbyte |
| DetermineBasal | lågt/högt/fallande BG, stale/flat CGM, maxIOB, max basal, SMB på/av, UAM |
| Dynamic ISF/TDD | av/log/sigmoid, viktning, ofullständig pumphistorik, nollunderlag, insulinuppdelning |
| Overrides | procent, mål, ISF/CR, utgångstid, obegränsad, schemalagd SMB-avstängning |
| Bolus | manuellt förslag, simulering, samtliga tidiga returgrenar, felvärden |
| Integration | APNS/shortcuts, lagring, NS-payload, notifieringar, samtidiga profiluppdateringar |
| Drift | äldre settings, omstart, växling båda håll, fel, tidsåtgång, CPU och minne |

För doseringsutfall krävs samma beslut och värden efter relevant pumpavrundning,
samt granskade numeriska mellanresultat. Ingen oförklarad doseringsavvikelse
accepteras. Skillnader i texter eller flyttal redovisas per fält; frivilliga och
saknade fält får inte slås samman utan att konsumenterna kontrollerats.

Upstream beskriver 736 480 replay-körningar. Det är upstreams evidens, inte ett
testresultat för vår branch. Vår teststatus ska rapporteras separat.

Prestanda mäts med samma indata, enhet, byggkonfiguration och loggningsnivå:
per modul och hel körning, median/p95, CPU och minne. Batteri följs över längre
jämförbara perioder på testtelefonen. Ingen viss förbättring är ännu uppmätt här.

## Aktuell status efter P3–P5-arbetet

P1-baslinjen är etablerad. P2-kärnan bygger och upstreamtesterna har nu körts
framgångsrikt i en fristående macOS-värd; iOS-simulatorns runtimeproblem kvarstår.
P3/P4 är implementerade med JavaScript som standard. P5:s offlinekontraktstester
passerar, men full prognosparitet, APNS/Shortcuts/Nightscout på telefon samt
prestanda/batteri återstår. Se swift-oref-p345-results.md och telefonprotokollet
swift-oref-test-phone.md. Ingen godkänd skarp drift eller full paritet påstås.

Användarens förtydliganden 2026-10-29:
- PR #1651 motsvarar den befintliga lokala SMB low-temp-korrigeringen. Den ska
  hanteras separat efter introduktions-PR:n. Vid lokal integration har just
  den redan befintliga korrigeringen bevarats även i appens Swift-väg; övriga
  senare PR-fixar är fortfarande utanför omfattningen.
- enableDynamicCR används inte och får utelämnas i Swift-vägen. Det är ett
  accepterat undantag från funktionsparitet. Dynamic ISF ska fortfarande stödjas.

