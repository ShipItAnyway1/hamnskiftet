# Hamnillustration och kortbilder

Datum: 2026-10-26. Slutlig produktasset: `harbor-hero-v4.png`, 1536 × 1024. Används i mellanbanemenyn; bilden föreställer inte spelbar geometri.

Metod: inbyggt `image_gen.imagegen`, först generering och sedan bildredigering. Ingen extern Scenario-körning för dessa tillgångar. Filen kopierades till projektet.

## Ursprunglig prompt

Use case: stylized-concept. Asset type: production background illustration used inside the inter-level harbor / upgrade menu of an original mobile cargo-truck puzzle game. Create a polished premium casual-game 3D illustration, landscape 3:2 composition. A charming compact working harbor seen from a three-quarter isometric camera, with three beautiful chunky toy cargo trucks in distinct saturated colors: cobalt blue refrigerated box truck with white snowflake marking, emerald refrigerated truck, vivid coral-orange flatbed with two orange hazardous-material drums. A small substantial steel conveyor and gantry crane, colorful freight containers, timber bundles and a few pale stone piles visibly grounded on the quay, vivid turquoise water and small warm warehouse buildings. High art direction: smooth rounded bevels, excellent soft ambient contact shadows, clean materials, controlled detail, beautiful bright sunlight and subtle atmospheric depth. Rich navy/cobalt, electric aqua, warm golden yellow accents, emerald and coral. Clear large silhouettes readable as a 600px-wide in-game menu hero, feels like a carefully art-directed high-quality mobile game diorama. Fill the landscape composition attractively; no title, no lettering, no numbers, no interface panels, no buttons, no frame, no watermark, no collage. This is background game artwork, not a fake screenshot of an interface.

Ursprunglig fil: `exec-c15d8019-3b13-4d6b-aac0-efdbbe542c13.png`.

## Korrigering

Edit the supplied production harbor illustration. Make exactly one small semantic correction: replace the white snowflake emblem on the side of the GREEN refrigerated truck in the middle with a crisp simple WHITE THERMOMETER pictogram of the same size and visual weight. The BLUE freezer truck in the foreground must KEEP its white snowflake. Green means chilled food, blue means frozen food. Preserve all other artwork, original landscape 3:2 framing, all vehicles, colors, composition, sunlight, harbor, containers, water, crane and materials. No lettering, no UI, no additional marks.

Slutresultat: `exec-762b086c-7233-4f73-9d7a-f24551a4d545.png`. Kopierad till `harbor-hero-v4.png`.

## Kortbilder

`upgrade-fleet.png`, `upgrade-loader.png`, `upgrade-belt.png`, `upgrade-warehouse.png`, `upgrade-parking.png` och `upgrade-campaign.png` är transparenta 320 × 280-renderingar av egna Godot-modeller. Scenerna skapas i `ui_assets.gd`/`_miniature`. PNG-filerna sparar sex extra 3D-vyer vid menyöppning. Inget bildgenereringsverktyg användes för dessa sex filer.
