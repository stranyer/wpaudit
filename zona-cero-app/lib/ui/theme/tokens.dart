import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Tokens del sistema visual SUTURA (terminal médica de campo VITA-7).
/// Fusión de la frialdad clínica de una survival horror y la holografía de red.
abstract final class Sutura {
  // Fondos y superficies
  static const void_ = Color(0xFF05070A);
  static const map = Color(0xFF0A0E11);
  static const surface1 = Color(0xE010161A); // 88 % sobre el mapa
  static const surface1Solid = Color(0xFF10161A);
  static const surface2 = Color(0xFF172026);
  static const lineHair = Color(0xFF23323A);
  static const lineStrong = Color(0xFF47616C);

  // Texto
  static const textHi = Color(0xFFEAF4F5);
  static const textMid = Color(0xFFA4B8BD);
  static const textLow = Color(0xFF62777E);
  static const textPaper = Color(0xFFD8D2C2);

  // Acentos
  static const signal = Color(0xFF6ADBEA); // red, nodos, escáner, foco
  static const signalDeep = Color(0xFF0B67A6); // selección, chips de pulso
  static const amber = Color(0xFFE2B53E); // "ámbar sutura": recompensas, refugios

  // Estados (ECG)
  static const fine = Color(0xFF74C044);
  static const caution = Color(0xFFE6C13A);
  static const caution2 = Color(0xFFE8792B);
  static const danger = Color(0xFFEE3B45);
  static const toxin = Color(0xFF9C6CE0);
  static const offline = Color(0xFFFF2E46);

  // Rareza (sobria, en clave clínica)
  static const rarityCommon = Color(0xFFA4B8BD);
  static const rarityUncommon = Color(0xFF74C044);
  static const rarityRare = Color(0xFF6ADBEA);
  static const rarityEpic = Color(0xFFB48CF0);
  static const rarityLegendary = Color(0xFFE2B53E);

  // Tipografías
  static const fDisplay = 'Jost';
  static const fUi = 'BarlowSemiCondensed';
  static const fMono = 'ShareTechMono';
  static const fPaper = 'CourierPrime';
  static const fStamp = 'SpecialElite';
  static const fLogo = 'Syncopate';

  // Movimiento
  static const snap = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 240);
  static const heavy = Duration(milliseconds: 360);
  static const easeIn = Cubic(0.2, 0, 0, 1);
  static const easeOut = Cubic(0.4, 0, 1, 1);
  static const scanCurve = Cubic(0.16, 1, 0.3, 1);

  // Geometría
  static const chamfer = 6.0;
  static const bracket = 8.0;
}

/// Estilos de texto base.
abstract final class SuturaText {
  static const display = TextStyle(fontFamily: Sutura.fDisplay, fontWeight: FontWeight.w500, letterSpacing: 2.4, color: Sutura.textHi, height: 1.05);
  static const title = TextStyle(fontFamily: Sutura.fDisplay, fontWeight: FontWeight.w500, fontSize: 18, letterSpacing: 1.8, color: Sutura.textHi);
  static const body = TextStyle(fontFamily: Sutura.fUi, fontWeight: FontWeight.w500, fontSize: 15, height: 1.33, color: Sutura.textHi);
  static const bodyMid = TextStyle(fontFamily: Sutura.fUi, fontWeight: FontWeight.w500, fontSize: 14, height: 1.35, color: Sutura.textMid);
  static const caption = TextStyle(fontFamily: Sutura.fUi, fontWeight: FontWeight.w600, fontSize: 12, letterSpacing: 1.0, color: Sutura.textMid);
  static const button = TextStyle(fontFamily: Sutura.fUi, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 1.6, color: Sutura.textHi);
  static const mono = TextStyle(fontFamily: Sutura.fMono, fontSize: 13, color: Sutura.textHi, letterSpacing: 0.5);
  static const micro = TextStyle(fontFamily: Sutura.fMono, fontSize: 8.5, color: Sutura.textLow, letterSpacing: 0.8);
  static const paper = TextStyle(fontFamily: Sutura.fPaper, fontSize: 15, height: 1.6, color: Sutura.textPaper);
  static const stamp = TextStyle(fontFamily: Sutura.fStamp, fontSize: 16, color: Sutura.danger, letterSpacing: 2);
  static const logo = TextStyle(fontFamily: Sutura.fLogo, fontWeight: FontWeight.w700, color: Sutura.textHi, letterSpacing: 6);
}

Color rarityColor(String rarityKey) => switch (rarityKey) {
      'uncommon' => Sutura.rarityUncommon,
      'rare' => Sutura.rarityRare,
      'epic' => Sutura.rarityEpic,
      'legendary' => Sutura.rarityLegendary,
      _ => Sutura.rarityCommon,
    };
