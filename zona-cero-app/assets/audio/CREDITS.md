# Zona Cero — créditos de audio

Todos los sonidos de `assets/audio/` fueron diseñados para Zona Cero a partir de grabaciones de dominio público (CC0) y síntesis propia (numpy/scipy, procesado con ffmpeg/LAME). No se usó material con licencias NC/ND ni sin licencia clara. CC0 no exige atribución; igual se acredita a cada autor por cortesía y trazabilidad.

Formato: MP3 44,1 kHz CBR (efectos mono 128 kbps, ambientes estéreo 160 kbps, encabezado LAME sin huecos). Efectos normalizados a ≈ −16 LUFS (interfaz −19 a −23 LUFS, más discretos) con pico real ≤ −1 dBTP; ambientes a −22 LUFS, loops sin costura de 28–32 s.

## Fuentes

| Clave | Obra | Autor | Licencia | Enlace |
|---|---|---|---|---|
| `creature` | 80 CC0 creature SFX | rubberduck | CC0 1.0 | https://opengameart.org/content/80-cc0-creature-sfx |
| `creature2` | 80 CC0 creture SFX #2 | rubberduck | CC0 1.0 | https://opengameart.org/content/80-cc0-creture-sfx-2 |
| `enemy` | Enemy sounds | AbnormalHumanBeing | CC0 1.0 | https://opengameart.org/content/enemy-sounds |
| `firearm` | The Free Firearm Sound Library (Prepared) | Free Firearm Sound Library team, posted by Bart K. | CC0 1.0 | https://opengameart.org/content/the-free-firearm-sound-library |
| `ghostmoans` | Ghost Monster Voice Moaning & Growling | qubodup | CC0 1.0 | https://opengameart.org/content/ghost-monster-voice-moaning-growling |
| `ghoul` | Hungry ghoul | darsycho | CC0 1.0 | https://opengameart.org/content/hungry-ghoul |
| `growls16` | 16 Monster Growls | StarNinjas | CC0 1.0 | https://opengameart.org/content/16-monster-growls |
| `gutter` | Rain in the Gutter Loop | ogrebane | CC0 1.0 | https://opengameart.org/content/rain-gutter-loop |
| `kenney_impact` | Impact Sounds | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| `kenney_rpg` | RPG Audio | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/rpg-audio |
| `kenney_ui` | UI Audio | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/ui-audio |
| `mud` | 25 CC0 mud sfx | rubberduck | CC0 1.0 | https://opengameart.org/content/25-cc0-mud-sfx |
| `rain2` | AMB Rain Loop 2 | Kresiek the Furry | CC0 1.0 | https://opengameart.org/content/amb-rain-loop-2 |
| `scream` | Horror scream1 | vinrax | CC0 1.0 | https://opengameart.org/content/horror-scream1 |
| `splash` | 40 CC0 water / splash / slime SFX | rubberduck | CC0 1.0 | https://opengameart.org/content/40-cc0-water-splash-slime-sfx |
| `synth` | Original synthesis (numpy/scipy) | Zona Cero audio | Original work, part of this project | — |

## Archivos

