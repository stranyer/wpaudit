import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Tokens del sistema visual de ZONA CERO (v2, "campo de batalla").
///
/// Survival horror de calle: paneles de metal gastado, títulos condensados con
/// desgaste, rojo de emergencia para lo activo y lo hostil, ámbar para recursos y
/// azul acero para la red de refugios.
abstract final class Sutura {
  // Fondos y superficies
  static const void_ = Color(0xFF0A0B0C);
  static const map = Color(0xFF111314);
  static const surface1 = Color(0xE6121415); // panel translúcido sobre mapa/escena
  static const surface1Solid = Color(0xFF131516);
  static const surface2 = Color(0xFF1B1D1F);
  static const surface3 = Color(0xFF24272A);
  static const lineHair = Color(0xFF2C3033);
  static const lineStrong = Color(0xFF4B5054);
  static const lineBright = Color(0xFF7A7F82);

  // Texto (blanco cálido, como papel viejo bajo luz de sodio)
  static const textHi = Color(0xFFE9E6DF);
  static const textMid = Color(0xFFABA8A1);
  static const textLow = Color(0xFF6F6D68);
  static const textPaper = Color(0xFFD8D2C2);

  // Acentos
  /// Rojo de emergencia: estado activo, hostiles, advertencias.
  static const accent = Color(0xFFC8322B);
  static const accentDeep = Color(0xFF5A1612);

  /// Azul acero: red de relevo, refugios, resistencia, jugador.
  static const signal = Color(0xFF8DB4C9);
  static const signalDeep = Color(0xFF2E4654);

  /// Ámbar: recursos, botín, antena, entregas.
  static const amber = Color(0xFFD9A233);
  static const amberDeep = Color(0xFF4A3510);

  /// Verde refugio: nodos de la red, lugares seguros.
  static const refuge = Color(0xFF7FC46B);

  // Estados (ECG)
  static const fine = Color(0xFF7DCB76);
  static const caution = Color(0xFFE0B83E);
  static const caution2 = Color(0xFFE07A2E);
  static const danger = Color(0xFFDC3A32);
  static const toxin = Color(0xFF9C6CE0);
  static const offline = Color(0xFFFF2E46);

  // Rareza
  static const rarityCommon = Color(0xFF8E8C86);
  static const rarityUncommon = Color(0xFF7DCB76);
  static const rarityRare = Color(0xFF8DB4C9);
  static const rarityEpic = Color(0xFFA884E0);
  static const rarityLegendary = Color(0xFFD9A233);

  // Tipografías
  /// Títulos: condensada pesada (con textura de desgaste en [GrungeTitle]).
  static const fDisplay = 'Oswald';
  static const fUi = 'BarlowCondensed';
  static const fMono = 'ShareTechMono';
  static const fPaper = 'CourierPrime';
  static const fStamp = 'SpecialElite';
  static const fLogo = 'Oswald';

  /// Notas a mano (marcador sobre papel/pared).
  static const fHand = 'Handwritten';

  // Movimiento
  static const snap = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 240);
  static const heavy = Duration(milliseconds: 360);
  static const easeIn = Cubic(0.2, 0, 0, 1);
  static const easeOut = Cubic(0.4, 0, 1, 1);
  static const scanCurve = Cubic(0.16, 1, 0.3, 1);

  // Geometría
  static const chamfer = 7.0;
  static const bracket = 9.0;

  // Texturas (assets/art/tex)
  static const texPanel = 'assets/art/tex/panel.webp';
  static const texGrunge = 'assets/art/tex/grunge.webp';
  static const texMottle = 'assets/art/tex/mottle.webp';
}

/// Estilos de texto base.
abstract final class SuturaText {
  static const display = TextStyle(fontFamily: Sutura.fDisplay, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: Sutura.textHi, height: 1.0);
  static const title = TextStyle(fontFamily: Sutura.fDisplay, fontWeight: FontWeight.w600, fontSize: 18, letterSpacing: 2.2, color: Sutura.textHi);
  static const body = TextStyle(fontFamily: Sutura.fUi, fontWeight: FontWeight.w500, fontSize: 16, height: 1.3, color: Sutura.textHi);
  static const bodyMid = TextStyle(fontFamily: Sutura.fUi, fontWeight: FontWeight.w500, fontSize: 15, height: 1.32, color: Sutura.textMid);
  static const caption = TextStyle(fontFamily: Sutura.fUi, fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 1.0, color: Sutura.textMid);
  /// Rótulo en mayúsculas espaciadas ("OBJETIVO ACTUAL", "EQUIPO ACTUAL").
  static const label = TextStyle(fontFamily: Sutura.fUi, fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 3.0, color: Sutura.textMid, height: 1.1);
  static const button = TextStyle(fontFamily: Sutura.fUi, fontWeight: FontWeight.w700, fontSize: 17, letterSpacing: 2.6, color: Sutura.textHi);
  /// Números grandes ("07 / 32", "15:58").
  static const number = TextStyle(fontFamily: Sutura.fUi, fontWeight: FontWeight.w600, fontSize: 30, letterSpacing: 1.0, color: Sutura.textHi, height: 1.0);
  static const mono = TextStyle(fontFamily: Sutura.fMono, fontSize: 13, color: Sutura.textHi, letterSpacing: 0.6);
  static const micro = TextStyle(fontFamily: Sutura.fMono, fontSize: 9.5, color: Sutura.textLow, letterSpacing: 1.6);
  static const paper = TextStyle(fontFamily: Sutura.fPaper, fontSize: 15, height: 1.6, color: Sutura.textPaper);
  static const stamp = TextStyle(fontFamily: Sutura.fStamp, fontSize: 16, color: Sutura.danger, letterSpacing: 2);
  static const logo = TextStyle(fontFamily: Sutura.fLogo, fontWeight: FontWeight.w700, color: Sutura.textHi, letterSpacing: 3);
}

Color rarityColor(String rarityKey) => switch (rarityKey) {
      'uncommon' => Sutura.rarityUncommon,
      'rare' => Sutura.rarityRare,
      'epic' => Sutura.rarityEpic,
      'legendary' => Sutura.rarityLegendary,
      _ => Sutura.rarityCommon,
    };
