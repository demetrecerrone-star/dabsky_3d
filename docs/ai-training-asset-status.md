# Dabsky AI — real 3D asset research status

The user supplied 16 source files for Dabsky AI model training: four
Quaternius Standard MegaKit archives (362 glTF models), ten GLB files,
and two ZIP archives containing sword FBX assets.

**Verified licensing:** The four Quaternius archives each contain
License_Standard.txt explicitly stating CC0 1.0. All 362 models were
indexed into a license-approved metadata dataset. Individual GLB and
sword ZIP license permissions remain unverified and have been kept
outside the licensed initial training dataset. Do not commit raw private
3D files or include them in public datasets without rights clearance.

**Measured baseline:** trained a small, original CPU bag-of-words ridge
regressor on the normalized local-mesh dimension ratios of 362
captioned CC0 models. A seeded 290/72 train/holdout split achieved
mean absolute ratio error 0.220824, versus a 0.294891 average-ratio
baseline (~25.12% reduction). This is a weak caption-to-proportion
experiment, NOT a text-to-3D mesh generator. Accessor bounds omit scene
transforms; random same-pack holdout does not establish transfer to
different sources.

**Local research materials:** The ChatGPT project has a bundled archive,
dabsky-ai-training-v0.2.zip, containing the complete CPU research
scripts, source inventory, license-gated examples, trained metadata
regressor weights, metrics, data card, and seven passing tests. Raw
source models are deliberately not bundled.

This GitHub branch isolates research from Android main; the source
bundle has not yet been synced to GitHub. Do not claim remote automated
training or APK changes on the basis of this status file.
