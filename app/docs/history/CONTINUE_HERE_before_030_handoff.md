# Current handoff — 2 October 2026, vision improvement active

The latest user challenged misleading progress percentages and asked for better models, data, training and performance outside training. Work is active; no user phone test is required to continue local model improvement. The 95% figure referred to first-test-build preparation, whereas 30% referred to the full universal product. Do not repeat those incompatible measures as one completion score.

## Current experiment checkpoint

- Updated experimental local-test app is now0.3.0+3 with AR42asset63b683c7. Flutter201tests and whole-appanalysis PASS. Platformagent is rebuilding/testingiOS/Android/web and updatingmanifests; read BUILD_VALIDATION/PLATFORM_CHECKPOINT for actualcompletion. iOS17iPhone13Pro simulator actual14tilephototest +blank/reopen alreadyPASS (317msphoto,0.8829minscore; simulatoronly). No publicdistribution/licensegrant is inferred.
- Pretrained comparisons completed: nano/small/medium YOLO11, AR42 YOLOv8n, ViT. AR42 improved the old development photos from2/7 to6/7 exact14tile regions. On a different published156image dataset it scored1211correct/339extra/378missed (78.1%precision/76.2%recall), compared with current nano24.4%recall. High-confidence mistakes remain. See VISION_CANDIDATES_20261002.md. Old public photos are development only; unknown upstream overlap prevents guaranteed unseen-data claims.
- Acquired and SHA-verified RF100-VL Mahjong v2:2135images/15037boxes. Duplicate-aware grouping yields1619train/360dev/156internal_test. All34classes; physical tile-set/session identity unknown.69 original cross-split groups were promoted out of test. See VISION_DATA_AUDIT.md.
- Source lock `vision/validation/rf100vl_internal_test_v1.lock.json` verified before fitting/testing. Validation/provenance helpers have27tests. Pretrained evaluation consumed the156test images for future adaptive changes; later tuning on this dataset must be labelled follow-up diagnostic, not a new untouched test.
- Own MobileNetV3Small classifier completed12fixedepochs in167seconds using MacGPU, general ImageNet initialization.13937train/3468dev crops includingbackground. Bestepoch12:96.86%devcrop accuracy,96.21%macrorecall. SelectedcheckpointSHA3881dd8444e934c0cb2ff9e8d39f97e65ace09f34e0d66ed7ada3ae31f438c78. `vision/runs/mobilenetv3_rf100_v1/`. Allhyperparameters/selection frozen before externalresults. Its frozenreservedcrop evaluation completed:1849/1900correct97.32%,1537/1588ordinaryfaces96.79%,131/156sourceshaveallevaluatedcropscorrect. This usestrueboxes, NOThanddetection. Oneinternaltesttinyannotationexcludedandreported. Firstsandboxattemptfailedsharedmemory; approvedCPUretry passed.
- Crucial negative result: classifier gets117/138 on truefacecrops in old Commons photos; replacing detector labels worsens completehand results (AR6/7 becomes2/7). Do not put classifier in app or describe dev97% as scanner accuracy. Results in commons_development_pipeline.json.
- Agent vision_eval is RUNNING new20epoch YOLO11n detector from generic official COCO weights, groupedtrain/devonly, physicalrotation/no mirroring. Active session30229; output vision/training/detector_runs/full20/, detector_full20.log. Epoch3completed~601seconds; maytake70–80minutes total. Userauthorizedlongwork, MacACcharging, no pause. Savebest/last each epoch. Afterinterruption resume via .venv/bin/python vision/training/detector_train.py --resume withMPSapproved. EarlyvalidationNMS-time-limitwarnings aretracked; finaldeterministicCPUdecoder evaluationhasnotimelimit. FollowupRF100evaluation isnotfreshuntouchedtest. Do not stopmerelybecausefirstbuildisready.
- rules_tests agent completed source/evaluator safeguards andAR42appmigration. platform_build agent owns actualnativechecks/builddocs/manifests now. Newrealbroadcastvideo acquired:239frames/8sec,20manuallypinned13tileframes. AR225/260identitymultisetmatches vsbaseline199/260; BOTH0/20exactrows. ActualDartgate replay rejectsallUIcountsanddiagnostic13; reports vision/video_candidates/*.json. SourceCC BY3.0, realvideo—not duplicatedstills. All state lives in files; original train/ untouched.

## Next steps

1. Classifier complete including6.23MBONNX/35realcropTorchparity. Keep negativecross-sourcefullpipeline result, do notdeployclassifier.
2. Finish or checkpoint explicitly the new detector training; evaluate/export parity and determine whether it actually improves cross-source photos. Preserve original negative reports. Do not claim a dataset is unseen by pretrained models without evidence.
3. AR42sourceisalreadyintegratedforlocalresearchwithnotices; keepitsnewtests andfinishnative/artifactrebuilds. Publisherrightsremainunresolvedforpublicrelease. Laterowntraineddetector mustbecomparedbeforeanyreplacement. Current201testsandwholeappanalysispass; nativeAndroid/profilebuilds pendingplatformagent.
4. User-facing report: clearly separate test-build readiness, implemented rule coverage, actual vision results, and later physical-phone camera/latency/heat validation. Further rule families are still unfinished.

## Historical battery-pause snapshot

The user asked to wrap up immediately because the Mac battery was nearly empty. Work is intentionally paused until the user says **continue**. Do not restart builds, emulators or servers before that request.

## User's outstanding objective

Deliver an Xcode-testable iPhone app (and Android version) with continuous local camera scanning → stable recognition → explicit confirmation → editable hand/calculation, locally saved preferences, researched scoring/payment rules, and real online image/video testing. They originally want many common rule families and configurable house conventions. Do not claim that all regional rules or reliable vision are finished.

## Latest completed source

- Flutter app `app/`, version **0.2.0+2**, rules engine **0.1.1**.
- Live camera replaced photo picking. No upload, saved frame/video or microphone access. iOS BGRA and Android YUV plane decoding; orientation and central 3.2:1 guide; single inference in flight, requested capture 15 fps, selected observations at most about 3/sec.
- Confirmation requires five matching observations over >=1.2 sec, selected count (2/5/8/11/14/17), all model confidences >=.80, legal tile multiplicities, row arrangement and stable positions relative to both previous and initial observations. UNKNOWN blocks confirmation. Expiry, rotation, backgrounding and tab exits reset it. Confirmation opens editable hand/context.
- Permission retry, stream cancellation before disposal, delayed initialization cleanup, native camera errors, incompatible preview/frame aspect rejection, and detector resource-release/retry/concurrent shutdown fixes are implemented.
- `shared_preferences` persists rule settings and immutable saved hand/result snapshots locally. The existing 32 storage tests plus app settings restart tests pass.
- Only HK and an explicitly partial Taiwanese16 house preset are executable. Rules audit fixed custom-score winning-tile allocation, impossible consecutive open kongs, structurally impossible HK responsibility and initial flower replacement with heavenly win. Many families/event-history rules remain unimplemented: read `docs/RULES_READINESS.md` and `SCORING_IMPLEMENTATION.md`.
- Current ONNX asset: `app/assets/models/mahjong-yolo11n-v2-2b1adbdb.onnx`; SHA256 `2b1adbdb6f395eba7ce755f87672c8a4275d6eeae68d26c5206ae6a89f4e628a`. 38 classes, UNKNOWN index34 => -1, redfives35–37. Export parity verified on ten real regions. See manifest/notices for provenance and model terms.

## Verification already done; do not restart indiscriminately

- Final `scripts/flutter.sh analyze`: **no issues**.
- Final `scripts/flutter.sh test --coverage`: **196 tests passed**. Log `/tmp/mahjong-tests-final.log`; analysis log `/tmp/mahjong-analysis-final.log`. These may disappear after restart; durable totals recorded in `BUILD_VALIDATION.md`.
- Counts: 71 domain, 18 preprocessing/decoder, 38 camera/stability, 12 detector lifecycle, 32 storage, 12 general widgets, 12 live-camera widgets, 1 actual-public-video replay. Includes 6,000 oracle structures, 1,000 metamorphic hands, 9,600 payment combinations and 200 temporal sequences.
- Five Python evaluator matching/boundary tests pass.
- Final refactored V2 detector passed actual iOS17 iPhone13Pro simulator native loading/repeat/dispose/reopen: about258ms first and106ms warm. These are simulator times.
- Android15 ARM64 emulator with16KB pages passed actual YUV camera→model→stop/reopen integration (640×480, rowstrides640/320/320, pixelstrides1/1/1). V2 about902/723ms; emulator-only.
- Final Android debug and optimized development-signed APKs built: arm64~56.2MB, armv7~48.3MB, x86_64~61.5MB. Version codes normalized across ABI builds; camera optional flag explicitly overridden false.
- Final simulator normal app build passed. Final unsigned Profile physical-phone build also passed just before pause (80.2MB); see `PLATFORM_CHECKPOINT.md` for exact status.
- Direct actual `Runner.xcworkspace` Profile xcodebuild succeeded on an earlier source revision; final-source rerun status must be read from platform checkpoint rather than assumed.
- Final browser rebuild may still be pending (browser is manual/scoring only).

## Real online vision results

See `docs/ONLINE_VISION_EVALUATION.md` and `VISION_EVALUATION.md`.
Seven licensed Commons photographs, ten fixed regions,138 tiles: V2 117TP/8FP/21FN (93.6% precision,84.8% recall), exact2/7 complete14tile regions (2/8 including13tile row), versusV1 1/7. Small correlated model-selection diagnostic; upstream training overlap unknown. No photo meets .80 minimum confidence + count prerequisites.
550 actual frames from a CC-BY YouTube-origin tile-carving documentary mirrored on Commons were evaluated; the actual Dart gate replay across all six counts accepted none. This is domain/rejection footage, **not a successful hand-scanning video benchmark**. No dependable live hand lock or physical-phone speed has been demonstrated. Real iPhone hand video/testing is still required. Source media/annotations/hashes and scripts are retained in `vision/`.

## Resume sequence

1. Read this file and `docs/PLATFORM_CHECKPOINT.md` if present. Do not redo completed model research or all passing tests without a new code change.
2. Finish only the outstanding final-source native/Profile workspace verification, normal app launch, actual Android live preview geometry check and screenshots. Check `FLUTTER_TARGET=lib/main.dart` after any integration test.
3. Complete/update `docs/BUILD_VALIDATION.md` and `TEST_ON_PHONE.md` with observed artifact status. BUILD currently documents tests and limitations but final artifact table is not yet fully confirmed. Its iOS timing paragraph still needs final258/106ms values if not already updated.
4. Final user handoff: Xcode workspace, **Runner iPhone Test** scheme (Profile, no attached Flutter debugger), select their Apple development team + iPhone13Pro, Run. Root `Open in Xcode.command` is a double-click helper. Do not select a team or install on their physical phone without a relevant request. No App Store/TestFlight upload was authorized.
5. Clearly answer: continuous camera now implemented; preferences local; test build ready after pending checks; **not all rules are done**, and model accuracy remains experimental. Ask for a short known-hand iPhone clip/test feedback for further vision work when appropriate.

## Paths and tooling

Workspace `/Users/samuel/Documents/leisure/mahjong vision`; original `train/` untouched. No root Git repository; changes are saved in files.
- `.tools/flutter`: Flutter3.47.6/Dart3.13.5; `scripts/flutter.sh` sets process-local Xcode/Java paths. Often requires approved unsandboxed access for tool caches/network.
- Xcode `/Applications/Xcode.app`; do not change global Xcode selection. `scripts/open-xcode.sh phone` configures main/Profile and opens workspace. `scripts/verify-xcode.sh` builds same actual workspace/scheme unsigned. `scripts/build.sh` supports ios-simulator/ios-device/android/android-test-release/web.
- Temporary path_provider_foundation2.5.1 pin is deliberate to avoid a newer hook losing DEVELOPER_DIR.
- `app/ios/Runner.xcworkspace`; signing remains user-controlled. Targets iOS16+, AndroidAPI24+.
- Simulator13Pro UUID `2D55114D-7797-4E4A-97AF-8963BED88DF8`; Android test AVD `Medium_Phone`/emulator5554. Shut down only the devices started for this task. Physical iPhone has not been modified.
- Python `.venv`; use curl for remote fetches if urllib SSL fails.
- Old port8080 Python web preview and our Android emulator were stopped on pause. The task-created iPhone13Pro simulator was also shut down. No build remains running.
- Subagents: platform_build owns platform/scripts/build checkpoints; rules_tests completed detector/domain audits; vision_eval completed evaluation. All substantive source is shared and saved.
