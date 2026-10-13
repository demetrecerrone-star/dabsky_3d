"use strict";

/** Original, deterministic procedural GLB builder for Dabsky Connect v0.1.
 * This is NOT the trained text-to-mesh AI. All output is simple static geometry.
 */
const TYPES = Object.freeze(["barrel", "chest", "table"]);
const MAX_PROMPT_CHARS = 180;

function classify(prompt) {
  if (typeof prompt !== "string" || !prompt.trim() || prompt.length > MAX_PROMPT_CHARS) {
    throw new RangeError("Prompt must contain 1–180 characters.");
  }
  const text = prompt.toLowerCase();
  const kinds = TYPES.filter((type) => new RegExp("\\b" + type + "s?\\b").test(text));
  if (kinds.length !== 1) {
    throw new RangeError("This prototype only builds one barrel, chest, or table at a time.");
  }
  return kinds[0];
}

function builder() {
  const groups = new Map();
  const palette = {
    wood: {color: [0.42, 0.25, 0.12, 1], metallic: 0.0, roughness: 0.9},
    timber: {color: [0.56, 0.34, 0.17, 1], metallic: 0.0, roughness: 0.88},
    iron: {color: [0.29, 0.31, 0.35, 1], metallic: 0.72, roughness: 0.56},
  };
  function group(name) {
    if (!groups.has(name)) groups.set(name, {positions: [], normals: []});
    return groups.get(name);
  }
  function tri(mat, a, b, c) {
    const u = a.map((x, i) => b[i] - x);
    const v = a.map((x, i) => c[i] - x);
    const cross = [u[1]*v[2] - u[2]*v[1], u[2]*v[0] - u[0]*v[2], u[0]*v[1] - u[1]*v[0]];
    const len = Math.hypot(...cross) || 1;
    const n = cross.map(x => x / len);
    const g = group(mat);
    for (const p of [a,b,c]) { g.positions.push(...p); g.normals.push(...n); }
  }
  function quad(mat, a,b,c,d) {tri(mat,a,b,c);tri(mat,a,c,d);}
  function box(mat, x,y,z, sx,sy,sz) {
    const X=[x-sx/2,x+sx/2],Y=[y-sy/2,y+sy/2],Z=[z-sz/2,z+sz/2];
    const p=(a,b,c)=>[X[a],Y[b],Z[c]];
    quad(mat,p(0,0,1),p(1,0,1),p(1,1,1),p(0,1,1)); // +z
    quad(mat,p(1,0,0),p(0,0,0),p(0,1,0),p(1,1,0)); // -z
    quad(mat,p(0,0,0),p(0,0,1),p(0,1,1),p(0,1,0)); // -x
    quad(mat,p(1,0,1),p(1,0,0),p(1,1,0),p(1,1,1)); // +x
    quad(mat,p(0,1,1),p(1,1,1),p(1,1,0),p(0,1,0)); // +y
    quad(mat,p(0,0,0),p(1,0,0),p(1,0,1),p(0,0,1)); // -y
  }
  function cylinder(mat, y, radius, height, sides=12) {
    for(let k=0;k<sides;k++){
      const a=2*Math.PI*k/sides, b=2*Math.PI*(k+1)/sides;
      const p=(theta,cy)=>[radius*Math.cos(theta),cy,radius*Math.sin(theta)];
      const lower=y-height/2,upper=y+height/2;
      quad(mat,p(a,lower),p(b,lower),p(b,upper),p(a,upper));
      tri(mat,[0,upper,0],p(a,upper),p(b,upper));
      tri(mat,[0,lower,0],p(b,lower),p(a,lower));
    }
  }
  return {box,cylinder,groups,palette};
}

