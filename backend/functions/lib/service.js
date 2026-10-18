"use strict";

const {classify,buildModel,TYPES,MAX_PROMPT_CHARS}=require("./generator");

const DAILY_LIMIT=20;
const MAX_JSON_BYTES=8*1024*1024;
const MAX_REFERENCE_BYTES=6*1024*1024;
const REFERENCE_MIME_TYPES=new Set(["image/png","image/jpeg","image/webp"]);
const INFERENCE_URL=String(process.env.DABSKY_INFERENCE_URL||"").replace(/\/+$/,"");
const INFERENCE_TOKEN=String(process.env.DABSKY_INFERENCE_TOKEN||"").trim();

function send(res,status,data) {
  res.setHeader("Cache-Control","no-store");
  return res.status(status).json(data);
}

async function reserveQuota(db,uid,date) {
  const daily=date.toISOString().slice(0,10);
  const ref=db.collection("dabsky_quotas").doc(uid+"_"+daily);
  return db.runTransaction(async transaction=>{
    const snapshot=await transaction.get(ref);
    const used=snapshot.exists ? Number(snapshot.data().used||0) : 0;
    if(used>=DAILY_LIMIT)return false;
    transaction.set(ref,{uid,day:daily,used:used+1,updatedAt:date.toISOString()});
    return true;
  });
}

function parseBody(req) {
  const content=req.body;
  const size=Buffer.isBuffer(content)?content.length:Buffer.byteLength(
    typeof content==="string"?content:JSON.stringify(content??{}));
  if(size>MAX_JSON_BYTES)throw new RangeError("Payload is too large.");
  let body=content;
  if(Buffer.isBuffer(body))body=JSON.parse(body.toString("utf8"));
  if(typeof body==="string")body=JSON.parse(body);
  if(!body||typeof body!=="object"||Array.isArray(body))throw new RangeError("Expected a JSON object.");
  const allowed=new Set(["prompt","output_format","client","client_version","reference_image"]);
  if(Object.keys(body).some(key=>!allowed.has(key)))throw new RangeError("Unsupported request field.");
  if(typeof body.prompt!=="string"||body.prompt.trim().length<1||body.prompt.length>MAX_PROMPT_CHARS)
    throw new RangeError("Invalid prompt.");

  let reference_image=null;
  let reference_payload=null;
  if(body.reference_image!==undefined) {
    const ref=body.reference_image;
    if(!ref||typeof ref!=="object"||Array.isArray(ref))
      throw new RangeError("Reference image must be an object.");
    if(!REFERENCE_MIME_TYPES.has(ref.mime_type))
      throw new RangeError("Reference image must be PNG, JPEG or WebP.");
    if(typeof ref.data_base64!=="string"||ref.data_base64.length<4||
       ref.data_base64.length>Math.ceil(MAX_REFERENCE_BYTES*4/3)+8)
      throw new RangeError("Reference image is too large.");
    if(!/^[A-Za-z0-9+/]+={0,2}$/.test(ref.data_base64))
      throw new RangeError("Reference image encoding is invalid.");
    const decoded=Buffer.from(ref.data_base64,"base64");
    if(decoded.length<1||decoded.length>MAX_REFERENCE_BYTES)
      throw new RangeError("Reference image is too large.");
    reference_image={
      filename:typeof ref.filename==="string"?ref.filename.slice(0,96):"reference-image",
      mime_type:ref.mime_type,
      bytes:decoded.length
    };
    // Keep the image in memory only long enough to submit it to the private
    // worker. The Firestore document receives metadata, never image bytes.
    reference_payload={
      filename:reference_image.filename,
      mime_type:reference_image.mime_type,
      data_base64:ref.data_base64
    };
  }
  return {prompt:body.prompt.trim(),reference_image,reference_payload};
}

function readPrompt(req) {
  return parseBody(req).prompt;
}

function inferenceHeaders() {
  const headers={"Accept":"application/json","Content-Type":"application/json"};
  if(INFERENCE_TOKEN)headers.Authorization="Bearer "+INFERENCE_TOKEN;
  return headers;
}