| Archivo | Duración | Tamaño | LUFS | Fuentes | Diseño |
|---|---|---|---|---|---|
| `bloater_burst.mp3` | 2.18 s | 35 KB | -15.1 | `ghoul`, `kenney_impact`, `mud`, `splash`, `synth` | Hinchado: gurgling moan (ghoul at 0.7×) and bubbling mud, then a wet burst (splash + mud splatters + saturated low boom) with dripping debris. |
| `brute_roar.mp3` | 3.09 s | 49 KB | -16.0 | `enemy`, `growls16`, `synth` | Bruto: two monster growls (StarNinjas) and an 'enemy' roar varispeeded to 0.62–0.7×, a saturated 46 Hz sub-growl following the voice envelope, chest resonance and hall. |
| `contact_ping.mp3` | 1.04 s | 17 KB | -19.0 | `synth` | Radar contact blip: two short FM-wobbled pings (1320 Hz then 990 Hz) with a soft click, short hall tail. |
| `defeat.mp3` | 4.31 s | 68 KB | -16.2 | `ghostmoans`, `synth` | Fallen: boom, a detuned saw drone gliding down 110→65 Hz with a minor-second cluster, slowing heartbeats and a distant low moan; filter closes into the hall. |
| `defend.mp3` | 0.61 s | 11 KB | -16.2 | `kenney_impact`, `kenney_rpg`, `synth` | Brace/block: cloth swish, heavy steel plate + wood impacts (Kenney) and a low thump. |
| `deliver.mp3` | 1.85 s | 30 KB | -16.1 | `kenney_impact`, `kenney_rpg`, `synth` | Crate set down at the node: wood plank + steel plate impacts (Kenney), latch, and a warm A-major swell (A2/C#3/E3) with soft hall. |
| `empty_click.mp3` | 0.18 s | 4 KB | -25.7 | `kenney_rpg`, `kenney_ui` | Dry-fire: two mechanical clicks (Kenney switch + metal click) high-passed, almost no room — the dreaded empty chamber. |
| `flee.mp3` | 1.51 s | 24 KB | -19.1 | `kenney_impact`, `synth` | Retreat: quick whoosh then six concrete footsteps (Kenney) accelerating away — each step quieter and darker (receding), ending in silence. |
| `headshot.mp3` | 0.53 s | 9 KB | -15.8 | `kenney_impact`, `kenney_rpg`, `splash`, `synth` | Headshot: sharp skull crack (layered synthetic crackle + chop), medium punch, big wet splatter (rubberduck splash) and a dull thump, short room. |
| `heal.mp3` | 1.63 s | 27 KB | -17.2 | `kenney_impact`, `kenney_rpg`, `synth` | Medkit: velcro/strap rustle (Kenney cloth belt), a glass vial tink, injector hiss and a warm rising tone (D4→A4) with chorus. |
| `heartbeat.mp3` | 0.54 s | 9 KB | -16.2 | `synth` | Single lub-dub: two saturated sub thumps (56→42 Hz, 50→38 Hz) with 140 Hz chest body and a soft valve click — audible on phone speakers. |
| `level_up.mp3` | 4.00 s | 64 KB | -16.2 | `kenney_impact`, `synth` | Cinematic rank-up: reversed-noise riser into a saturated boom, open D-major low chord with filter sweep, inharmonic bell partials and a 3 s hall. |
| `loot.mp3` | 1.19 s | 20 KB | -17.5 | `kenney_rpg`, `synth` | Rummage: cloth and leather handling (Kenney RPG), a metal latch clink and a subdued low 'reward' fifth (G2/D3) underneath. |
| `melee_impact.mp3` | 0.66 s | 11 KB | -15.2 | `kenney_impact`, `kenney_rpg`, `splash`, `synth` | Blunt hit: heavy punch + chop crunch (Kenney), synthetic bone crackle (sparse impulses band-passed 1.5–5 kHz), wet flesh splat and saturated sub. |
| `melee_swing.mp3` | 0.41 s | 7 KB | -17.0 | `synth` | Heavy whoosh: white noise through a state-variable band-pass sweeping 450→2300→650 Hz with a bell envelope, plus a low air layer for weight. |
| `pistol_shot.mp3` | 1.05 s | 18 KB | -15.8 | `firearm`, `synth` | .45 1911 at near distance (Free Firearm Library, 96 kHz) + the mid-distance take for urban slapback, saturated sub punch and transient crack; soft-clipped. |
| `player_hurt.mp3` | 1.16 s | 19 KB | -16.2 | `kenney_impact`, `synth` | Taking a hit: heavy body punch (Kenney), low 'whump' + sub, a muffled heartbeat thump and a 3.6 kHz tinnitus ring that fades out. |
| `runner_snarl.mp3` | 1.09 s | 18 KB | -15.0 | `creature2`, `enemy`, `growls16` | Corredor: fast snarl — monster growl (StarNinjas) at 1.12×, 'enemy' snarl and a rubberduck attack bark, hard drive with 1–3 kHz aggression peak. |
| `scan_charge.mp3` | 1.57 s | 26 KB | -17.0 | `kenney_ui`, `synth` | Capacitor charge-up: exponential sine/triangle sweep 180→1650 Hz with accelerating tremolo, noise riser and sub swell, ending in a lock click. |
| `scan_pulse.mp3` | 3.36 s | 53 KB | -16.1 | `synth` | Hero sonar pulse: saturated sub boom (72→36 Hz), inharmonic bell ping at 1150 Hz with outbound noise sweep, sonar echo taps and a 3 s dark hall. |
| `screamer_scream.mp3` | 3.09 s | 49 KB | -15.0 | `creature`, `scream` | Chillón: horror scream (vinrax) layered with a rubberduck scream at 1.25×, a 1.7 kHz ring-modulated inhuman edge, presence boost, drive and a 1.6 s hall. |
| `shotgun_shot.mp3` | 1.26 s | 21 KB | -15.0 | `firearm`, `synth` | 12-gauge Benelli Nova at near distance (Free Firearm Library) + Model 12 mid-distance tail, heavy saturated sub thump; soft-clipped and long tail. |
| `signal_radio.mp3` | 1.72 s | 28 KB | -17.0 | `synth` | Distress-signal pickup: squelch burst, tuning sweep, three Morse-like 1 kHz beeps, crackle and a closing squelch, all through a band-limited, driven 'radio' chain. |
| `ui_error.mp3` | 0.45 s | 8 KB | -17.0 | `kenney_ui`, `synth` | 'Denied' double buzz: two detuned square pulses (110/98 Hz) with drive, band-limited to 140–2600 Hz, plus a relay click. |
| `ui_open.mp3` | 0.99 s | 16 KB | -19.0 | `kenney_impact`, `kenney_ui`, `synth` | Holographic panel open: rising band-passed noise whoosh, low thud (Kenney impact) and a two-note shimmer (E6/B6) with chorus + short hall. |
| `ui_tab.mp3` | 0.32 s | 6 KB | -20.8 | `kenney_ui`, `synth` | Heavier switch click (Kenney) + short radio chirp (900→1350 Hz) through a band-limited 'terminal' filter, tiny room. |
| `ui_tap.mp3` | 0.09 s | 2 KB | -22.7 | `kenney_ui`, `synth` | Recorded mechanical switch (Kenney) trimmed to its transient + a dark 1.6 kHz terminal tick and a 190 Hz body thump. |
| `victory.mp3` | 3.85 s | 61 KB | -16.1 | `synth` | Survived: taiko-like low hit, then an A-minor swell that resolves to A major (Picardy third) with filter bloom, high bell partials and a dark hall. |
| `zombie_attack.mp3` | 1.11 s | 18 KB | -15.0 | `enemy`, `ghoul`, `kenney_impact`, `kenney_rpg`, `splash` | Lunge and bite: aggressive ghoul snarl at 0.9× + 'enemy' snarl layer, lunge whoosh (Kenney knife slice, low-passed), punch impact and wet squelch. |
| `zombie_death.mp3` | 2.67 s | 43 KB | -16.0 | `ghoul`, `kenney_impact`, `splash` | Death: falling-off ghoul moan at 0.8×, a pitched-down bubbling gurgle, then a body collapse (Kenney soft + punch impacts) in a dark room. |
| `zombie_groan.mp3` | 2.84 s | 45 KB | -16.0 | `ghostmoans`, `ghoul` | Caminante: long raspy ghoul moan (darsycho) varispeeded to 0.82× over a tonal ghost-moan layer (qubodup) at 0.7×, chest EQ, grit and a small dark room. |
| `zombie_hurt.mp3` | 0.86 s | 14 KB | -16.0 | `ghoul`, `kenney_impact`, `splash` | Short pained grunt (ghoul take at 0.85×) over a heavy body punch (Kenney) and a small wet splat. |
| `amb_city_rain.mp3` | 32.00 s | 626 KB | -22.0 | `rain2`, `synth` | Map: steady city rain (Kresiek, CC0) as the bed + low urban drone (filtered brown noise with slow movement), wind gusts, a distant two-tone siren and a far thunder roll, all placed away from the loop seam; 32 s seamless loop. |
| `amb_combat.mp3` | 28.00 s | 548 KB | -22.0 | `ghoul`, `rain2`, `synth` | Combat bed: dark detuned low drone with breathing filter, slow 64 BPM sub pulse, a high beating dissonant shimmer, muffled rain and distant reverberant ghoul moans; 28 s seamless loop. |
| `amb_shelter.mp3` | 30.00 s | 587 KB | -22.0 | `gutter`, `kenney_rpg`, `rain2`, `synth` | Node interior: rain on the roof (low-passed Kresiek rain) + gutter drips (ogrebane), a 50 Hz generator hum with wobble, faint radio-static murmurs and a timber creak (Kenney); 30 s seamless loop. |

## Detalle de tomas usadas

- `firearm`: `1911/A_42P.wav` (cerca) + `1911/A_34P.wav` (media distancia) → pistola; `Nova/O_21P.wav` + `Model 12/K_17P.wav` → escopeta.
- `ghoul`: `hungry-ghoul_0.ogg`, segmentado en 13 tomas; usadas las que empiezan en 5,4 s, 11,9 s, 18,4 s, 21,8 s, 24,9 s, 26,5 s y 32,0 s.
- `enemy`: `enemy_sounds.ogg`, tomas de 7,6 s, 9,1 s y 11,3 s.
- `growls16`: `monster.8`, `monster.11`, `monster.13`.
- `ghostmoans`: `qubodup-GhostMoan01.wav`, `qubodup-GhostMoan03.wav`.
- `scream`: `scream_horror1_0.mp3` (0,9–3,0 s). `creature`: `scream_01.ogg`. `creature2`: `attack_04.ogg`.
- `splash`: `slime_02/03/05/07/09/11/12`, `bubble_01/02`, `splash_05/09/11`. `mud`: `mud_04`, `mud_12`.
- `rain2`: `amb_rain2.flac` (tramos de 300 s, 520 s y 610 s). `gutter`: `rain-gutter-loop_0.mp3`.
- Kenney: `switch2`, `switch7` (UI Audio); `cloth1`, `clothBelt`, `handleSmallLeather`, `beltHandle1`, `metalLatch`, `metalClick`, `knifeSlice`, `chop`, `creak2` (RPG Audio); `impactPunch_heavy_000`, `impactPunch_medium_002`, `impactSoft_heavy_001`, `impactPlank_medium_000`, `impactPlate_heavy_002`, `impactWood_heavy_003`, `impactGlass_light_002`, `footstep_concrete_000–004` (Impact Sounds).

Los scripts de diseño (Python) que generan cada archivo de forma reproducible están fuera del repositorio; pedirlos al equipo de audio si hace falta regenerar o retocar un sonido.
