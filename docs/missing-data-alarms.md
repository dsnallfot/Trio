# Saknade glukosvärden och Loopar inte

Implementerat 2026-09-22. Två separata, valfria AlarmKit-bevakningar:

- Saknade glukosvärden: i GlucoseAlarmSettingsSection, standard 15/30 minuter.
- Loopar inte: i SystemAlarmSettingsSection direkt efter glukoslarmsektionerna,
  standard 20/40 minuter. Tiderna används även av befintliga vanliga loopnotiser.

Båda AlarmKit-valen börjar avstängda. Varje typ har eget ljud och två intervall:
10–60 minuter i steg om 5. Tiderna räknas från samma händelse, inte efter varandra.
De sorteras tidsmässigt; lika intervall ger endast ett larm. De valfria AlarmKit-larmen
kräver AlarmKit-behörighet och är oberoende av vanliga glukosnotiser, låg/hög-larmens
AlarmKit-reglage och deras snooze/global snooze. Vanliga loopnotiser behåller sina
befintliga behörighets-, ljud- och inställningsregler, och kan visas tillsammans med
AlarmKit-komplementet.

Glukosbevakningen använder senaste giltiga värdets tidsstämpel (positivt värde,
inte framtidsdaterat). Nyare timestamp flyttar båda larmen. Dubbletter, äldre backfill,
borttagning av senaste värdet eller enbart ett heartbeat flyttar inte bevakningen.
Loopbevakningen använder APSManager.lastLoopDate, som bara ändras vid lyckad loop.
Om ingen tidigare händelse finns räknas från första aktiveringen av bevakningen.

Tidslarmen schemaläggs som framtida fasta AlarmKit-tider hos iOS. Ingen körande
Swift-timer behövs vid larmtidpunkten. När nya data anländer måste Trio få exekvering
för att avboka/flytta alarmen; schemaläggnings-/avbokningsfel visas och loggas.
Tillstånd, händelsetider, UUID:n och kvittering sparas så omstart inte börjar om
räkningen eller spelar upp redan schemalagda och passerade larm igen.

Kvittera stoppar bara det specifika larmet. Den andra varningen ligger kvar om
avbrottet fortsätter. Ingen ytterligare automatisk repetition sker efter de två
varningarna. Vid aktivering/ändring när båda gränser redan passerats ges endast den
senare varningen omedelbart. Avstängning återkallar båda larmen för den typen.

## Verifiering

`bash scripts/test-glucose-alarms.sh` testar även tidsplaneringen i produktionskod:
ankare, backfill, radering, framtida tider, omstart, kvittering, ny episod, avstängning,
ljudändring, lika/omvända intervall, tom databas, konfigurationsmigrering och förfallna
tider. Simulatorbygge verifierar AlarmKit-/AppIntent-/SwiftUI-integrationen.

På fysisk testtelefon:

1. Välj 10/15 minuter, tillåt AlarmKit och testa först ljudleveransen med testknappen.
2. Stoppa glukosmottagningen i testmiljön. Lås telefonen och verifiera båda riktiga
   deadlines utan att öppna Trio. Testljudsknappen verifierar inte bevakningen.
3. Kvittera första larmet och verifiera att det andra ändå kommer.
4. Återuppta mottagningen innan andra tidsgränsen och verifiera att larmet flyttas.
5. Testa omstart under väntan, avstängning av bevakningen och ändrade intervall/ljud.
6. Testa utebliven lyckad loop separat, inklusive fortsatta heartbeats och misslyckade
   loopförsök. Glukoslarmet ska inte bero på om pump-/loopkommunikationen lyckas.
7. Kontrollera att vanliga loopnotiser använder de valda tiderna även med AlarmKit av.

Valet Visa mer inställningar sparas nu också; det befintliga fältet lästes tidigare
in men saknades i save(). Övriga användarjusteringar av glukoslarmens UI är bevarade.
