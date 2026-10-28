# Cycle 36 — Offline-AI Quality Fix (P1) + OpenRouter Cloud Models (AgentA 2.1 Flash + AgentA Pro)

**Status: ACTIVE** — created 2026-10-28 by Adviser; RE-SEQUENCED same day per user directive ("this is also the main feature the offline ai — so focus on this first"): the offline-AI echo defect is now the FIRST execution phase, ahead of every OpenRouter phase. Cycle-34 closed (v1.6.0 shipped, CI green). Cycle-35 (name-fix) investigated (`REPORT_cycle35_readonly.md`) and waits; it opens at this cycle's close per the user's priority ruling.

## 1. Ground truth (verified 2026-10-28)

**Web research — search REQUIRED and performed.** External, time-sensitive facts (live model catalog, API shape, limits, reasoning semantics). Sources cited inline; nothing below is training knowledge.

### 1.1 OpenRouter models (live catalog `GET https://openrouter.ai/api/v1/models`, 464 models, fetched today)

| User display name (binding) | Exact model ID | Tier | Context | Max completion | Modality | Reasoning |
|---|---|---|---|---|---|---|
| **AgentA 2.1 Flash** (small/fast) | `thinkingmachines/inkling-small:free` | free (prompt `0` / completion `0`) | 1,048,576 | 262,144 | text+image+audio→text | enabled by default, default effort `high` |
| **AgentA Pro** (strong) | `thinkingmachines/inkling:free` | free (prompt `0` / completion `0`) | 1,048,576 | 262,144 | text+image+audio→text | enabled by default, default effort `high` |

- Both are Thinking Machines Lab MoE models: Inkling Small = 12B active / 276B total; Inkling = 41B active / 975B total.
- User mapping confirmed against the catalog's own scale: the small model is `inkling-small`, the strong model is `inkling` (the user's corrected mapping is the correct one).
- Paid variants exist (`thinkingmachines/inkling`, `thinkingmachines/inkling-small`, prompt `$0.000001`–`$0.00000045`/tok) — **out of scope**; the user ruled free tier.
- `reasoning.supported_efforts` includes `none`…`max` for both; `mandatory: false`. We deliberately send an explicit reasoning config (§4/P2 rationale).

### 1.2 OpenRouter API shape (live docs: OpenAPI 3.1 `POST /chat/completions` + auth + limits + reasoning-tokens pages)

- **Endpoint:** `POST https://openrouter.ai/api/v1/chat/completions` (OpenAI-compatible).
- **Auth:** `Authorization: Bearer <key>` — OpenAPI `securitySchemes.apiKey = { type: http, scheme: bearer }`. No required attribution headers (no `HTTP-Referer` requirement found in the spec).
- **Request (what we send):** `{ model, messages[], stream: true, max_tokens, temperature, reasoning: { effort, exclude: true } }`. `messages` is the only required field; `max_tokens` is deprecated in favor of `max_completion_tokens` (both share one budget) — the contract picks one and records it.
- **Response 200 (non-stream):** `{ id, choices[{ message{ role, content }, finish_reason }], created, model, object, usage }`.
- **Streaming:** `text/event-stream`, SSE `data: {...}` chunks (`object: chat.completion.chunk`, `choices[].delta.content`), sentinel `data: [DONE]`.
- **Errors:** `400/401/402/403/404/408/413/422/429/500/502/503/524/529` with body `{ error: { code, message, metadata? } }`.
- **Mid-stream errors (documented):** a rate limit hit after streaming starts arrives as an SSE event with `finish_reason: "error"` and a top-level `error` object — NOT an HTTP status. The Groq-style parser must handle this or a mid-stream 429 silently truncates.
- **Free-tier limits (verified):** `:free` variants → **20 requests/min** and **50 requests/day** for accounts that purchased <10 credits all-time (1000/day at ≥10 credits). `GET /api/v1/key` exposes `free_model_daily_requests`. A negative credit balance also errors free models (402).
- **Reasoning-token hazard (documented, load-bearing):** reasoning tokens count against `max_tokens`; if the budget is spent reasoning, the response returns `finish_reason: "length"` with **empty content**. Documented mitigations: raise `max_tokens`, lower `reasoning.effort`, and/or `reasoning.exclude: true`. Both inkling models default reasoning ON at effort `high`, so a naive Groq-style `max_tokens: 2048` request risks empty answers. Also documented: streaming reasoning arrives in `choices[].delta.reasoning_details` / legacy `delta.reasoning` — parsers reading only `delta.content` ignore it naturally.
- **Flutter client fit:** the existing `http` package (pubspec.yaml:19) suffices — no new dependency. SSE parsing, retries with `Retry-After`, and cancel already exist as patterns in `groq_service.dart`.

