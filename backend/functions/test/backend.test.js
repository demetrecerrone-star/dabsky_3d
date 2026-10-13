"use strict";

const test=require("node:test");
const assert=require("node:assert/strict");
const {classify,buildModel,TYPES}=require("../lib/generator");
const {createHandler}=require("../lib/service");

function mockStore() {
  const collections=new Map();
  let nextId=0;
  function collection(name) {
    if(!collections.has(name))collections.set(name,new Map());
    const records=collections.get(name);
    return {doc(id) {
      const key=id??"job_"+String(++nextId).padStart(12,"0");
      return {id:key, async get() {return {exists:records.has(key),data:()=>records.get(key)};},
        async set(value) {records.set(key,value);}};
    }};
  }
  const db={collection,async runTransaction(callback) {
    const writes=[];
    const tx={get:ref=>ref.get(),set:(ref,value)=>writes.push([ref,value])};
    const result=await callback(tx);
    for(const [ref,value] of writes)await ref.set(value);
    return result;
  }};
  return db;
}
function response() {
  return {code:200,headers:{},status(n){this.code=n;return this;},
    setHeader(k,v){this.headers[k.toLowerCase()]=v;return this;},
    json(v){this.body=v;return this;},send(v){this.body=v;return this;}};
}
async function send(handler,method,url,uid="user-a",body) {
  const res=response();
  await handler({method,url,headers:{authorization:uid?"Bearer "+uid:""},body},res);
  return res;
}

test("GLB writer produces structurally valid static geometry for all three types",()=>{
  for(const kind of TYPES) {
    const model=buildModel(kind);
    const bytes=model.bytes;
    assert.equal(bytes.readUInt32LE(0),0x46546c67);
    assert.equal(bytes.readUInt32LE(4),2);
    assert.equal(bytes.readUInt32LE(8),bytes.length);
    const jsonLength=bytes.readUInt32LE(12);
    assert.equal(bytes.readUInt32LE(16),0x4e4f534a);
    const gltf=JSON.parse(bytes.subarray(20,20+jsonLength).toString("utf8"));
    const binAt=20+jsonLength;
    assert.equal(bytes.readUInt32LE(binAt+4),0x004e4942);
    assert.equal(gltf.asset.version,"2.0");
    assert.ok(gltf.meshes[0].primitives.length>=2 && gltf.meshes[0].primitives.length<=3);
    assert.equal(gltf.buffers[0].byteLength,model.vertices*3*4*2);
    assert.ok(model.vertices>100&&model.triangles>30);
    for(const accessor of gltf.accessors) {
      assert.ok(accessor.count>0);
      assert.equal(accessor.type,"VEC3");
      assert.ok(gltf.bufferViews[accessor.bufferView].byteOffset>=0);
    }
  }
});
test("prompts map to a narrow explicitly supported catalog",()=>{
  assert.equal(classify("Create a fantasy wooden barrel"),"barrel");
  assert.equal(classify("Make a simple treasure chest"),"chest");
  assert.equal(classify("Create medieval tables"),"table");
  for(const text of ["build me a castle","make a sword and a table and a chest","", "x".repeat(181)]) {
    assert.throws(()=>classify(text));
  }
});

test("health and catalog are public, job mutation requires Firebase user token",async()=>{
  const handler=createHandler({db:mockStore(),verifyIdToken:async token=>({uid:token})});
  const health=await send(handler,"GET","/health",null);
  assert.equal(health.code,200);
  assert.equal(health.body.service,"dabsky-connect");
  const catalog=await send(handler,"GET","/v1/catalog",null);
  assert.equal(catalog.code,200);
  assert.equal(catalog.body.text_to_mesh_ai,false);
  assert.equal((await send(handler,"POST","/v1/jobs",null,{prompt:"a barrel"})).code,401);
  assert.equal((await send(handler,"GET","/v1/jobs/abcdefgh/model",null)).code,401);
  assert.equal((await send(handler,"DELETE","/v1/jobs", "user-a")).code,405);
});
test("authenticated job lifecycle yields GLB to owner but not to another user",async()=>{
  const store=mockStore();
  const handler=createHandler({db:store,verifyIdToken:async token=>({uid:token})});
  const create=await send(handler,"POST","/v1/jobs","alice",{prompt:"Create a medieval chest"});
  assert.equal(create.code,201);
  assert.equal(create.body.status,"ready");
  assert.equal(create.body.kind,"chest");
  const jobId=create.body.id;
  const own=await send(handler,"GET","/v1/jobs/"+jobId,"alice");
  assert.equal(own.code,200);
  assert.equal(own.body.kind,"chest");
  const blocked=await send(handler,"GET","/v1/jobs/"+jobId+"/model","bob");
  assert.equal(blocked.code,404);
  const glb=await send(handler,"GET","/v1/jobs/"+jobId+"/model","alice");
  assert.equal(glb.code,200);
  assert.equal(glb.headers["content-type"],"model/gltf-binary");
  assert.ok(Buffer.isBuffer(glb.body));
  assert.equal(glb.body.readUInt32LE(0),0x46546c67);
  assert.ok(glb.body.length>1000);
  const missing=await send(handler,"GET","/v1/jobs/unknown_000000","alice");
  assert.equal(missing.code,404);
});
test("invalid requests never create a job or count toward a quota",async()=>{
  const store=mockStore();
  const handler=createHandler({db:store,verifyIdToken:async token=>({uid:token})});
  for(const prompt of ["make a dragon","create a chest and a table","x".repeat(181)]) {
    const out=await send(handler,"POST","/v1/jobs","alice",{prompt});
    assert.equal(out.code,400);
  }
  const extra=await send(handler,"POST","/v1/jobs","alice",{prompt:"barrel",admin:true});
  assert.equal(extra.code,400);
  const legitimate=await send(handler,"POST","/v1/jobs","alice",{prompt:"wooden barrel"});
  assert.equal(legitimate.code,201);
});
test("per-user daily quota caps server-side procedural generation",async()=>{
  const handler=createHandler({db:mockStore(),verifyIdToken:async token=>({uid:token}),
    now:()=>new Date("2026-10-12T12:00:00Z")});
  for(let i=0;i<20;i++){
    const out=await send(handler,"POST","/v1/jobs","alice",{prompt:"barrel"});
    assert.equal(out.code,201);
  }
  const limit=await send(handler,"POST","/v1/jobs","alice",{prompt:"barrel"});
  assert.equal(limit.code,429);
  assert.equal((await send(handler,"POST","/v1/jobs","bob",{prompt:"barrel"})).code,201);
});
test("bad Firebase ID tokens are denied without leaking backend error details",async()=>{
  const handler=createHandler({db:mockStore(),
    verifyIdToken:async()=>{throw new Error("Sensitive service account failure.");}});
  const out=await send(handler,"POST","/v1/jobs","untrusted",{prompt:"barrel"});
  assert.equal(out.code,401);
  assert.doesNotMatch(JSON.stringify(out.body),/service account/i);
});
