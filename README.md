# Hamnskiftet V7 — order, risk och räddning

Lokal Mac-prototyp av ett lastbilspussel i en animerad hamn. [Spela i mobilen eller datorns webbläsare](https://shipitanyway1.github.io/hamnskiftet/). Starta Mac-versionen med `Spela.command`. Native-export till iOS/Android och tester på fysiska telefoner återstår. Alla priser nedan gäller intjänat spelguld; riktiga betalningar och annonser är inte implementerade.

## Målet och de verkliga felvalen

Leverera **den fasta godsordern**, inte hela fordonsparken. Kampanjen har 10, 12, 14, 16, 18, 22, 26 och 30 lastbilar. Samma banor har 8, 10, 12, 14, 16, 18, 20 och 24 fysiska varor. Senare banor stannar vid högst 30 lastbilar och 24 varor. Antalet lastbilar är alltså större än antalet varor, och bilar får stå kvar när ordern är klar.

Varje skickad bil reserverar omedelbart en av dina tre kajer. Flera bilar kan skickas direkt efter varandra och kör samtidigt med fysisk väjning. Bilen reserverar högst sin kapacitet av återstående, ännu inte reserverat gods av rätt typ. En liten restorder ger en delvis lastad avgång. En överflödig bil kan också skickas: utan godsorder tar den upp kajen och lämnar den inte automatiskt.

Bandet tar högst **8 pallar**, eller **6 på bossbanor**. Gods som inte kan lastas cirkulerar vidare; nästa varor väntar i vänster/höger matare tills det finns plats. Fel kajval kan låsa tillförseln. När inga automatiska transporter eller lastningar kan lösa stoppet visas en faktisk förlust med gratis omstart. Även en bevisat blockerad utfart kan ge förlust. Ingen tidsgräns eller automatisk ledtråd finns.

Lagerföljden och placeringen varierar mellan banorna men är bestämda för ett visst försök. Varje genererad bana kontrolleras mot en lösning utan helikopter. Det är en kontroll av lösbarhet; svårighetsgrad och spelglädje behöver fortfarande bedömas genom provspelning.

## Bommar och bossbanor

Från bana 3 finns fasta containrar och en bom som blockerar en riktig utfart. Bommen öppnas efter **två färdiga avgångar**, från bana 8 efter tre. Räknaren visar till exempel `0 / 2`; väntan i sig öppnar inte bommen. Armen lyfts synligt och körande bilar väntar på att den har gått upp.

Nödvändiga lastbilar har blockeringskedjor: en bil behöver lämna plats åt nästa. Från bana 5 ligger nödvändiga bränslebilar bakom bommen, så du måste skapa fungerande leveranser först. Var femte bana är en bossbana med snävare bandkapacitet. Detta är den första bossvarianten, inte en färdig serie av olika bossmekaniker.

## Helikopter, ångra och omstart

**Heli** i överkanten aktiverar val av en parkerad bil. Helikoptern flyger in, greppar bilen, lyfter den och vänder körriktningen 180 grader på samma ruta. Den första vändningen i ett försök är gratis, därefter kostar varje vända **50 guld**. Den kan inte vända bilar som redan har skickats eller frigöra en kaj som är upptagen av en felvald bil.

**Paus → Ångra** kostar **100 guld**. Det återställer föregående drag och godsflöde men återbetalar inte redan använda hjälpköp. Ångra ger inte tillbaka en förbrukad gratis helikopter. Brist på pengar eller ett misslyckat sparförsök ska inte konsumera drag eller guld. **Börja om är alltid gratis** och ger ett nytt försök med en gratis helikoptervändning. Det går att vinna utan att köpa hjälp.

Godsbelöningar och skiftbonus kvitteras permanent. Ångra och omstart ska inte betala samma ordergods igen, även när en annan lastbil används nästa gång.

## Läsbar värld och normalspel

Förstorade vyer för lastning och depå delar samma riktiga 3D-värld. En tredje smal vy följer de faktiska lastbilarna på asfalten. Den större depåytan finns kvar. Tomma eller ännu inte nådda kajer visar inga svävande lastnummer; bara bilen som faktiskt lastar får en lastmätare.

Färg, form och stor symbol följer varje godstyp på både bil och vara: grön kyl/termometer, blå frys/snöflinga, gul schakt/stenar, orange ADR/faromärke, lila timmer/stockringar och rosa bränsle/droppe. Fysiska modeller och tydliga takpilar kompletterar märkningen. **Gods** visar återstående varor per typ och deras myntvärde.

Godset åker på ett sammanhängande band med räcken och matarspår. Nya pallar glider in från sidan. Transportplattorna är neutrala och visas vid faktiskt gods; tomma ramar ska inte se ut som ytterligare lagerkapacitet. Kranar, bakdörr/rullift, schaktlastning, stocklyft och bränsleslangar används under lastningen.

Bottenmenyn och gratis 2×-hastighet är dolda i normalspel. De finns under **Paus → Testläge**, tillsammans med gratis ångra, vybyte och äldre testverktyg. När testläget stängs återgår hastigheten till 1×. Det behövs inga testverktyg för att klara kampanjbanorna.

## Uppgraderingar mellan banorna

Varje lastbilstyp uppgraderas separat från **3 → 4 → 5 → 6 varor**. Större kapacitet lägger **inte till fler varor i ordern**: fler varor kan samlas i samma bil, vilket kan spara en kaj och en körning. Om restordern redan är mindre än bilens kapacitet ger just den storleksökningen ingen ytterligare besparing där. Kapacitet 5–6 använder en längre lastbil, så parkeringen påverkas också.

| Uppgradering | Priser i spelguld | Effekt |
|---|---|---|
| Kyl, frys, schakt eller timmer, per typ | 200 / 450 / 900 | Kapacitet 4 / 5 / 6 |
| ADR eller bränsle, per typ | 230 / 500 / 1 000 | Kapacitet 4 / 5 / 6 |
| Snabbare lastning | 180 / 360 / 700 / 1 100 / 1 600 / 2 200 | +12 % per nivå |
| Snabbare varuband | 220 / 440 / 800 / 1 250 / 1 800 / 2 500 | +8 % per nivå |
| Finare varor | 260 / 520 / 900 / 1 500 / 2 300 | +25 % varuvärde per nivå |
| Extra kajer | 650 / 1 400 | 3 → 4 → 5 samtidiga kajer |

Köp gäller nästa bana. ADR introduceras på bana 3, bränsle på bana 5. Bana 1 börjar med schakt och kyl; bana 2 lägger till timmer och frys. Godsens grundvärden är schakt 1, timmer 2, kyl 3, frys 4, ADR 6 och bränsle 8 guld. Skiftbonusen är 50 + 10 × bannumret. Första grundbanans order är värd 16 guld och bonusen är 60: totalt 76 vid första genomspelningen. Alla priser och formler finns i `progression.gd`.

## Ljud, musik och sparning

En ny egen **76,8 sekunders musikloop** kombinerar melodi, marimba, bas och rytm; bossbanan lägger till ett synkroniserat rytmspår. Separata ljud finns för sex lasttyper, matare, bom, motorer, bromsar, helikopter, förlust och köp. Ljud kan överlappa; musiken dämpas vid effekter och motor/rotor tystnar i paus. **Paus → Musik/Effekter** styr grupperna separat och inställningarna sparas.

[20 sekunders musikprov](assets/audio/v7/music_preview_20s.wav) och [mixprov](assets/audio/v7/mix_preview_20s.wav) är lokalt skapade original. Generator och proveniens finns i `tools/generate-truck-audio-v7.py` och `assets/audio/v7/manifest.json`. Ljudfiler, looplängder, volymgränser och uppspelning är tekniskt kontrollerade; provlyssna själv för att bedöma musiksmak och ljudbild.

Saldo, uppgraderingar, belöningskvittenser och aktiv V7-order sparas lokalt och atomiskt. Animerad trafik återupptas vid sina reserverade kajer. Ångrahistoriken sparas inte över appstart. En äldre V5/V6-order kan inte återställas under de nya reglerna och börjar om; permanent saldo, köp och avklarade banor behålls.

## Provspela och verifiera

Klicka på bil för att skicka, **Heli → bil** för att vända. **Mellanslag/pausknapp** pausar, **R** börjar om och **Z** gör betald ångra. **Gods** förklarar ordern. Skroll zoomar depån; höger musknapp drar när vyn är zoomad. Testläge väljs i pausmenyn.

[Genomförd granskning, bilder och fler hinderidéer](qa/v7/GRANSKNING.md).

Aktuella V7-tester körs från workspace-roten med exempelvis:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_v7_rules.gd
```

- `test_v7_rules.gd`: fasta order, uppgraderingar, lösbarhet, blockeringskedjor, bommar, verkliga felval och bossar.
- `test_v7_save.gd`: nio verkliga ConfigFile-sparningar med delorder, rotation, bommar och felaktiga data.
- `test_v7_controller.gd`: riktig spelkontroll, gratis/betald räddning, betald ångra, sparfel, förlust/omstart och testlägets avgränsning.
- `test_v7_rewards.gd`: orderbelöningar över omstart, ångra och byte av lastbil.
- `test_v7_view_ui.gd`: priser, hjälpknappar, tomma kajer, vägkameran och fysisk bomfrigång.
- `test_audio.gd` och `test_rescue.gd`: ljud, helikopter, paus och städning.

`-- --v7=01` till `-- --v7=05` kör isolerade native-scenarier: menyer, räddning/ångra, faktisk förlust och fulla order på bana 5 och 8. QA-saldot 500 används bara där. `-- --play --handoff` öppnar normalt sparat spel, tar en skärmbild och lämnar spelet öppet.

Äldre V4/V5/V6-tester finns kvar som historik. De ersätter inte V7-kontrollerna. Automatiska kontroller och Mac-bilder bevisar inte mänsklig spelglädje eller telefonprestanda.

## Webbversion och GitHub Actions

Öppna **https://shipitanyway1.github.io/hamnskiftet/** direkt i Safari eller Chrome. Välj **Spela**, sedan bana 1. Webbversionen använder samma spelregler och illustrationer som Mac-versionen. Den första starten laddar ned spelmotorn och godset. En uppdaterad webbläsare med WebGL 2 och WebAssembly behövs.

Mobilen har egen lokal sparning i webbläsaren. Mac-sparfilen överförs inte automatiskt. Ljudet aktiveras efter ett tryck i spelet. Webbversionen använder en tråd och kräver inga särskilda isoleringsheaders eller installation från en appbutik.

Varje push till `main` kör Actions: isolerad import och åtta aktuella tester, en riktig Godot-webbexport, paketeringskontroll och ett mobilanpassat webbläsartest. Bara ett godkänt bygge publiceras till GitHub Pages. Pull requests kör kontrollerna utan att publiceras. Versioner och officiella Actions är låsta; `build-info.json` vid spellänken anger exakt publicerad commit och filhashar.

Lokal kontroll och webbexport från repots rot:

```sh
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tools/run_ci.py --log-dir ci-results
python3 tools/fetch_web_template.py
mkdir -p build/web
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release Web build/web/index.html
python3 tools/check_web_build.py
python3 -m http.server 8765 --directory build/web
```

Exportmallen hämtas från den officiella Godot-releasen och kontrolleras mot en låst SHA-256. Lokala profiler, spelbackup, byggkataloger och QA-fixturer filtreras bort från exporten. Nya ljud och illustrationer laddas genom Godots importerade resurser i exporten.

## Tillgångar

Värld, fordon, gods och animationer skapas lokalt i Godot. Sex fordonskort har renderats från de egna modellerna. Menyn återanvänder [V4-illustrationen och dokumenterade promptar](assets/art/PROVENANCE.md). Den här versionens nya modeller, animationer och ljud kräver inga externa API-köp.
