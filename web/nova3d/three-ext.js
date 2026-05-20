// Single import boundary for Three.js + addons. All other Nova modules import
// from here rather than reaching for the importmap directly, so a CDN/version
// change only touches this file.

import * as THREE from 'three';
import { OrbitControls }      from 'three/addons/controls/OrbitControls.js';
import { TransformControls }  from 'three/addons/controls/TransformControls.js';
import { GLTFLoader }         from 'three/addons/loaders/GLTFLoader.js';
import { GLTFExporter }       from 'three/addons/exporters/GLTFExporter.js';
import { RGBELoader }         from 'three/addons/loaders/RGBELoader.js';
import { mergeGeometries }    from 'three/addons/utils/BufferGeometryUtils.js';

export {
  THREE,
  OrbitControls,
  TransformControls,
  GLTFLoader,
  GLTFExporter,
  RGBELoader,
  mergeGeometries,
};
