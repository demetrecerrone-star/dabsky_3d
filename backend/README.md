# Dabsky Connect v0.1 — Firebase backend

Firebase Project ID: `dabsky-3d`.

**Current scope:** deployable/tested backend prototype. It creates original **procedural** GLB props: barrel, chest and table. It is NOT yet the trained text-to-3D AI and it is NOT a connected ChatGPT MCP plugin.

## Endpoints

- `GET /health`: public service status.
- `GET /v1/catalog`: public supported model types and capability declaration.
- `POST /v1/jobs`: requires Firebase Auth bearer ID token and JSON `{ "prompt": "Create a medieval chest" }`; returns a ready job ID and model path.
- `GET /v1/jobs/{id}`: requires same user's Firebase Auth ID token; returns job status.
- `GET /v1/jobs/{id}/model`: requires same user; returns downloadable binary GLB.

Prototype generation completes immediately. Metadata is stored in Firestore and binary GLBs are rebuilt deterministically when retrieved. No Firebase Storage bucket is needed at this stage.

## Security and limits

- Firebase ID tokens verified with Admin SDK, including token revocation.
- Each job belongs to one user. Cross-user access is intentionally returned as 404.
- Quota limit: 20 new jobs per UID, per UTC day; Firestore transaction protects against concurrent bypass.
- Generator only supports three procedural types. Unsupported prompts are rejected with 400 rather than hallucinating a model.
- No service-account key in source code or Android APK; Cloud Functions uses managed credentials.
- Firestore client rules deny all reads and writes for job and quota collections; only Admin SDK can access them.
- Cloud Function maxInstances=1, minInstances=0. Limits reduce expense but are not an absolute cost cap.

## Local and GitHub test

Run `cd backend/functions && npm test`. Tests use Node's built-in runner and simulated Firebase Auth/Firestore, requiring no Firebase credentials or npm dependency download. The `.github/workflows/dabsky-connect.yml` workflow runs these tests on the research feature branch. This does not constitute a live deployed smoke test.

## Deployment checklist (requires the Firebase project owner)

1. In the Firebase console for project `dabsky-3d`, enable Firebase Authentication and a Cloud Firestore database.
2. Cloud Functions deployment requires **Blaze pay-as-you-go** billing. Do not enable it without approving possible charges. Configure budget alerts and evaluate Cloud Run spend limits. Budget alerts do not automatically stop billing.
3. Install Firebase CLI and authenticate on a machine or CI environment with deployment privileges. Prefer short-lived Workload Identity Federation credentials over long-lived service account JSON keys.
4. At repository root run `cd backend/functions && npm install && cd ../.. && firebase deploy --project dabsky-3d --only firestore:rules,functions`.
5. Test live `/health`, authentication, ownership and GLB responses at the deployed function URL.
6. Implement a separate OAuth-protected ChatGPT MCP server/adapter if supported by the user's ChatGPT plan, so ChatGPT can invoke these operations directly. This step is **not yet implemented**.

Firebase's Cloud Functions managed credentials mean the `serviceAccountKey.json` file shown in SDK examples should never be uploaded to ChatGPT or committed to GitHub.

## Next

- Add Android login and a model jobs panel.
- Add accessible monitoring, deployed integration tests and job cancellation as generation becomes asynchronous.
- Replace the procedural GLB builder with Dabsky's original learning-based model after training, licensing and quality benchmarks justify it.