function buildModel(kind) {
  if (!TYPES.includes(kind)) throw new RangeError("Unsupported object type.");
  const b=builder();
  if(kind==="barrel") {
    b.cylinder("wood",0.65,0.47,1.22,16);
    b.cylinder("iron",0.19,0.493,0.09,16);
    b.cylinder("iron",1.10,0.493,0.09,16);
  } else if(kind==="chest") {
    b.box("wood",0,0.40,0,1.4,0.66,0.82);
    b.box("timber",0,0.82,0,1.48,0.21,0.88);
    b.box("iron",0,0.45,0.423,0.17,0.34,0.055);
    for(const x of [-0.57,0.57]) {
      b.box("iron",x,0.42,0.42,0.07,0.7,0.04);
      b.box("iron",x,0.82,0,0.065,0.22,0.91);
    }
  } else {
    b.box("timber",0,1.02,0,1.66,0.16,0.99);
    for(const x of [-0.69,0.69])for(const z of [-0.35,0.35]) {
      b.box("wood",x,0.5,z,0.16,0.96,0.16);
    }
    b.box("wood",0,0.77,-0.35,1.45,0.16,0.11);
  }
  const meshes=[], materials=[], views=[], accessors=[], chunks=[];
  let cursor=0, vertices=0;
  function appendFloats(data, kind) {
    const buffer=Buffer.alloc(data.length*4);
    for(let i=0;i<data.length;i++)buffer.writeFloatLE(data[i],i*4);
    const viewIndex=views.length;
    views.push({buffer:0,byteOffset:cursor,byteLength:buffer.length,target:34962});
    chunks.push(buffer);cursor+=buffer.length;
    const accessor={bufferView:viewIndex,componentType:5126,count:data.length/3,type:"VEC3"};
    if(kind==="position"){
      const min=[Infinity,Infinity,Infinity],max=[-Infinity,-Infinity,-Infinity];
      for(let i=0;i<data.length;i+=3)for(let j=0;j<3;j++){
        min[j]=Math.min(min[j],data[i+j]);max[j]=Math.max(max[j],data[i+j]);
      }
      accessor.min=min;accessor.max=max;
    }
    const index=accessors.length;accessors.push(accessor);return index;
  }
  for(const [mat,g] of b.groups) {
    const pos=appendFloats(g.positions,"position"),norm=appendFloats(g.normals,"normal");
    const pbr=b.palette[mat];
    const material=materials.length;
    materials.push({name:mat, pbrMetallicRoughness:{
      baseColorFactor:pbr.color,metallicFactor:pbr.metallic,roughnessFactor:pbr.roughness},
      doubleSided:true});
    meshes.push({attributes:{POSITION:pos,NORMAL:norm},material,mode:4});
    vertices+=g.positions.length/3;
  }
  if(vertices>15000)throw new RangeError("Model exceeded procedural complexity limit.");
  const gltf={asset:{version:"2.0",generator:"Dabsky Connect procedural prototype 0.1"},
    scene:0,scenes:[{nodes:[0]}],nodes:[{name:kind,mesh:0}],
    meshes:[{name:kind,primitives:meshes}],materials,
    buffers:[{byteLength:cursor}],bufferViews:views,accessors};
  const json=Buffer.from(JSON.stringify(gltf),"utf8");
  const jsonPad=(4-json.length%4)%4,bin=Buffer.concat(chunks);
  const binPad=(4-bin.length%4)%4;
  const total=12+8+json.length+jsonPad+8+bin.length+binPad;
  const out=Buffer.alloc(total,0);
  out.writeUInt32LE(0x46546c67,0);out.writeUInt32LE(2,4);out.writeUInt32LE(total,8);
  out.writeUInt32LE(json.length+jsonPad,12);out.writeUInt32LE(0x4e4f534a,16);
  json.copy(out,20);out.fill(0x20,20+json.length,20+json.length+jsonPad);
  const off=20+json.length+jsonPad;
  out.writeUInt32LE(bin.length+binPad,off);out.writeUInt32LE(0x004e4942,off+4);
  bin.copy(out,off+8);
  return {bytes:out,vertices,triangles:vertices/3,kind};
}

module.exports={TYPES,MAX_PROMPT_CHARS,classify,buildModel};