function inferenceUrl(path) {
  if(!INFERENCE_URL)throw Error("DABSKY_INFERENCE_URL is not configured.");
  return INFERENCE_URL+(path.startsWith("/")?path:"/"+path);
}

async function submitInference(request) {
  const response=await fetch(inferenceUrl("/v1/jobs"),{
    method:"POST",
    headers:inferenceHeaders(),
    body:JSON.stringify({
      prompt:request.prompt,
      output_format:"glb",
      reference_image:request.reference_payload
    })
  });
  const raw=await response.text();
  let data;
  try {data=JSON.parse(raw);} catch(_error) {data={};}
  if(!response.ok)throw Object.assign(Error(String(data.detail||data.error||"Inference worker rejected the job.")),{status:response.status});
  if(!data.id)throw Error("Inference worker returned no job id.");
  return data;
}

async function readInferenceJob(workerJobId) {
  const response=await fetch(inferenceUrl("/v1/jobs/"+encodeURIComponent(workerJobId)),{
    method:"GET",headers:inferenceHeaders()
  });
  const raw=await response.text();
  let data;
  try {data=JSON.parse(raw);} catch(_error) {data={};}
  if(!response.ok)throw Error(String(data.detail||data.error||"Inference worker status failed."));
  return data;
}

async function readInferenceModel(workerJobId) {
  const response=await fetch(inferenceUrl("/v1/jobs/"+encodeURIComponent(workerJobId)+"/model"),{
    method:"GET",headers:inferenceHeaders()
  });
  if(!response.ok) {
    const raw=await response.text();
    let data;
    try {data=JSON.parse(raw);} catch(_error) {data={};}
    throw Object.assign(Error(String(data.detail||data.error||"Inference model is not ready.")),{
      status:response.status
    });
  }
  return Buffer.from(await response.arrayBuffer());
}

