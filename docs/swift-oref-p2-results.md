# P2: selektiv Swift-import, 2026-10-29

Historisk rapport från importsteget. Senare testresultat och aktiv integration
beskrivs i swift-oref-p345-results.md. Uppgifterna om frånkopplad motor och
outförda tester nedan beskriver status vid P2, inte dagens slutstatus.

Status: import genomförd; runtime-verifiering återstår. P2 är ännu inte godkänd.

## Omfattning och ursprung

49 Swift-kärnfiler och 29 test-/hjälp-/resursfiler från nightscout/Trio PR #1141,
head 2062173891762a538650e1695a13afa3f4f285f4. SHA-256 för original och lokal
version finns i swift-oref-import.json. Inga senare algoritmfixar har införts.
207 upstream @Test-deklarationer och tre nya lokala modelltester ingår.
Detta är antal deklarationer, inte ett påstående om körda testfall.

Swift-kärnan ingår i appbygget men har inga aktiva anrop från appens befintliga
algoritmflöde. JavaScript är fortsatt enda aktiva motor. Toggle kommer i P4.

## Nödvändiga anpassningar

- Separat SwiftOrefAutosens bevarar gamla Autosens och dess JSON-kontrakt.
- Determination behåller lokala fält; fem egenskaper blir skrivbara för kärnan.
  DeterminationErrorResponse läggs till.
- Swift-konstruktörerna lämnar lokala insulin-/manuell-bolus-fält nil tills P3.
  Detta är inte färdig kompatibilitet med lokala uppladdningar/bolusberäkningar.
- TrioCustomOrefVariables och Decimal-collection mean importeras separat.
- En oanvänd tick-loggvariabel tas bort; fyra testanrop till avrundning använder
  befintlig rounded(scale:). Förväntade testvärden är oförändrade.
- Synkroniserade Xcode-grupper inkluderar kärna och tester. Testtarget höjs från
  iOS 17 till 26 för att kunna importera appen som redan kräver iOS 26.
- Nytt schema TrioOrefTests kör bara TrioTests, i UTC. De äldre testklasserna
  CalibrationsTests, FileStorageTests och PluginManagerTests undantas i just
  detta schema. Ordinarie Trio-schema och samtliga upstream oref-tester behålls.

## Verifiering

Slutlig build-for-testing för generic iOS Simulator lyckades (exit 0,
TEST BUILD SUCCEEDED), både arm64 och x86_64. Logg:
/private/tmp/trio-p2-build-final.log. Xcode varnar bland annat för ett saknat
explicit testtarget-beroende till LibreTransmitter; bygget lyckas ändå.

App och testpaket kompilerade och länkade även i testförsök 3. Körningen fastnade
före teststart på iPhone 17e / iOS 27-simulatorn. Även test-without-building
(försök 4) fastnade; simulatorns statuskommando svarade inte heller normalt.
Försöken avbröts. Ingen godkänd Swift-testkörning kan därför redovisas.
SpringBoard-rapporten 16:39 visar SIGTERM_TIMEOUT vid avstängningen, inte
ett påvisat fel i Trio eller algoritmen. Simulatorn är därefter avstängd.
Ingen simulator har raderats och inga globala simulatortjänster har stoppats.

JS-regression: PASS, 15 scenarier och 150 algoritmanrop med exakt JSON-jämförelse.
SMB-regression: korrigerad lokal kod ger 0.9 U/h; återställd gammal formel 0.1 U/h.
Logg: /private/tmp/trio-p2-js-regression.log.

249 baseline-hashar kontrollerade: endast project.pbxproj och Determination.swift
är ändrade. Befintliga JS-filer, integrationsflöden och submoduler är oförändrade.
git diff --check godkänd.

## Återstående arbete

1. Kör TrioOrefTests när simulatorns teststart fungerar och granska alla utfall.
   Testförsökens loggar/resultat finns under /private/tmp/trio-p2-tests-{3,4}.*.
2. P3: anpassa TDD, insulinuppdelning, manuella bolusfält och lokala overrides;
   jämför Swift mot den bundlade personliga JS-versionen.
3. PR #1651 hanteras separat enligt användarens avgränsning. Swift-importen
   innehåller fortfarande introduktions-PR:ns gamla SMB low-temp-formel.
4. enableDynamicCR får utelämnas; Dynamic ISF ska fortsatt stödjas.

Upstreamtester ersätter inte lokal paritetsverifiering. Detta är ännu inget
färdigt bygge för dosering med Swift eller installation på skarp telefon.
