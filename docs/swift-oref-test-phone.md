# Testtelefon: Swift Oref

Status 2026-10-29: integrationen kan byggas för testtelefon. Full algoritmparitet
är inte godkänd: kvarvarande prognosavvikelser finns i swift-oref-p345-replay.json.
APNS, Shortcuts, nätverksuppladdning, omstart och UI behöver köras på telefonen.

## Bygg och motorval

Öppna Trio.xcworkspace i Trio-ivar-dev-os och bygg med ordinarie Trio-schema
för den dedikerade testtelefonen, med din vanliga signering. TrioOrefTests är
ett separat schema för tester. Inget har installerats eller pushats av agenten.

Extra inställningar → Algoritmmotor → Använd Swift-algoritmen.
Reglaget är av som standard, även med äldre settings-JSON. En pågående
beräkning behåller sin motor; byte gäller nästa beräkning. Under reglaget
visas motorn, tiden och total tidsåtgång för senaste lyckade beräkningen.

## Protokoll

Utför samma kontroll med JavaScript och Swift. Använd testtelefonens testmiljö
för pump och Nightscout så att provkommandon inte träffar den skarpa telefonen.

- [ ] Starta med äldre inställningar: JavaScript är valt och en normal körning lyckas.
- [ ] Växla JS → Swift → JS. Verifiera faktiskt använd motor efter varje körning.
- [ ] Avsluta/starta appen i båda lägena; motorvalet består och cache återanvänds
      bara för samma motor. Prova även byte följt av omedelbar omstart.
- [ ] Kör byte under en pågående beräkning och ett samtidigt shortcut-anrop.
      Kontrollera ordning, ett resultat per anrop och att appen inte låser sig.
- [ ] APNS: måltid, override, temp target, avbryt/utgångstid och upprepat kommando.
      Kontrollera även kvittens och befintlig dubbletthantering.
- [ ] Shortcuts: befintliga måltids-/bolusflöden, behörighet, maxbolusgränser,
      avbrutet anrop och simulering för bolusförslag.
- [ ] Verifiera lokalt bolusförslag, felkod/text och IOB/COB efter simulering.
- [ ] Nightscout: suggested/enacted, timestamps/received, IOB/COB, prognoser,
      TDD, insulinuppdelning och manuella bolusfält. Kontrollera även reason;
      Swift använder delvis andra diagnostiktexter.
- [ ] Nätverk av/på: köade uppladdningar kommer fram utan nya dubbletter.
- [ ] Kort pumphistorik, saknad CGM och för gamla CGM-värden ger väntat stopp/
      returresultat; inget tyst byte till annan motor sker vid Swift-fel.
- [ ] Följ även längre drift, dygnsbyte och cacheförnyelse under flera dygn.

## Prestanda

Appen sparar de senaste 576 lyckade, ordinarie beräkningarnas motor, timestamp
och tidsåtgång i monitor/oref-engine-timing.json. Simuleringar ingår inte.
Tiden omfattar underlagsläsning, profil, eventuell autosensförnyelse,
beräkningskedjan och lagring. Den är inte ett isolerat CPU-mått för workern.

Exportera filen från testappen och kör:

```sh
python3 scripts/summarize-oref-timings.py /sökväg/oref-engine-timing.json
```

Jämför flera likvärdiga perioder i samma byggkonfiguration och på samma telefon.
Notera laddning, skärmtid, nätverk, loggning och om första körningen efter
motorbyte bygger om cache. Mät CPU/minne separat med Xcode Instruments och
batteriförbrukning över längre perioder. Ingen telefonprestanda eller
batterivinst har ännu uppmätts i denna branch.
