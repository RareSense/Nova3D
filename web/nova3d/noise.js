// Procedural noise + canvas-based normal/roughness map generators used by the
// metal material factories. Pure: no module state, no DOM beyond `<canvas>`.

import { THREE } from '@nova/three-ext.js';
import { normalizeTexture } from '@nova/util.js';

export function smoothNoise(x, y, seed = 0) {
  const n = Math.sin(x * 12.9898 + y * 78.233 + seed) * 43758.5453;
  return n - Math.floor(n);
}

export function interpNoise(x, y, seed = 0) {
  const x0 = Math.floor(x), y0 = Math.floor(y);
  const fx = x - x0, fy = y - y0;
  const sx = fx*fx*(3-2*fx), sy = fy*fy*(3-2*fy);
  return (smoothNoise(x0,y0,seed)*(1-sx) + smoothNoise(x0+1,y0,seed)*sx)*(1-sy) +
         (smoothNoise(x0,y0+1,seed)*(1-sx) + smoothNoise(x0+1,y0+1,seed)*sx)*sy;
}

export function fractalNoise(x, y, oct=6, persist=0.5, seed=0) {
  let total=0, freq=1, amp=1, max=0;
  for (let i=0; i<oct; i++) {
    total += interpNoise(x*freq, y*freq, seed+i*100)*amp;
    max += amp; amp *= persist; freq *= 2;
  }
  return total / max;
}

export function genNormalMap(size=512, scale=8, intensity=0.3, seed=Math.random()*1000) {
  const cvs = document.createElement('canvas'); cvs.width = cvs.height = size;
  const ctx = cvs.getContext('2d'), img = ctx.createImageData(size,size), d = img.data;
  const hm = new Float32Array(size*size);
  for (let y=0; y<size; y++) for (let x=0; x<size; x++) {
    const nx=x/size*scale, ny=y/size*scale;
    hm[y*size+x] = fractalNoise(nx,ny,6,.5,seed)*.6
                 + fractalNoise(nx*4,ny*4,4,.4,seed+500)*.25
                 + fractalNoise(nx*16,ny*16,3,.3,seed+1000)*.15;
  }
  for (let y=0; y<size; y++) for (let x=0; x<size; x++) {
    const i=(y*size+x)*4;
    const gh = (px,py) => hm[((py%size+size)%size)*size+((px%size+size)%size)];
    const dx=(gh(x+1,y-1)+2*gh(x+1,y)+gh(x+1,y+1)-gh(x-1,y-1)-2*gh(x-1,y)-gh(x-1,y+1))*intensity;
    const dy=(gh(x-1,y+1)+2*gh(x,y+1)+gh(x+1,y+1)-gh(x-1,y-1)-2*gh(x,y-1)-gh(x+1,y-1))*intensity;
    const len=Math.sqrt(dx*dx+dy*dy+1);
    d[i]=(-dx/len*.5+.5)*255; d[i+1]=(-dy/len*.5+.5)*255; d[i+2]=(1/len*.5+.5)*255; d[i+3]=255;
  }
  ctx.putImageData(img,0,0);
  const t = new THREE.CanvasTexture(cvs);
  normalizeTexture(t, THREE.NoColorSpace);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(2,2); return t;
}

export function genRoughnessMap(size=512, base=0.15, variation=0.1, seed=Math.random()*1000) {
  const cvs = document.createElement('canvas'); cvs.width = cvs.height = size;
  const ctx = cvs.getContext('2d'), img = ctx.createImageData(size,size), d = img.data;
  for (let y=0; y<size; y++) for (let x=0; x<size; x++) {
    const i=(y*size+x)*4;
    const nx=x/size*12, ny=y/size*12;
    const noise = fractalNoise(nx,ny,5,.5,seed) + fractalNoise(nx*8,ny*8,3,.3,seed+777)*.3;
    const v = Math.max(0,Math.min(1, base+(noise-.5)*variation*2))*255;
    d[i]=d[i+1]=d[i+2]=v; d[i+3]=255;
  }
  ctx.putImageData(img,0,0);
  const t = new THREE.CanvasTexture(cvs);
  normalizeTexture(t, THREE.NoColorSpace);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(2,2); return t;
}
