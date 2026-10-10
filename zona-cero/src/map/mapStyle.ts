import type { StyleSpecification } from 'maplibre-gl';

// Estilo de mapa propio: oscuro, postapocalíptico, sobre los tiles vectoriales
// gratuitos de OpenFreeMap (datos de OpenStreetMap). No requiere API key.

export const OMT_SOURCE = 'openmaptiles';
const FONT = ['Noto Sans Regular'];
const FONT_BOLD = ['Noto Sans Bold'];

const C = {
  background: '#0f120f',
  residential: '#121612',
  park: '#16200f',
  wood: '#142010',
  water: '#08161a',
  waterLine: '#0c2329',
  buildingLow: '#1b201b',
  buildingHigh: '#2a3029',
  path: '#3b4233',
  minor: '#262b22',
  minorCasing: '#191c17',
  major: '#3b3a2b',
  majorCasing: '#1c1b14',
  motorway: '#4d3b24',
  rail: '#2c2c2a',
  label: '#7f8875',
  labelHalo: '#0b0d0b',
  place: '#a3ad92',
};

export function buildMapStyle(): StyleSpecification | string {
  const custom = import.meta.env.VITE_MAP_STYLE_URL as string | undefined;
  if (custom) return custom;
  return {
    version: 8,
    name: 'Zona Cero',
    glyphs: 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
    sources: {
      [OMT_SOURCE]: {
        type: 'vector',
        url: 'https://tiles.openfreemap.org/planet',
        attribution:
          '<a href="https://openfreemap.org" target="_blank">OpenFreeMap</a> © <a href="https://www.openstreetmap.org/copyright" target="_blank">OpenStreetMap</a>',
      },
    },
    layers: [
      { id: 'background', type: 'background', paint: { 'background-color': C.background } },
      {
        id: 'landuse-residential',
        type: 'fill',
        source: OMT_SOURCE,
        'source-layer': 'landuse',
        filter: ['==', ['get', 'class'], 'residential'],
        paint: { 'fill-color': C.residential },
      },
      {
        id: 'landcover-wood',
        type: 'fill',
        source: OMT_SOURCE,
        'source-layer': 'landcover',
        filter: ['match', ['get', 'class'], ['wood', 'grass', 'farmland'], true, false],
        paint: { 'fill-color': C.wood, 'fill-opacity': 0.8 },
      },
      {
        id: 'park',
        type: 'fill',
        source: OMT_SOURCE,
        'source-layer': 'park',
        paint: { 'fill-color': C.park, 'fill-opacity': 0.9 },
      },
      {
        id: 'water',
        type: 'fill',
        source: OMT_SOURCE,
        'source-layer': 'water',
        filter: ['!=', ['get', 'brunnel'], 'tunnel'],
        paint: { 'fill-color': C.water },
      },
      {
        id: 'waterway',
        type: 'line',
        source: OMT_SOURCE,
        'source-layer': 'waterway',
        paint: { 'line-color': C.waterLine, 'line-width': 1.5 },
      },
      {
        id: 'road-path',
        type: 'line',
        source: OMT_SOURCE,
        'source-layer': 'transportation',
        minzoom: 14,
        filter: ['all', ['==', ['geometry-type'], 'LineString'], ['==', ['get', 'class'], 'path']],
        paint: {
          'line-color': C.path,
          'line-width': ['interpolate', ['linear'], ['zoom'], 14, 0.6, 18, 2],
          'line-dasharray': [2, 2],
        },
      },
      {
        id: 'road-minor-casing',
        type: 'line',
        source: OMT_SOURCE,
        'source-layer': 'transportation',
        minzoom: 13,
        filter: ['match', ['get', 'class'], ['minor', 'service', 'track'], true, false],
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': C.minorCasing,
          'line-width': ['interpolate', ['exponential', 1.6], ['zoom'], 13, 2, 19, 26],
        },
      },
      {
        id: 'road-minor',
        type: 'line',
        source: OMT_SOURCE,
        'source-layer': 'transportation',
        minzoom: 13,
        filter: ['match', ['get', 'class'], ['minor', 'service', 'track'], true, false],
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': C.minor,
          'line-width': ['interpolate', ['exponential', 1.6], ['zoom'], 13, 1, 19, 20],
        },
      },
      {
        id: 'road-major-casing',
        type: 'line',
        source: OMT_SOURCE,
        'source-layer': 'transportation',
        filter: ['match', ['get', 'class'], ['primary', 'secondary', 'tertiary', 'trunk'], true, false],
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': C.majorCasing,
          'line-width': ['interpolate', ['exponential', 1.6], ['zoom'], 10, 2, 19, 38],
        },
      },
      {
        id: 'road-major',
        type: 'line',
        source: OMT_SOURCE,
        'source-layer': 'transportation',
        filter: ['match', ['get', 'class'], ['primary', 'secondary', 'tertiary', 'trunk'], true, false],
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': C.major,
          'line-width': ['interpolate', ['exponential', 1.6], ['zoom'], 10, 1, 19, 30],
        },
      },
      {
        id: 'road-motorway',
        type: 'line',
        source: OMT_SOURCE,
        'source-layer': 'transportation',
        filter: ['==', ['get', 'class'], 'motorway'],
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': C.motorway,
          'line-width': ['interpolate', ['exponential', 1.6], ['zoom'], 8, 1, 19, 36],
        },
      },
      {
        id: 'rail',
        type: 'line',
        source: OMT_SOURCE,
        'source-layer': 'transportation',
        filter: ['match', ['get', 'class'], ['rail', 'transit'], true, false],
        paint: { 'line-color': C.rail, 'line-width': 2, 'line-dasharray': [3, 3] },
      },
      {
        id: 'building-3d',
        type: 'fill-extrusion',
        source: OMT_SOURCE,
        'source-layer': 'building',
        minzoom: 15,
        filter: ['!=', ['get', 'hide_3d'], true],
        paint: {
          'fill-extrusion-color': [
            'interpolate',
            ['linear'],
            ['coalesce', ['get', 'render_height'], 6],
            0,
            C.buildingLow,
            60,
            C.buildingHigh,
          ],
          'fill-extrusion-height': ['coalesce', ['get', 'render_height'], 6],
          'fill-extrusion-base': ['coalesce', ['get', 'render_min_height'], 0],
          'fill-extrusion-opacity': 0.92,
        },
      },
      {
        id: 'road-label',
        type: 'symbol',
        source: OMT_SOURCE,
        'source-layer': 'transportation_name',
        minzoom: 15,
        layout: {
          'symbol-placement': 'line',
          'text-field': ['coalesce', ['get', 'name:es'], ['get', 'name']],
          'text-font': FONT,
          'text-size': 11,
          'text-letter-spacing': 0.05,
        },
        paint: { 'text-color': C.label, 'text-halo-color': C.labelHalo, 'text-halo-width': 1.4 },
      },
      {
        id: 'place-label',
        type: 'symbol',
        source: OMT_SOURCE,
        'source-layer': 'place',
        filter: ['match', ['get', 'class'], ['suburb', 'neighbourhood', 'quarter', 'city', 'town'], true, false],
        layout: {
          'text-field': ['upcase', ['coalesce', ['get', 'name:es'], ['get', 'name']]],
          'text-font': FONT_BOLD,
          'text-size': ['interpolate', ['linear'], ['zoom'], 11, 11, 16, 14],
          'text-letter-spacing': 0.2,
          'text-max-width': 8,
        },
        paint: { 'text-color': C.place, 'text-halo-color': C.labelHalo, 'text-halo-width': 1.6, 'text-opacity': 0.8 },
      },
    ],
  };
}
