import json, os, sys
sys.argv = [sys.argv[0], sys.argv[1], sys.argv[2]]
ROOT, OUT = sys.argv[1], sys.argv[2]
sys.argv += []
import importlib.util
spec = importlib.util.spec_from_file_location("design", os.path.join(os.path.dirname(__file__), "design.py"))
# design.py reads argv at import: give it harmless values
sys.argv = ["design.py", ROOT, OUT, "__none__"]
d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)
rep = json.load(open(os.path.join(ROOT, "out", "report.json")))
S = d.SOURCES
lines = []
w = lines.append
w("# Zona Cero — créditos de audio")
w("")
w("Todos los sonidos de `assets/audio/` fueron diseñados para Zona Cero a partir de grabaciones de dominio público (CC0) y síntesis propia (numpy/scipy, procesado con ffmpeg/LAME). No se usó material con licencias NC/ND ni sin licencia clara. CC0 no exige atribución; igual se acredita a cada autor por cortesía y trazabilidad.")
w("")
w("Formato: MP3 44,1 kHz CBR (efectos mono 128 kbps, ambientes estéreo 160 kbps, encabezado LAME sin huecos). Efectos normalizados a ≈ −16 LUFS (interfaz −19 a −23 LUFS, más discretos) con pico real ≤ −1 dBTP; ambientes a −22 LUFS, loops sin costura de 28–32 s.")
w("")
w("## Fuentes")
w("")
w("| Clave | Obra | Autor | Licencia | Enlace |")
w("|---|---|---|---|---|")
used = sorted({k for r in rep.values() for k in r["sources"]})
for k in used:
    t, a, u, l = S[k]
    w(f"| `{k}` | {t} | {a} | {l} | {u} |")
w("")
w("## Archivos")
w("")
w("| Archivo | Duración | Tamaño | LUFS | Fuentes | Diseño |")
w("|---|---|---|---|---|---|")
for name in sorted(rep, key=lambda n: (rep[n]["kind"] != "sfx", n)):
    r = rep[name]
    size = os.path.getsize(os.path.join(OUT, name + ".mp3"))
    src = ", ".join(f"`{k}`" for k in r["sources"])
    note = r["note"].replace("|", "/").replace("\n", " ")
    w(f"| `{name}.mp3` | {r['dur']:.2f} s | {size/1024:.0f} KB | {r['lufs']:.1f} | {src} | {note} |")
w("")
w("## Detalle de tomas usadas")
w("")
w("- `firearm`: `1911/A_42P.wav` (cerca) + `1911/A_34P.wav` (media distancia) → pistola; `Nova/O_21P.wav` + `Model 12/K_17P.wav` → escopeta.")
w("- `ghoul`: `hungry-ghoul_0.ogg`, segmentado en 13 tomas; usadas las que empiezan en 5,4 s, 11,9 s, 18,4 s, 21,8 s, 24,9 s, 26,5 s y 32,0 s.")
w("- `enemy`: `enemy_sounds.ogg`, tomas de 7,6 s, 9,1 s y 11,3 s.")
w("- `growls16`: `monster.8`, `monster.11`, `monster.13`.")
w("- `ghostmoans`: `qubodup-GhostMoan01.wav`, `qubodup-GhostMoan03.wav`.")
w("- `scream`: `scream_horror1_0.mp3` (0,9–3,0 s). `creature`: `scream_01.ogg`. `creature2`: `attack_04.ogg`.")
w("- `splash`: `slime_02/03/05/07/09/11/12`, `bubble_01/02`, `splash_05/09/11`. `mud`: `mud_04`, `mud_12`.")
w("- `rain2`: `amb_rain2.flac` (tramos de 300 s, 520 s y 610 s). `gutter`: `rain-gutter-loop_0.mp3`.")
w("- Kenney: `switch2`, `switch7` (UI Audio); `cloth1`, `clothBelt`, `handleSmallLeather`, `beltHandle1`, `metalLatch`, `metalClick`, `knifeSlice`, `chop`, `creak2` (RPG Audio); `impactPunch_heavy_000`, `impactPunch_medium_002`, `impactSoft_heavy_001`, `impactPlank_medium_000`, `impactPlate_heavy_002`, `impactWood_heavy_003`, `impactGlass_light_002`, `footstep_concrete_000–004` (Impact Sounds).")
w("")
w("Los scripts de diseño (Python) que generan cada archivo de forma reproducible están fuera del repositorio; pedirlos al equipo de audio si hace falta regenerar o retocar un sonido.")
open(os.path.join(OUT, "CREDITS.md"), "w").write("\n".join(lines) + "\n")
print("ok", len(rep))
