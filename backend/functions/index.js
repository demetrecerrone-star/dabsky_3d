"use strict";
const {onRequest}=require("firebase-functions/v2/https");
const {initializeApp,getApps}=require("firebase-admin/app");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore}=require("firebase-admin/firestore");
const {createHandler}=require("./lib/service");
// Cloud Functions supplies application default credentials automatically.
if(!getApps().length)initializeApp();
exports.dabskyApi=onRequest({
  region:"us-central1",cors:false,invoker:"public",memory:"256MiB",
  minInstances:0,maxInstances:1,timeoutSeconds:30
},createHandler({
  db:getFirestore(),
  verifyIdToken:token=>getAuth().verifyIdToken(token,true),
}));
