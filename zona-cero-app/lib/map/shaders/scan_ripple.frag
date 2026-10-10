// Onda de choque del escáner: refracción radial (lente anular) con leve
// aberración cromática alrededor del frente de onda. Se usa como
// ImageFilter.shader dentro de un BackdropFilter (solo con Impeller).
//
// Uniforms (en píxeles físicos, coordenadas de la textura de fondo):
//   uSize     — lo completa el motor con el tamaño de la textura.
//   uCenter   — centro de la onda (el jugador).
//   uRadius   — radio actual del frente de onda.
//   uWidth    — medio ancho de la franja distorsionada.
//   uStrength — desplazamiento máximo (px).
#version 460 core
#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;
uniform vec2 uCenter;
uniform float uRadius;
uniform float uWidth;
uniform float uStrength;
uniform sampler2D uTexture;

out vec4 fragColor;

vec4 sampleAt(vec2 px) {
  vec2 uv = clamp(px / uSize, vec2(0.0), vec2(1.0));
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uTexture, uv);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 d = p - uCenter;
  float dist = length(d);
  vec2 dir = dist > 0.001 ? d / dist : vec2(0.0, 0.0);
  float x = (dist - uRadius) / max(uWidth, 1.0);
  float env = exp(-x * x * 2.2);
  // Adentro del frente la imagen se estira hacia afuera y afuera se comprime:
  // un anillo de vidrio que avanza.
  float wave = -sin(clamp(x, -1.6, 1.6) * 1.9635) * env;
  vec2 off = dir * wave * uStrength;
  vec4 g = sampleAt(p - off);
  float r = sampleAt(p - off * 1.35).r;
  float b = sampleAt(p - off * 0.65).b;
  vec3 c = vec3(r, g.g, b);
  // Brillo frío sobre el frente de onda.
  c += vec3(0.32, 0.46, 0.56) * env * 0.16 * clamp(uStrength / 14.0, 0.0, 1.0);
  fragColor = vec4(min(c, vec3(g.a)), g.a);
}