function createHandler({db,verifyIdToken,now=()=>new Date()}) {
  if(!db||typeof verifyIdToken!=="function")throw Error("Admin dependencies required.");
  return async function api(req,res) {
    try {
      const url=new URL(req.url,"https://dabsky.local");
      const path=url.pathname.replace(/\/+$/,"")||"/";
      if(req.method==="GET"&&path==="/health")
        return send(res,200,{status:"ok",service:"dabsky-connect",version:"0.4.0",
          generator:INFERENCE_URL?"hunyuan3d-2.1-with-procedural-fallback":"procedural-fallback",
          image_to_mesh_ai:Boolean(INFERENCE_URL),reference_images:true,text_conditioning:INFERENCE_URL?"worker_optional":"offline_only"});
      if(req.method==="GET"&&path==="/v1/catalog")
        return send(res,200,{types:TYPES,generator:INFERENCE_URL?"hunyuan3d-2.1":"procedural-fallback",
          text_to_mesh_ai:Boolean(INFERENCE_URL),image_to_mesh_ai:Boolean(INFERENCE_URL),reference_images:true,text_conditioning:INFERENCE_URL?"worker_optional":"offline_only"});
      if(!path.startsWith("/v1/jobs"))return send(res,404,{error:"Not found."});

      const match=/^\/v1\/jobs\/([A-Za-z0-9_-]{8,128})(\/model)?$/.exec(path);
      const listing=path==="/v1/jobs";
      if((listing&&req.method!=="POST")||(match&&req.method!=="GET")||(!listing&&!match))
        return send(res,405,{error:"Unsupported route or method."});

      const header=String(req.headers?.authorization||"");
      if(!/^Bearer [A-Za-z0-9._~-]+$/.test(header)||header.length>4200)
        return send(res,401,{error:"Firebase ID token required."});
      let uid;
      try {
        const verified=await verifyIdToken(header.slice(7));
        uid=verified?.uid;
      }catch(_error){return send(res,401,{error:"Invalid or expired Firebase ID token."});}
      if(typeof uid!=="string"||uid.length<1||uid.length>128)
        return send(res,401,{error:"Unverified identity."});

      if(listing) {
        let request,kind="remote";
        try {
          request=parseBody(req);
          // The procedural fallback keeps its strict catalog. The neural worker
          // accepts arbitrary reference-conditioned prompts.
          if(!INFERENCE_URL)kind=classify(request.prompt);
        } catch(error) {
          if(error instanceof RangeError||error instanceof SyntaxError)
            return send(res,400,{error:error.message});
          throw error;
        }
        const available=await reserveQuota(db,uid,now());
        if(!available)return send(res,429,{error:"Daily generation limit reached (20 per user)."});
        let remote=null;
        if(INFERENCE_URL) {
          try {remote=await submitInference(request);}
          catch(error) {
            console.error("Dabsky inference worker request failed:",error?.message||"unknown");
            const code=Number(error?.status||502);
            if(code===400||code===422)
              return send(res,code,{error:String(error.message||"Dabsky AI worker rejected the job.")});
            return send(res,502,{error:"Dabsky AI worker is unavailable."});
          }
        }
        const doc=db.collection("dabsky_jobs").doc();
        const createdAt=now().toISOString();
        const generator=remote?"hunyuan3d-2.1":"procedural-fallback-v0.2";
        const status=remote?String(remote.status||"queued"):"ready";
        const record={uid,prompt:request.prompt,kind,status,generator,
          reference_image:request.reference_image,createdAt};
        if(remote)record.worker_job_id=String(remote.id);
        await doc.set(record);
        return send(res,remote?202:201,{id:doc.id,kind,status,generator,
          reference_image:!!request.reference_image,model_path:"/v1/jobs/"+doc.id+"/model"});
      }

      const jobRef=db.collection("dabsky_jobs").doc(match[1]);
      const job=await jobRef.get();
      if(!job.exists||job.data()?.uid!==uid)return send(res,404,{error:"Job not found."});
      const data=job.data();

      if(data.worker_job_id) {
        if(!INFERENCE_URL)return send(res,503,{error:"Inference worker is not configured."});
        if(match[2]) {
          try {
            const bytes=await readInferenceModel(data.worker_job_id);
            res.setHeader("Content-Type","model/gltf-binary");
            res.setHeader("Content-Disposition",'attachment; filename="dabsky-ai.glb"');
            res.setHeader("Cache-Control","private, no-store");
            return res.status(200).send(bytes);
          } catch(error) {
            const code=Number(error.status||502);
            return send(res,code===409?409:502,{error:code===409?"Model is not ready.":"Dabsky AI worker is unavailable."});
          }
        }
        try {
          const remote=await readInferenceJob(data.worker_job_id);
          const status=String(remote.status||data.status);
          if(status!==data.status)await jobRef.set({...data,status});
          return send(res,200,{id:match[1],kind:data.kind,status,
            progress:Number(remote.progress||0),message:String(remote.message||""),
            generator:data.generator,reference_image:!!data.reference_image,
            created_at:data.createdAt,
            model_path:status==="ready"?"/v1/jobs/"+match[1]+"/model":null});
        } catch(_error) {
          return send(res,502,{error:"Dabsky AI worker is unavailable."});
        }
      }

      if(match[2]) {
        if(data.status!=="ready")return send(res,409,{error:"Model is not ready."});
        const output=buildModel(data.kind);
        res.setHeader("Content-Type","model/gltf-binary");
        res.setHeader("Content-Disposition",'attachment; filename="dabsky-'+data.kind+'.glb"');
        res.setHeader("Cache-Control","private, no-store");
        return res.status(200).send(output.bytes);
      }
      return send(res,200,{id:match[1],kind:data.kind,status:data.status,
        generator:data.generator,reference_image:!!data.reference_image,created_at:data.createdAt,
        model_path:data.status==="ready"?"/v1/jobs/"+match[1]+"/model":null});
    } catch(error) {
      console.error("Dabsky API request failed:",error?.message||"unknown");
      return send(res,500,{error:"Internal server error."});
    }
  };
}

module.exports={createHandler,parseBody,readPrompt,reserveQuota,DAILY_LIMIT};
