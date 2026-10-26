# V7-granskning · 26 oktober 2026

Spelbar lokal Mac-version med fast godsorder, verkliga förluster, bommar och helikopterräddning. Normalspel och testläge har skilda verktyg. Alla hjälp- och uppgraderingspriser är spelguld. iOS/Android-export, tester på telefon och mänsklig bedömning av pusselglädje återstår.

## Vad som faktiskt har kontrollerats

| Kontroll | Resultat och bevis |
|---|---|
| Lösbarhet och uppgraderingar | 50 fulla banor och 50 uppvärmda starter; 299 körningar, 850 varor. Samtliga utan helikopter. Grundkapacitet, maxkapacitet, mellannivåer och blandade uppgraderingar ingår. |
| Sparning | Nio ConfigFile-rundresor. Delorder, pågående transporter, tomma reservationer, 180°-riktning, bomräknare och förbrukad räddning behålls. Felaktiga ögonblicksbilder avvisas. |
| Spelkontrollen | 71 kontroller av faktisk main: normalt startflöde, Heli 0/50, ångra 100, återställning efter sparfel, laddad profil, normal/testläge, kajmätare, förlust/omstart och helikopterval efter blockerad utfart. |
| Native bossbana 5 | 16/16 pallar levererade på åtta körningar. Tio överflödiga bilar kvar. Ingen räddning. 62 guld i varor + 100 i bonus. |
| Native större bana 8 | 24/24 pallar levererade på nio körningar. 21 bilar kvar. Ingen räddning. 82 guld i varor + 130 i bonus. |
| Native felval | Tre tillåtna kylbilar kan skapa ett bestående gods-/kajstopp. Riktig förlustpanel visas. Gratis omstart återställer försöket. |
| Återhämtning från blockerad utfart | Förlust → val av helikopter över flera bildrutor → avbrutet val → ny förlust → verklig helikoptervändning → öppen vanlig utfart. Förlustpanelen avbryter inte längre valet. |
| Räddning och kostnader | Första flygningen gratis, andra kostar 50; följande ångra kostar 100. Gratisräddningen återkommer inte genom ångra. Flygning, lyft, vändning och landning renderas i native Godot. |
| Orderbelöningar | 50 kontroller av samma order över omstart/ångra, andra lastbils-ID, olika kapaciteter, sex typer, decimalavrundning och disk. Hamnens prognos räknar ordern, inte alla extra bilar. |
| Ljud och musik | 22 runtime-strömmar, 18 samtidiga provhändelser, 76,8 s musik och bossrytm, separata reglage och städning. Ingen automatisk bedömning av musikalisk smak. |
| Visuell kontroll | Normalspel saknar bottenmeny. Tomma kajer saknar nummer. Riktig bil följs på asfalt. Priser, bomräknare, order och seger är läsbara i Mac-bilder. |

Fullständiga nya testloggar sparas som GitHub Actions-artifakter. De ursprungliga lokala native-loggarna ingår inte i repot. Vissa headless-körningar rapporterade Godots macOS-varning vid hämtning av CA-certifikat; respektive tests slutresultat passerade. Native-körningarna använder lokal grafik och saknar motsvarande fel. Historiska tester är inte omdöpta till V7-bevis.

## Bilder från den körda versionen

- [Normalspel utan verktygsrad](01-normalspel-utan-bottenmeny.png).
- [Order och återstående godstyper](01-gods-fast-order.png).
- [Paus med priser och testläge](02-paus-priser.png).
- [Verktygsrad endast i testläge](03-endast-testverktyg.png).
- [Helikoptern lyfter en riktig lastbil](04-helikopter-lyft.png).
- [Faktisk förlust](06-verklig-forlust.png) och [gratis omstart](07-gratis-omstart.png).
- [Körning på asfalt](05-korning-pa-asfalt.png).
- [Dyrare uppgraderingar och orderbaserad intäktsprognos](09-dyrare-uppgraderingar.png).
- [Bossorder klar utan räddning](05-order-klar-utan-heli.png).
- [Större order klar utan räddning](08-order-klar-utan-heli.png).

QA är isolerad från spelarens profil. Därför syns 500 guld vid teststart. Större testfart används bara under automatisk genomspelning. Bilder i `mobile390/` är förminskade Mac-bilder, inte en telefonbyggnad.

## Sparning vid versionsbytet

En lokal migreringskontroll verifierade att saldo, uppgraderingar, avklarade banor, historiska belöningskvittenser och ljudinställningar behålls. Spelarprofiler och säkerhetskopior ingår inte i repot eller webbexporten.

## Varför pusslet kan bli knepigare

Tidigare räckte det ofta att få ut bilar i möjlig ordning. Nu måste man samtidigt planera vilken last som behövs, vilket gods som kan komma in på det ändliga bandet och vilka nödvändiga bilar som blir tillgängliga efter en avgång. En överflödig bil är ett möjligt felval, inte en gratis platsrensning. Bommen kräver verkliga färdiga avgångar. På bossbanan måste samma samband hanteras med mindre plats på bandet.

Detta skapar testbara beslutsproblem men är ingen garanti för att spelet upplevs roligt. Vid provspelning bör man särskilt bedöma om stoppet går att förstå, om man vill försöka igen och om det finns flera intressanta val. Orderinnehåll och kvarvarande typer är synlig information; spelet markerar inte rätt drag.

## Fler hinder och bossar att prova senare — ännu inte byggda

| Förslag | Den nya kluringen | Tydlig regel som spelaren kan läsa |
|---|---|---|
| Materiallåst bom | En specifik leverans, exempelvis schakt, måste bli klar för att öppna en viktig utfart. Två lämpliga lastbilar konkurrerar om samma kaj. | Materialmärke på bommen och en synlig leveransräknare. |
| Enkelriktad vändskiva | En platta ändrar körningens riktning efter varje passerad bil. Ordningen påverkar vilken bil som kan lämna depån härnäst. | Pil på plattan; nästa riktning syns före draget. |
| Viktbegränsad bro | En stor uppgraderad bil tar mer gods men behöver en längre utfart. En liten bil kan först öppna vägen för den stora. | Fordonslängd och tillåten brostorlek visas fysiskt. |
| Gemensam ADR-säkerhetszon | En farlig last reserverar en angränsande kaj under lastningen. Bäst fyllnadsgrad är inte alltid bästa ordning. | Orange markerat område visar exakt vilken kaj som tillfälligt blockeras. |
| Växlande matare | Två synliga godsköer delar en infart; spelaren växlar matare som ett eget drag. Frihet att skapa kombinationer, risk att fylla bandet fel. | Förhandsvisning av de närmaste fysiska pallarna från båda håll. |
| Boss: stormskiftet | En kaj stängs efter två avgångar och en annan öppnar. Man behöver göra rätt förberedelser innan skiftet. | Nedräkning i avgångar; ingen osynlig slump eller realtidspress. |
| Boss: dubbel beställning | Två order delar band och begränsade kajer. Första ordern öppnar en genväg som behövs för den andra. | Två tydliga orderytor och en fysisk, låst genväg. |

Prioritering för nästa prov: **materiallåst bom och växlande matare**. De tillför nya planeringsbeslut med liten mängd extra UI. Viktbron bör provas senare eftersom fordonsuppgraderingar annars kan kännas som en bestraffning. Varje variant behöver en verifierad lösning utan betald hjälp.
