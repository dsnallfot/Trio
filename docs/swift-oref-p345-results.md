# P3–P5: lokal integration och offlineverifiering

Datum: 2026-10-29. Branch: ivar-dev-os, arbetsmapp Trio-ivar-dev-os.

P3 och P4 är implementerade. P5:s offlinekontroller är genomförda, men full
paritet och telefonens integrations-/drift-/prestandatester återstår.
Se swift-oref-test-phone.md för telefonprotokollet.

## Implementerat

- Alla fem steg (profil, autosens, meal, IOB, determine basal) kan köras i Swift.
- JavaScript är standard; äldre eller ogiltig useSwiftOref-inställning blir false.
- En FIFO-grind skyddar hela kedjan och fristående profil-/autosensuppdateringar
  över async-avbrott. Motorvalet läses en gång per operation och skickas explicit
  till varje steg. Samma väg används av ordinarie och simulerade beräkningar.
- Vid motorbyte, eller saknad äldre motormarkör, rensas profil, pumpprofil,
  autosens och IOB-cache. Profiler byggs före beräkningen; fel propageras och
  ingen tyst fallback till JS sker. Motorval och cachemarkör består över omstart.
- Reglage i Extra inställningar samt faktiskt använd motor, tid och total
  tidsåtgång för senaste lyckade körning. 576 tidsprov sparas separat.
- TDD beräknas från samma lokala pumphistorik med pumpinkrement per segment,
  bolus/tempbasal/schemalagd basal, historikgräns för Dynamic ISF och samma
  viktade historiska TDD-indata. Befintlig Core Data-hämtning är kvar.
- Lokal Oref2-mappning, overrides, SMB-scheman och träningslägets IOB-effekt.
- Manuella bolusfält och felkoder följer lokala returgrenar. Saknade fält hålls
  separata från noll. TDD/insulin, ISF, mål och bolusfält använder befintliga
  Determination-/Core Data-/Nightscout-konsumenter.
- Anpassade JSON-gränser för Core Data-glukos, tempbasal och mmol-scheman.
  Lokalt COB avrundas som JS; decimalrepresentation bevaras efter IOB-avrundning.
- Lokal cancellation vid gammal/flat/brusig CGM och befintlig SMB low-temp-fix
  bevaras. Den sistnämnda motsvarar korrigeringen som diskuteras i #1651, men är
  införd som lokal kompatibilitet, inte som en merge av senare PR-serier.
  Upstreamtesternas defaultväg för SMB är kvar; appens Swift-väg väljer uttryckligen
  den lokala varianten. Övriga senare PR-fixar har inte importerats.
- enableDynamicCR används inte i Swift-vägen enligt överenskommelsen.

## Körda kontroller

- App och iOS-testpaket: build-for-testing, unsigned arm64 simulator, lyckat.
  Ingen iOS-runtime-testkörning påstås vara genomförd.
- 213 Swift-testfall i 30 sviter passerar på macOS. Dessa omfattar 207
  upstreamtester och sex lokala modell-/gränssnitts-/samtidighetstester.
  Ett extra iOS-specifikt migrationstest kompileras men har inte körts på iOS.
- 15 frysta JS-scenarier: 150 exakta JS-replays passerar, inklusive lokal SMB-fix.
- Samma 15 scenarier genom Swift: 150 modulanrop, isolerat och genom kedjan.
  De explicit listade doserings-/bolus-/TDD-fälten matchar exakt, utan tolerans.
- 13 extra syntetiska scenarier genom båda motorerna: ISF/CR-varianter,
  override-mål, ändrade SMB-minuter, dag-/nattschema, helt avstängd SMB,
  Dynamic ISF med högt mål/kort/tom historik, träningsläge och lågt temp target.
  Doseringskontrakten matchar exakt. 130 modulanrop totalt i dessa kontroller.
- Isolerad SMB-regression: Swift ger 0.9 E/h, 30 minuter och 0.1 E SMB,
  samma som den korrigerade lokala JS-bundlen.
- Källkodsgränser: 9 APNS/remote-, 22 shortcuts-, 7 Nightscout- och 18 JS-filer
  matchar P1-hasharna. Detta är en källkodsregression, inte ett runtimebevis för
  nätverk, iOS Shortcuts eller APNS. Telefonprotokollet täcker dessa luckor.

## Kvarvarande skillnader och begränsningar

Full JSON-/algoritmparitet är inte uppnådd. Replayrapporten listar exakta
skillnader per fält och scenario, utan att ändra JS-goldenfiler:

- 19 av 30 determine-basal-jämförelser har prognosskillnader. Isolerade körningar
  visar enstaka avrundningsskillnader på 1 mg/dL; hela kedjan visar också
  skillnader i nolltemp-prognosens längd/värden kring dygns-/sommartidsgränser.
  Dessa är ännu inte slutligt förklarade/godkända för skarp drift.
- Dynamic ISF kan skilja på sista flyttalsdecimalen i sensitivityRatio.
- Diagnostiktexter är delvis engelska; vissa råa JS-diagnostiknycklar saknas i
  Swift-modellen. Befintlig lokal Determination avkodade inte heller dessa
  nycklar (t.ex. tick, BGI, target_bg). UUID/received/timestamp skiljer sig i rå
  JSON; appens befintliga lagringsflöde används fortsatt.
- Imported IOB har striktare kontroll av trasiga basal/duration-par än JS.
  Orphan duration-only-poster ignoreras som i JS; en basal som saknar duration
  ger fortfarande fel. Swift-fel ger inget doseringsresultat och ingen fallback.
- macOS-värden kompilerar samma algoritmkällor och modellkod. UIKit/HealthKit/
  LoopKit-specifika tillägg utelämnas och loggning/icke använda app-typer ersätts
  av små stödfunktioner. Den testar inte Core Data, pumpkommunikation eller UI.
- Inga telefonmätningar, APNS-leveranser eller Nightscout-uppladdningar har gjorts.

## Reproduktion

Kör från repo-roten (macOS med Xcode):

```sh
python3 scripts/test-oref-replay.py
python3 scripts/test-oref-integration-boundaries.py
python3 scripts/test-swift-oref.py --work-dir /private/tmp/trio-oref-native-tests --report /private/tmp/swift-replay.json
python3 scripts/test-swift-oref-extended.py --work-dir /private/tmp/trio-oref-native-tests --report /private/tmp/swift-extended.json
```

Swift-replay rapporterar både dosingContractsPassed och fullJSONParity. Det
första är true för testfallen; det andra är false. Det är inte samma sak som
att algoritmen generellt är likvärdig. P5 hålls öppen tills prognosavvikelserna
är granskade och telefonprotokollet samt prestandamätningen är genomförda.

Slutligt byggbevis: /private/tmp/trio-p345-build-final.log visar
TEST BUILD SUCCEEDED (exit 0). Xcode rapporterar befintliga varningar om
implicita testtarget-beroenden till pump-/CGM-moduler; de stoppar inte bygget.

Maskinläsbara resultat: swift-oref-p345-replay.json (inklusive exakta
källhashar) och swift-oref-p345-extended.json.