### 1.3 App integration surface (all file:line read today)

| Site | Evidence |
|---|---|
| Model registry | `lib/services/ai/ai_model.dart:1-27` — `enum AIModel { pollinations, groq, gemma }` + `displayName`/`description` extensions + `isImageGeneration` |
| Online dispatch | `lib/services/ai/online_ai_service.dart:40-74` — exhaustive switches over `AIModel` in `sendMessage`/`sendMessageStream`; constructor `(groq, pollinations, huggingFace)`; default preferred = `groq` (:13); `cancelActiveGeneration` covers groq+huggingFace only (:86-89) |
| Cloud-service template | `lib/services/ai/groq_service.dart` — Bearer + 30s timeout + 3 retries (`Retry-After` honoring, :32-52) + SSE parse (`data: `, `[DONE]`, malformed-chunk counting :54-67) + cancel (:69-80) + 20-msg history window (:82-96) + `max_tokens: 2048` (:140) |
| Facade | `lib/services/ai/ai_service.dart` — `isOnline` routing, `AiOutputGuard.stripPromptArtifacts` (:75) and `guardStream` (:86/:101) apply to ALL online models automatically |
| Config source | `lib/core/config/app_config.dart:14-24` — `String.fromEnvironment('GROQ_API_KEY')` etc.; **C1: dart-define is the ONLY config source** (:4-9); secret-suffix logging pattern (:98-110) |
| Chat UI | `lib/presentation/chats/chats.dart` — picker at :622-635 (`showModelPickerSheet`); appbar name via `currentModelName` (:666); image-model heuristic by enum name (:72-75) — new names must not contain `pollinations`/`image` |
| Picker sheet | `lib/presentation/chats/widgets/model_picker_sheet.dart:57` — **auto-enumerates every non-gemma `AIModel` value**; availability = `isOnline` for non-gemma (:102). New enum values surface with zero picker code changes |
| DI wiring | `lib/main.dart:241-256` (`GroqService()` constructed, injected into `OnlineAIService`) + `lib/cubit/app_providers.dart:25-68` (services exposed as providers) |
| Error mapping | `lib/core/utils/chat_error_classifier.dart:38-58` — groq/huggingface/pollinations branches + generic `api error`/`service error` catch-all; tests at `test/chat_error_classifier_test.dart` |
| CI secrets | `.github/workflows/build-apk.yml` — secrets → trimmed env (:158-164) → `--dart-define=GROQ_API_KEY=...` (:306-311); `.env.example` is documentation-only ("the app never reads it or any .env file", :1-5) |
| Suite baseline | `flutter test` green through cycle-34; `test/gemma_service_test.dart` + service-error tests exist; **no groq_service_test.dart** (Groq has no unit test file — OpenRouterService should not inherit that gap) |

### 1.4 Secrets posture (verified)

- Repo carries no keys in code: dart-define only (C1, `app_config.dart:4-9`), CI-injected from GitHub Actions secrets (`build-apk.yml:44`), `.env` git-ignored and never read.
- The OpenRouter key (`sk-or-v1-…09f8`) transited chat. It must never be written into the repo, plan files, logs, or commit messages in full. Rotation recommended at implementation time.

### 1.5 Offline-AI inference path (audit 2026-10-28 — the echo defect, evidence chain)

