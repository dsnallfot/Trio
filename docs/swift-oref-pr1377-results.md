# PR #1377: lokal port och verifiering

Implementerad 2026-10-31 på ivar-dev-os, med lokal referens vid HEAD badad7a10.
Källa: https://github.com/nightscout/Trio/pull/1377, PR-head 222e02b04c6a6b0a795ce616d44aa03ee9c4e4ed.

## Omfattning och lokala anpassningar

1. Frös den befintliga Swift-motorns utdata före ändringarna. Referenserna är lokala resultat, inte officiella Trios förväntade resultat.
2. Porterade återanvändning av pumphistorik, förberedda basal-/ISF-scheman, förberedd IOB-indata, binär sökning i sorterad historik och billigare insulinkurvberäkning. Autosens återanvänder samma behandlingshistorik för 8 och 24 timmar i vår befintliga Swift-brygga.
3. Porterade wall-clock/tidszonscache separat och verifierade mot Calendar, inklusive sommartidsövergångar, byte av tidszon och historiska datum i omvänd ordning.

Behöll lokal Decimal/JavaScript-avrundning, SwiftOrefAutosens, exercise-mode/temporära mål, historiknormalisering och alla anpassningar i doseringslagret. Osorterad indata till den äldre IOB-funktionen använder dess ursprungliga beräkningsväg: upstreams binära sökning förutsätter sortering. Den förberedda beräkningskedjan använder den optimerade vägen.

DosingEngine, DetermineBasalGenerator, svenska reason-strängar inklusive TDD/AF/SMB-ordning samt Nightscout-, APNS- och shortcuts-kod ändrades inte av denna port. Befintliga parallella användarändringar i andra filer lämnades orörda. JavaScript-reserven och motorvalet behålls. Inga nya periodiska mätningar eller diagnostikjobb har lagts till i appen; prestandatesterna körs bara på uttrycklig begäran.

## Verifiering

- 151/151 jämförelser av lokala Swift-resultat före/efter passerar.
- 66/66 extra jämförelser passerar: overrides, mål, SMB-scheman, begränsad historik, exercise-mode och lokal SMB-lågtemp. SMB-lågtempkontrollen ingår också i huvudserien.
- 14 golden-scenarier med totalt 70 modulresultat passerar. Kompletta reason-strängar ingår. Endast slumpmässigt determination-ID normaliseras; JSON-nyckelordning saknar betydelse.
- Referens-/tidszonssviten: 5 tester i 3 sviter passerar, varav golden-testet har 14 parameterfall. Offset-cachen provas med Stockholm, New York, Kolkata, Lord Howe och UTC.
- Ordinarie native-testsvit: 216 tester, samma 31 befintliga felande kontroller före och efter. Dessa förväntar äldre engelska reason-texter; inga nya fel kvarstår. Sviten är därför **inte helt grön**.
- Swift-kärnan byggd i release med teståtkomst aktiverad. Ingen fullständig iOS-appbyggning eller installation utförd i denna omgång. Appens byggfas kör formattering av hela repot, vilket skulle kunna påverka pågående manuella ändringar.

Detta visar likhet med vår tidigare Swift-motor för dessa testfall, inte generell likhet med JavaScript eller bevis för alla möjliga patientdata. De externa APNS-/Nightscout-flödena har inte körts end-to-end här.

## Prestanda

Native macOS, release, samma syntetiska täta 24-timmarshistorik, uppvärmning och 10 mätningar per test. Före- och eftermätning kördes sekventiellt utan parallella testbyggen. Medianer:

| Beräkning | Före | Efter | Minskad tid |
| --- | ---: | ---: | ---: |
| IOB | 6,03 ms | 2,12 ms | 65 % |
| Autosens, 288 värden | 10,29 ms | 3,61 ms | 65 % |
| Meal | 5,69 ms | 3,74 ms | 34 % |
| Testets hela pipeline | 37,66 ms | 18,79 ms | 50 % |

Pipeline-mätningen avser testharnessens algoritmkedja, inte hela appens loop med lagring, Bluetooth och uppladdningar. Det är en kort mikrobenchmark på Mac; procentsatserna är inte ett löfte om samma telefon- eller batterivinst. Råloggar finns bredvid denna fil.

## Reproducera kontrollerna

Från repots rot, skapa en separat native-testvärd (skriv aldrig över en tidigare fryst referensvärd):

```sh
python3 scripts/oref-native/setup.py "$PWD" /private/tmp/trio-1377-check
swift build -c release -Xswiftc -enable-testing --package-path /private/tmp/trio-1377-check --product OrefReplay
python3 scripts/test-swift-oref-performance-parity.py --binary /private/tmp/trio-1377-check/.build/release/OrefReplay --baseline docs/swift-oref-pr1377-baseline.json
python3 scripts/test-swift-oref-performance-parity.py --binary /private/tmp/trio-1377-check/.build/release/OrefReplay --baseline docs/swift-oref-pr1377-extended-baseline.json
TZ=Europe/Berlin swift test -c release -Xswiftc -enable-testing --package-path /private/tmp/trio-1377-check --filter 'ParityGoldenTests|WallClockParityTests|ParityEnvironmentTests'
TZ=UTC swift test -c release -Xswiftc -enable-testing --package-path /private/tmp/trio-1377-check --skip 'Parity|WallClock'
TZ=Europe/Berlin TRIO_RUN_PERF=1 swift test -c release -Xswiftc -enable-testing --package-path /private/tmp/trio-1377-check --filter ParityPerformanceTests
```

Kör golden- och ordinarie tester i separata processer med angivna tidszoner. Att bara sätta NSTimeZone.default i testharnessen räcker inte för TimeZone.current i native-värden. SwiftPM kan varna för odeklarerade golden-resurser; dessa tester läser referenserna via källfilens sökväg och har verifierats fungera så.

Kvar på testtelefon: bygg appen, följ reason-parsning och oref2/Nightscout, jämför oref-engine-timing över flera körningar med liknande historikmängd och fortsätt bakgrundstestet. Telefon- och batterimätning återstår.