**Web research — search REQUIRED and performed** (echo is an external, version-sensitive behavior): MediaPipe LLM Inference Android guide (developers.google.com/edge/mediapipe/solutions/genai/llm_inference/android — raw prompt in / raw response out; maintenance-only, LiteRT-LM successor); fluttergemma.dev/docs/mediapipe + /docs/models + /docs/troubleshooting (the pinned plugin's own docs: `.task` = "MediaPipe applies each model's chat template internally"; ModelType table: Gemma 3 1B → `ModelType.gemmaIt`; official catalog asset = `litert-community/Gemma3-1B-IT`); HF API `litert-community/Gemma3-1B-IT` (gated `"auto"` — Gemma license acknowledgment + token required for download; contains `gemma3-1b-it-int4.task`); flutter_edge_ai issue #81 ("always repeating endless text from gemma3-1b-it-int4.task", 100% reproducible, maintainer closed with model-file/ModelType-mismatch guidance). Stack note: the app runs **flutter_edge_ai 1.11.4 + flutter_edge_ai_mediapipe 1.0.8** since cycle-7 (the "flutter_gemma 1.11.4" in the F20 record is the pre-migration name — repo renamed, plugin succeeded).

| Link in the chain | Evidence | Verdict |
|---|---|---|
| UI streaming path | `chats.dart:371-398` — assistant bubble filled only from yielded stream chunks; `onDone` falls back to accumulated buffer only | UI echo RULED OUT |
| History dedup | `gemma_service.dart:188-192` removes the trailing current-message duplicate before replay | double-add RULED OUT |
| Inference settings | `gemma_service.dart:104-110` — temp 0.3, topK 30, topP 0.85, seed 1, systemInstruction | sane, not echo-causing |
| ModelType | `model_download_service.dart:247,471` — `ModelType.gemmaIt`; plugin ModelType table prescribes exactly this for Gemma 3 1B | CORRECT |
| Template handling | `flutter_edge_ai 1.11.4` extensions.dart:67-69 — `.task`+`gemmaIt` → raw content, "MediaPipe handles templates"; mediapipe 1.0.8 `mobile_inference_session.dart:91-112` + `MediaPipeSession.kt:60-62` pass raw text to `LlmInferenceSession.addQueryChunk`; plugin docs: template applied internally per model bundle metadata | by-design, correct for an INTACT bundle |
| Model asset | `model_download_service.dart:68-69` — `https://huggingface.co/AfiOne/gemma3-1b-it-int4.task/...` — a THIRD-PARTY re-upload of the official `litert-community/Gemma3-1B-IT` file, fetched token-less to dodge the license gate. Echo/repetition on this exact file is the documented failure mode (issue #81) | **ROOT CAUSE (primary): the model asset** |
| Stale-copy trap | install() is idempotent, keyed on the URL filename — the AfiOne and official files share the name `gemma3-1b-it-int4.task`, so a URL-only swap would silently keep the broken copy (`model_download_service.dart:87-88` comment; plugin troubleshooting: "the installer does not fetch a file it already has") | fix MUST include a replace path |
| Replace lever | `FlutterEdgeAi.uninstallModel(String modelId)` is public (pinned source core/api/flutter_edge_ai.dart:965-985); `ModelReplacePolicy.replace` exists (model_specs.dart:28-33) but the public install builder hardcodes `keep` | migration = uninstallModel + reinstall via the existing gate |
| Token plumbing | `AppConfig.hfToken` EXISTS (app_config.dart:15,25; consumed by huggingface_image_service.dart:27); CI injects+trims+dart-defines HF_TOKEN (build-apk.yml:150,168,299,308); `.env.example:9` | NO new secret surface — thread the existing getter |
| System-instruction shape | `mobile_inference_session.dart:77-85` — `[System: …]\n\n` glued to the first user message for `.task` (plugin-designed behavior) | contributing prompt pollution on a 1B model; NOT the echo cause; backlog advisory F15 |
| Expected total prompt | raw text only — no `<start_of_turn>` structure is ever sent or (for the suspect bundle) applied; gemma3-1b-it on untemplated text degenerates to parroting the visible question | matches the screenshot symptom exactly |

## 2. Findings backlog (Level 3 — full ranked list, uncapped)

| # | Finding | Evidence | Impact / effort | Owner |
|---|---|---|---|---|
| **F1** | **Two cloud models missing from the picker.** User task: AgentA 2.1 Flash = `thinkingmachines/inkling-small:free`, AgentA Pro = `thinkingmachines/inkling:free`. | user directive; catalog §1.1; `ai_model.dart:1` | High / medium | middle-end (this cycle) |
| **F2** | **Mid-stream SSE error events unhandled by the existing parser pattern.** OpenRouter delivers post-headers 429/5xx as `finish_reason: "error"` + `error` object inside the stream; the Groq parser reads only `delta.content`, so such errors would render as a silent empty reply. | limits docs §1.2; `groq_service.dart:270-291` | High (correctness of error UX) / low | middle-end (in-scope, P3) |
| **F3** | **Reasoning-budget hazard → empty answers.** Both models default reasoning ON at effort `high`; reasoning counts against `max_tokens`; Groq-style `max_tokens: 2048` risks `finish_reason: "length"` + empty `content`. | reasoning docs §1.2; catalog `reasoning.default_enabled: true` | High (feature-killer if unhandled) / low | middle-end (in-scope, P3) |
| **F4** | **Free-tier quota UX.** 20 req/min + 50 req/day on the free tier; 402 also possible (negative balance). Classifier has no openrouter branch — errors fall into the generic bucket ("failed to respond"), hiding the real cause. | limits docs §1.2; `chat_error_classifier.dart:38-58` | Medium / low | middle-end (in-scope, P3) |
| **F5** | **Groq has no unit test file.** The new service must not inherit that gap: OpenRouterService gets a mocked-`http.Client` unit test. | glob `test/*.dart` — no `groq_service_test.dart` | Medium / low | middle-end (in-scope, P3) |
| **F6** | `OnlineAIService.cancelActiveGeneration` never cancels Pollinations (groq + huggingFace only) — pre-existing inconsistency, unrelated to this cycle's surface. | `online_ai_service.dart:86-89` | Low / low | backlog (future cheap cluster) |
| **F13** | **Offline AI ECHOES the user's question instead of answering (the app's MAIN feature).** Screenshot: "Who's doctor Jose Rizal?" answered by the question itself. Root cause: third-party model asset `AfiOne/gemma3-1b-it-int4.task` (§1.5) — same failure mode as flutter_edge_ai #81. Fix class: asset swap to official `litert-community/Gemma3-1B-IT` + token threading + stale-copy migration. | §1.5 evidence chain; `model_download_service.dart:68-69` | High (main feature broken) / medium | middle-end-light (**SELECTED — new P1, this cycle, FIRST**) |
| **F14** | Stale-asset migration UX: the one-time replace re-downloads ~0.5 GB through the existing install gate; no extra UI needed, but the marker must survive process death (SharedPreferences, not memory). | `model_download_service.dart:83-84`; plugin idempotency note §1.5 | Low / low | middle-end-light (in-scope, P1) |
| **F15** | System instruction reaches `.task` models as a `[System: …]` blob glued to the first user turn (plugin-designed for .task; native only on .litertlm). Prompt pollution on a 1B model; not the echo cause. Candidate upstream issue — do NOT change app-side without evidence. | `mobile_inference_session.dart:77-85` | Low / low | backlog (upstream advisory) |
| **F16** | `ChatSessionModel` naming + plugin storage naming still carry legacy "gemma" branding while the engine is flutter_edge_ai — cosmetic only. | `model_download_service.dart:70,112` | Low / low | backlog (future cheap cluster) |
| **F7** | `AIModel` registry is a hardcoded enum + multi-site exhaustive switches (dispatch ×2, extensions ×2). Fine at 5 values; a data-driven registry (id → endpoint/model/capability table) would collapse the pattern if a 3rd cloud provider ever lands. | `ai_model.dart`, `online_ai_service.dart:40-74` | Low / medium | backlog (deferred refactor) |
| **F8** | Client-bundled API keys are extractable from the APK binary. Accepted posture today (free-tier keys, user's own app). Real mitigation = Supabase edge-function proxy holding keys server-side. | `app_config.dart:14-24`; limits docs §1.2 | Low today / medium | backlog (security hardening — revisit if any key gains paid credits) |
| **F9** | Classifier's groq branch matches `groq api key not configured` literally; an OpenRouter key-missing message needs its own branch (the generic catch-all would mask "not configured" as "failed to respond"). | `chat_error_classifier.dart:38-40` | Low / low | middle-end (in-scope, P3) |
| **F10** | `chats.dart:72-75` + `model_picker_sheet.dart:165-168` image-model detection is a name-substring heuristic on the enum name. Constraint recorded: new enum names must avoid `pollinations`/`image` substrings. | `chats.dart:72-75`; `model_picker_sheet.dart:165-168` | Low (constraint only) | recorded (P3 constraint) |
| **F11** | Groq's fixed 30s timeout is tight for reasoning models with long answers; OpenRouterService sets a longer connect timeout (60s) while keeping the unbounded body-stream shape. | `groq_service.dart:11`, reasoning docs §1.2 | Medium / low | middle-end (in-scope, P3) |
| **F12** | `AppConfig.envLengths` exposes lengths for supabase/google only; adding the OpenRouter key length would follow the same never-log-value pattern (optional, debug-only). | `app_config.dart:210-214` | Low / low | backlog (optional nit) |

## 3. Objective

**Primary (user directive, "the offline ai — so focus on this first"):** the offline AI answers questions with REAL content instead of echoing them: the model asset is swapped to Google's official `litert-community/Gemma3-1B-IT` `.task` bundle, downloaded with the existing `HF_TOKEN` plumbing, and the stale broken copy is migrated out via the plugin's public `uninstallModel`. The Jose Rizal class of question gets a real answer offline.

**Secondary:** the chat model picker offers two new free cloud models beside AgentA Chatbot (Groq): **AgentA 2.1 Flash** (`thinkingmachines/inkling-small:free`) and **AgentA Pro** (`thinkingmachines/inkling:free`), served through a new OpenRouterService that mirrors the GroqService contract (streaming, retries, cancel, error hygiene) with OpenRouter-specific handling: reasoning config, mid-stream error events, free-tier error copy, and dart-define key injection. No change to the offline (Gemma) path beyond P1, the image path, or the default preferred model (`groq`).

## 4. Secrets ruling (Adviser decision — FINAL)

1. **OPENROUTER_API_KEY enters exactly like GROQ_API_KEY**: build-time `--dart-define` (C1: the only config source), CI value from a new GitHub Actions secret consumed by `build-apk.yml`, local dev via `--dart-define=OPENROUTER_API_KEY=...` on the command line; `.env.example` gains a documentation line; `.env` stays git-ignored and unread.
2. **The chat-transited key is burned-by-transit:** never record it in the repo, plans, logs, or commits; the user creates a FRESH key at implementation time (rotation), optionally with a credit limit cap, and enters it in GitHub secrets + local build commands themselves. No agent ever writes the key to disk.
3. **Client-exposure accepted explicitly:** a key bundled via dart-define is extractable from the APK. Accepted for a free-tier key in the user's own app — same posture as GROQ_API_KEY/HF_TOKEN. The server-side proxy alternative is recorded as F8 backlog, not built now.
4. **Hygiene requirements on the service:** never log or embed the key (follow `app_config.dart:98-110` suffix-only logging if any log is added); error messages never echo the key; CI trim step mirrors the GROQ pattern and never prints the value.

## 5. Phases

| Phase | Scope | Size (reason) | Check (reason) | Agent | Depends on | Status |
|---|---|---|---|---|---|---|
| **P1** | **Offline-AI echo fix (F13):** official model asset swap + `HF_TOKEN` threading + stale-copy migration + 401/403 copy + tests + `.env.example` line | light (2 code-adjacent files + 1 test; no new secret surface — `AppConfig.hfToken`/CI already exist; no schema change — marker in SharedPreferences) | EXPENSIVE (touches download-path behavior, state, error handling; the main feature) | middle-end-light | — | open |
| **P2** | `contracts/openrouter-ai.yaml` — the OpenRouter chat-completions contract for the two models + the internal dispatch contract (AIModel additions, wiring, error-copy table) | light (one new file, documentation-only) | CHEAP (no behavior; it is the record of record) | contractor | P1 | open |
| **P3** | OpenRouterService + full wiring: `app_config.dart`, `ai_model.dart`, `online_ai_service.dart`, `main.dart`, `app_providers.dart`, `chat_error_classifier.dart`, `.env.example`, `build-apk.yml`, new `openrouter_service.dart`, unit tests + classifier tests | heavy (~10 files, new network service + auth + error-handling redesign + CI config) | EXPENSIVE (touches behavior: network, state, error handling) | middle-end | P2 | blocked |
| **P4** | Security verification of BOTH secret paths: OpenRouter key + HF token — threat-model checklist, zero-leak greps (repo, logs, errors, CI output), rotation confirmations by user | light (verification-only; no code) | EXPENSIVE (gates on behavior evidence of error paths and secret hygiene) | middle-end-light | P3 | blocked |
| **P5** | e2e gate: gates re-run + full suite + regression sweep + live-catalog re-verification + offline-fix acceptance greps | light (run-and-evidence, no code) | EXPENSIVE (the once-per-plan user-path proof) | general (standing directive) | P4 | blocked |
| **P6** | Reviewer once (searches + commands below) → Adviser push approval → commit plan → push → CI gate watch → version-bump commit last | light | EXPENSIVE (the PASS gate) | reviewer → agent-push | P5 | blocked |

### P1 — Offline-AI echo fix (middle-end-light, light, EXPENSIVE)

Fix the main feature: the offline model must ANSWER, not echo. Ground truth in §1.5. Change surface:

1. **Asset swap** (`lib/services/ai/model_download_service.dart:68-70`): `_modelUrl` → `https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task` (official bundle; `gated:"auto"` per HF API — license-acknowledged token required). Keep `_modelType` as-is.
2. **Token threading**: both install chains — `installModel` (:247-254) and `ensureModelActive` (:471-477) — pass `token: AppConfig.hfToken` (getter EXISTS, app_config.dart:25; consumed the same way by huggingface_image_service.dart:27). `AppConfig.gemmaModelUrl` override keeps winning via `resolvedModelUrl` (:83-84).
3. **Stale-copy migration (the load-bearing step)**: the broken AfiOne copy and the official file share the filename `gemma3-1b-it-int4.task`, and install() skips an already-present file. Implement a one-time migration: a SharedPreferences marker (e.g. `model_asset_v2`) — when absent AND the model is present/ready, call the public `FlutterEdgeAi.uninstallModel('gemma3-1b-it-int4.task')` (pinned source core/api/flutter_edge_ai.dart:965-985), reset the DAO readiness flag (existing `setModelNotInstalled`), set the marker, and let the normal install gate re-download. Marker must be set BEFORE the uninstall so process death mid-migration never loops the download.
4. **401/403 copy**: `_friendlyDownloadError` (model_download_service.dart:368-392) maps UnauthorizedError/ForbiddenError to "The model source rejected the download." — for the gated-model flow this must guide the user: authorization required / model license must be accepted (never echo the token; keep the brand-free tone).
5. **Tests** (extend the existing model-download-service test file): token passed when configured (assert via `installOverrideForTest`); `_modelUrl` points at the official repo; migration marker semantics (absent → uninstall+reinstall path; present → no uninstall); 401/403 friendly copy.
6. **`.env.example:8`**: default `GEMMA_MODEL_URL` doc value → the official resolve URL, with a note that HF_TOKEN is required for it.

**User actions (governance-recorded, never agent-executed):** the user's HF account (the one behind the existing HF_TOKEN) must accept the Gemma license on `litert-community/Gemma3-1B-IT` once (auto-gated, instant). If the existing token lacks scope, the user creates a fresh read token and updates the GitHub secret themselves — the token never transits chat or agents.

**Device proof (advisory, non-gating — established cycle-6/7 precedent):** post-green, the user asks "Who's doctor Jose Rizal?" offline; a real answer is expected.

**STOP rules:** (a) if the pinned-source migration lever differs from `uninstallModel(String)` (e.g. modelId form rejected) → STOP, report; no manual storage-dir deletion. (b) if the user's device smoke on the OFFICIAL file still echoes → defect class is engine/template (MediaPipe 0.10.33 / plugin), not the asset → STOP and report; the next fix (plugin upgrade or Dart-side turn-template mitigation) is a different phase.

**Acceptance criteria (individually checkable):**
1. `grep -rn "AfiOne" lib/ test/ .env.example` → zero hits.
2. Both install chains pass `token:`; zero log statements or error strings reference the token; zero `hf_` literals in tracked files.
3. Migration: marker absent + model present → uninstall called, DAO reset, marker set, gate re-downloads; marker present → no uninstall (unit-proven).
4. `flutter analyze` exit 0; `dart format --set-exit-if-changed` 0 changed; full `flutter test` green (count vs baseline recorded).
5. Grep gates in the P5 e2e phase confirm the acceptance greps on the final tree.

### P2 — Contract (contractor, light, CHEAP)

Write `contracts/openrouter-ai.yaml` recording, as the single source of truth for P3:

1. **External API:** endpoint `https://openrouter.ai/api/v1/chat/completions`; auth `Authorization: Bearer <OPENROUTER_API_KEY>`; request `{ model, messages[], stream, max_tokens, temperature, reasoning: { effort, exclude: true } }`; response shapes per §1.2 including `delta.content`, `delta.reasoning_details` (ignored), `data: [DONE]`, mid-stream `finish_reason: "error"` events, and the error table (401/402/408/429/4xx/5xx) with the friendly-copy mapping.
2. **Model constants:** `thinkingmachines/inkling-small:free` → AgentA 2.1 Flash; `thinkingmachines/inkling:free` → AgentA Pro. Reasoning config: `effort: "low"`, `exclude: true`, `max_tokens: 4096` (documented mitigations for F3; both values leave ample room inside the 262,144 completion cap).
3. **Internal contract:** `AIModel` gains `openrouterFlash`, `openrouterPro` (names checked against the F10 substring constraint); display names "AgentA 2.1 Flash" / "AgentA Pro"; descriptions state cloud + free; `OnlineAIService` switch cases dispatch both to OpenRouterService with the model ID as parameter; `cancelActiveGeneration` extended; `AppConfig` gains `_dOpenRouter` const + getter + endpoint + the two model IDs; `OpenRouterService` exposes `sendMessage`/`sendMessageStream`/`cancelGeneration` matching the GroqService shape; `main.dart`/`app_providers.dart` construction sites; 60s connect timeout (F11); classifier branch table for openrouter errors (F4/F9); `.env.example` + `build-apk.yml` dart-define lines.
4. **Acceptance criteria:** every path, header, field, ID, and file:line in the contract is one verified in §1; a reader can implement P3 from the contract alone; no key value anywhere in the file.

### P3 — Implementation (middle-end, heavy, EXPENSIVE)

Build exactly the contract. Key requirements beyond the mechanical map: OpenRouterService is a structural sibling of GroqService (same history window, cancel semantics, malformed-chunk counting, `AiOutputGuard` compatibility — no changes to `ai_service.dart` are expected; flag if any become necessary); mid-stream error events raise a friendly error instead of ending the stream silently (F2); empty final content (`finish_reason: "length"` with no content) raises a friendly error (F3); unit test with mocked `http.Client` covering auth header, per-model ID routing, SSE parse incl. comment lines/`[DONE]`/mid-stream error, 401/429/402 mapping (F5); classifier branch + tests (F4/F9); CI lines mirror the GROQ trim + define pattern with the value never printed.

**Acceptance criteria (individually checkable):**
1. `flutter analyze` exit 0; `dart format --set-exit-if-changed` reports 0 changed.
2. Full `flutter test` green with new tests passing (count recorded vs baseline).
3. `grep -r "thinkingmachines/" lib/` shows exactly the two contract model IDs; zero other OpenRouter model strings.
4. Zero occurrences of the chat-transited key or `sk-or-v1-` literals in tracked files.
5. The picker sheet lists both new models (auto-enumeration, `model_picker_sheet.dart:57`) with the contract display names/descriptions, disabled when offline, enabled online.
6. `OPENROUTER_API_KEY` absent from every log statement; error strings never contain key material.

### P4 — Security verification (middle-end-light, light, EXPENSIVE)

Verification-only against BOTH secret surfaces: the OpenRouter key AND the HF token now threaded into the offline download path. (a) grep repo + recent diff for key/token material (`sk-or-v1-`, `hf_` literals); (b) confirm error/log paths cannot emit either secret (walk every string built from config — including the new P1 download-path errors); (c) confirm CI yml trims but never prints; (d) the user confirms the fresh rotated OpenRouter key is in GitHub secrets AND the HF token in use is license-authorized for the model repo (chat confirmation; chat-transited secrets are treated as burned). **STOP rule:** any leak path found → report back, do not patch within this phase (a fix sub-phase opens).

### P5 — e2e gate (general, light, EXPENSIVE)

Once per plan, on the general agent per the standing directive: re-run all gates, full suite, regression sweep over standing flows, re-verify the two model IDs against the live catalog (re-fetch `GET /api/v1/models` and grep — free tier confirmed, IDs unchanged), and re-run the P1 acceptance greps (AfiOne gone, official URL present, both install chains carry `token:`). A live network call from the app is NOT required (the user's device proof remains advisory, like prior cycles' device smoke tests).

### P6 — Reviewer + push (reviewer → agent-push, light, EXPENSIVE)

Single-pass Reviewer with the searches and commands below; on PASS the Adviser approves push; commit plan per §9 (offline-fix commit FIRST, then implementation, docs, version-bump LAST — `chore(release): bump version to 1.7.0+1`, Adviser-authorized one-liner). Exclusions: `.opencode/` churn, `analysis_options.yaml`, never root-wide add. After push: CI green required; the user cuts `v1.7.0` from the push HEAD per the established release process.

## 6. STOP rule

If any phase discovers the live integration surface differs from this plan's ground truth (model IDs missing/renamed from the catalog, API shape rejection — e.g. `reasoning` rejected for these models, endpoint/auth changes), STOP and report to the Orchestrator. No improvisation, no silent parameter drops. Phase-level STOPs: P1 (a) migration lever mismatch, (b) official-asset echo persists on the user's device — defect class becomes engine/template, new phase; P3 contract-vs-ground-truth divergence; P4 leak-path finding; P5 red suite.

## 7. Orchestration rule

One phase at a time, in P1→P6 order; the Orchestrator delegates the named agent with the plan path and reads results before the next delegation. All phases → e2e once (P5) → Reviewer once (P6). Termination timeouts apply per the standing disciplines. Incremental-writing applies to code agents' artifacts. If a delegation contradicts this file, the file is authoritative — stop and report.

## 8. Version bump decision — MINOR `1.6.0+1 → 1.7.0+1` — FINAL

New user-facing feature (two new selectable AI models) plus a defect fix on the main offline feature, shipping in this cycle's single push. Per `docs/versioning.md` §2 and precedents (cycle-26 → 1.3.0, cycle-31 → 1.5.0, cycle-34 → 1.6.0): bump commit LAST in this cycle's push; tag `v1.7.0` cut by the user from the push HEAD after CI green. The push agent must not re-decide.

## 9. Push guidance

Push only after Reviewer PASS + Adviser approval. Commits: (1) `fix(ai): replace offline model asset with official litert-community Gemma3-1B-IT + HF token download + stale-copy migration (C36)` (all P1 files), (2) `feat(ai): add OpenRouter cloud models — AgentA 2.1 Flash + AgentA Pro (C36)` (all P3 files + contract), (3) `docs(plans): record cycle-36 governance` (plans/), (4) `chore(release): bump version to 1.7.0+1 (C36)`. Never stage `.opencode/`, `analysis_options.yaml`, or the repo root wholesale. Red CI keeps the plan active and opens a fix phase.

## 10. Reviewer searches + commands

**Web searches (mandatory):**
1. OpenRouter free-model rate limits (verify 20/min + 50/day tiers still current).
2. OpenRouter streaming errors (`finish_reason: "error"` mid-stream shape) — verify the documented handling.
3. OpenRouter reasoning tokens (`max_tokens` interplay, `exclude`/`effort` semantics) — verify unchanged.
4. `litert-community/Gemma3-1B-IT` — verify `gemma3-1b-it-int4.task` still published at the pinned revision and the repo's gating/token status (HF API).
5. flutter_edge_ai issues — echo/repetition reports on `gemma3-1b-it-int4.task` (status of #81; any 1.11.4+ release notes addressing template handling).
6. flutter_edge_ai public uninstall/replace API (`uninstallModel`) — verify the implemented lever is the documented one.

**Commands:** `flutter analyze` (exit 0); `dart format --set-exit-if-changed --output=none .` (0 changed); `flutter test` (green, count recorded); `grep -rn "sk-or-v1-" --include="*"` and `grep -rn "hf_" --include="*"` on tracked files (zero hits); `grep -rn "AfiOne" lib/ test/ .env.example` (zero hits); `grep -rn "OPENROUTER_API_KEY" lib/ .github/ .env.example` (exactly: app_config const+getter, build-apk.yml secret/trim/define, .env.example doc line); `grep -rn "thinkingmachines/" lib/ test/` (exactly the two contract IDs); `grep -rn "litert-community/Gemma3-1B-IT" lib/ .env.example` (exactly: model_download_service URL, .env.example doc line).

## 11. Governance log

| Date | Entry |
|---|---|
| 2026-10-28 | Plan created `active`. Live-catalog + docs verification complete (§1); level call **Level 3** (secrets + new network AI surface + >5 files); secrets ruling §4 (dart-define, rotation, no repo writes); version bump MINOR 1.7.0+1 FINAL. Cycle-35 (name-fix) opens at this cycle's close per user priority. |
| 2026-10-28 | **User re-prioritized (3 directives): the offline AI is the app's MAIN feature and echoes questions instead of answering — fix it FIRST, before the cloud-model phases.** Adviser audited the full offline inference path (§1.5, file:line evidence); web research REQUIRED and performed (MediaPipe guide, plugin docs §1.5, HF API, flutter_edge_ai #81). Root cause: third-party model asset `AfiOne/gemma3-1b-it-int4.task` (token-less mirror of the license-gated official file; echo/repetition is its documented failure mode). App-side usage verified CORRECT (`.task`+`gemmaIt`+raw messages per plugin docs; UI echo ruled out). Plan re-sequenced: new P1 = offline fix (middle-end-light, light size, EXPENSIVE check); OpenRouter phases shifted P2-P6; P4 security verification now covers the HF token; no new secret plumbing needed (`AppConfig.hfToken` + CI HF_TOKEN already exist). Zero work in flight (P1-contract was staged, not delegated) — re-sequencing clean. |
