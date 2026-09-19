# Bilingual Whisper adapters: feasibility, data and training

Research date: 2026-09-17. This is a research proposal, not a trained model or a cleared training dataset. It accompanies the [current-model-first plan](iphone17-vien-research-plan.md).

## Explanation in ordinary language

Think of the recognizer as a student who already understands English and Vietnamese but sometimes treats a mixed sentence as though it must stay in one language. Bilingual examples teach it that a switch is normal and that the transcript should keep the words actually spoken.

A LoRA adapter is a compact collection of learned adjustments to that particular student's knowledge. It is not a Vietnamese dictionary, an English/Vietnamese text replacement list, a translation service or a second full recognizer. Most original weights stay frozen during training; small matrices learn changes to selected layers. Those changes can be merged into the original weights before export [R1, R2]. Mural already deploys such a merged model, so removing an extra adapter runtime would not solve its present 3 GB footprint.

Different-sized students need their own learned adjustments. The **training approach and permitted data** can be reused; the **same trained tensor values** are not automatically transferable.

## What the existing adapter contains

The actual adapter configuration names `vinai/PhoWhisper-large` as its base. It specifies LoRA rank 32, alpha 64, dropout 0.1 and targets `q_proj`, `k_proj`, `v_proj`, `out_proj`, `fc1`, and `fc2`. `use_qalora` is false [R3]. These training settings do not describe the separate Core ML PAL8 deployment format.

In mathematical terms, a targeted weight matrix becomes `W + (alpha/r) * B * A`. The small learned matrices must match the base layer's input/output dimensions [R1, R2]. A matching shape is necessary, not proof that adjustments learned around a different base's numerical weights will improve it.

## Which models can receive a newly trained adapter?

| Backbone | Configuration distinction | Can train a fresh bilingual LoRA? | Reuse the existing large adapter unchanged? |
| --- | --- | --- | --- |
| Current PhoWhisper-large | Large-v2 lineage; width 1280, 32 encoder / 32 decoder layers, 80 mel bins | Yes; current case | Only with the matched base/revision and verified merge |
| PhoWhisper-small / multilingual Whisper-small | About 244M parameters; width 768, 12 / 12 layers | Yes | No direct compatible large-adapter replacement |
| PhoWhisper-medium / multilingual Whisper-medium | About 769M; width 1024, 24 / 24 layers | Yes | No direct compatible large-adapter replacement |
| Whisper-large-v3 | About 1.55B; large-width/depth, 128 mel bins and changed language-token inventory | Yes | Many targeted shapes may fit, but that does not validate transfer across learned bases; train against v3 |
| Whisper-large-v3-turbo | About 809M; 32 encoder / 4 decoder layers, 128 mel bins | Yes | No complete layer-for-layer transplant; train against Turbo |

Sources: official model catalogue and actual configs [R4-R9]. There are no official multilingual `small-v3` or `medium-v3` checkpoints in that catalogue; the relevant names are `small`, `medium`, `large-v3`, and `large-v3-turbo`. PhoWhisper-small/medium are additional Vietnamese-adapted starting points, not smaller copies of large-v3.

Large-v3 is not a memory reduction simply because it is newer. Turbo's short decoder is a more direct latency hypothesis, while small provides a much larger parameter reduction. These are reasons for experiments, not promised bilingual quality or iPhone performance.

Mural hard-codes the current large model's tensor/tokenizer contracts. A smaller/v3 model needs a matched export, tokenizer, mel frontend, dimensions, suppression and cache configuration. Do not swap directories under the existing 1280-wide/80-mel contract or ignore mismatched adapter keys.

## The original adapter's training dataset: not yet located

The publisher's card refers to a Vietnamese-English speech corpus and a KES 2026 paper, but does not provide a dataset download, a reproducible split manifest or corpus-use terms. Its bibliographic author fields are placeholders [R10]. Searching the title/author account did not establish an accessible original corpus. This is **unverified availability**, not proof that the data do not exist.

The adapter's declared CC-BY-4.0 license is not a license grant for an unlinked speech corpus. Before a training run, obtain the exact audio/transcript release, revision, permitted commercial training/derived-weight use, consent/provenance and train/dev/test separation. Keep base-model, adapter and dataset obligations distinct.

Suggested author inquiry, not sent:

> We are evaluating a commercial, on-device English/Vietnamese language-learning app. Could you share the corpus/release used for your PhoWhisper code-switching LoRA, its audio and annotation licenses, and whether training and distributing derived ASR weights commercially is permitted? We also need speaker/source-disjoint split manifests, the training script/environment and language-prefix/normalization settings. Please identify any restricted recordings or resources that must be excluded.

## Independent evidence: small-model adaptation already works in a related domain

The LREC 2026 ViMedCSS study reports a 34.57-hour medical code-switching corpus. Its PhoWhisper-small test WER changes from **36.31 to 27.13** with LoRA, and code-switched-region WER from **62.55 to 30.26**. On its harder unseen-term split the latter remains **60.71**, so generalization is far from solved [R11, Tables 4-6].

This supports technical feasibility for a small bilingual adapter. It is not the same corpus as the existing adapter's claimed corpus, not ordinary learner conversation, and not an iPhone benchmark.

| Data lead | What is actually established | Commercial-training disposition |
| --- | --- | --- |
| Original `rinhoooo` training corpus | Described but no verified accessible release/rights obtained | Hold pending author/release clarification |
| `tensorxt/ViMedCSS` | Public audio/transcript release; medical English insertions in Vietnamese | Metadata says CC-BY-4.0, but the card separately warns about YouTube/dictionary rights and asks users to verify commercial use. Resolve this before using it for Mural training [R12]. |
| CanVEC | Published natural-conversation Vietnamese-English corpus: approximately 10 hours, 45 bilinguals; author repository has an access process | Described for research; confirm audio access and commercial/derived-model permission, not just text availability [R13, R14]. |
| New consented conversational recordings | A proposed alternative, not collected | Obtain explicit appropriate consent/rights and document sources before use |

ViMedCSS's current HF card lists **15,818 rows / 32.64 hours**, whereas the paper reports **16,576 / 34.57 hours**. Pin and audit the actual release rather than assuming downloaded data reproduce the published benchmark [R11, R12]. No corpus has been downloaded or commercially cleared by this research.

## Proposed training experiment after data clearance

Use one reproducible training/evaluation pipeline with a separate adapter for each pinned base. Start with PhoWhisper-small, then decide from evidence whether medium or Turbo merits the next run. Do not launch all sizes or a paid job before resource profiling and budget approval.

### Data and held-out evaluation

Use audio paired with human-checked, verbatim mixed-language transcripts. Do not translate the Vietnamese, correct learner grammar, or substitute teacher guesses for ground truth. Include both switch directions, multiple switches, monolingual English/Vietnamese, accents, hesitation, self-correction, short words and background noise. Medical insertion data alone are insufficient coverage for Mural's target conversation; that is an experimental design concern, not a ban on using licensed supplementary data.

Split by speaker and conversation/source recording before making crops or augmented variants. Keep calibration/development/test distinct; include unseen words and speakers. Retain the existing 21 recordings only as regression evidence, never as training or calibration data. Because these recordings have already influenced engineering choices, do not call them an untouched generalization test.

### Model training and controls

Proposed starting configuration: rank 32 / alpha 64 with the existing target-module set; treat it as a starting hypothesis, not an optimum for every backbone. Profile a short forward/backward run first, then choose microbatch, accumulation, mixed precision and gradient checkpointing from measured memory. Validate several initial predictions/labels and special-token handling before a longer run.

Train `transcribe` targets containing both languages. Use the base's own processor/tokenizer. Specify the language-control-token policy explicitly and test it against deployment's automatic detection; do not feed the test's true language or expected vocabulary into inference to manufacture an improvement. A new language token is not inherently required to write both languages.

Monitor both mixed and monolingual held-out errors, not training loss alone. Stop from validation behavior; report results against the exact unadapted backbone and current merged CS model. Optionally use the large model as a teacher on separately permitted training audio, with human review and an independent test set; do not distill its known mistakes as unquestioned labels.

PEFT documents a Whisper LoRA/quantized-base, single-GPU training workflow [R15]. That establishes an implementation route, not a promised GPU size, cost or runtime for Mural. Training-time int8/4-bit base loading, LoRA learning and deployment-time PAL8 are separate operations. Profile the selected stack; do not copy a historical tutorial's package versions or monolingual prefixes blindly.

### Deployment gate

Merge into the exact unquantized matching base using a validated high-precision merge, compare merged versus unmerged outputs, and export with the correct shape/tokenizer/frontend. Then evaluate FP16 and PAL8 separately with unchanged decoding. Preserve source/adapter/export/runtime hashes and versions. Do not claim that widening already quantized weights restores the original precision.

Run the physical iPhone benchmark only after host correctness checks. Keep one recognizer resident, preserve rollback assets, and measure preparation/first-turn/warm-turn/peak-memory behavior in the real tutor/TTS app. Select a size by the measured accuracy/resource tradeoff, not age, likes, desktop throughput or parameter count alone.

## Primary sources

[R1] LoRA paper: https://arxiv.org/abs/2106.09685

[R2] PEFT LoRA reference: https://huggingface.co/docs/peft/v0.21.0/package_reference/lora

[R3] Existing adapter config: https://huggingface.co/rinhoooo/phowhisper-large-vien-cs-asr/blob/main/adapter_config.json

[R4] Official Whisper model catalogue: https://github.com/openai/whisper

[R5] PhoWhisper-large config: https://huggingface.co/vinai/PhoWhisper-large/blob/main/config.json

[R6] PhoWhisper-small config: https://huggingface.co/vinai/PhoWhisper-small/blob/main/config.json

[R7] PhoWhisper-medium config: https://huggingface.co/vinai/PhoWhisper-medium/blob/main/config.json

[R8] Whisper-large-v3: https://huggingface.co/openai/whisper-large-v3

[R9] Whisper-large-v3-turbo: https://huggingface.co/openai/whisper-large-v3-turbo and https://huggingface.co/openai/whisper-large-v3-turbo/blob/main/config.json

[R10] Existing adapter card: https://huggingface.co/rinhoooo/phowhisper-large-vien-cs-asr

[R11] ViMedCSS, LREC 2026: https://aclanthology.org/2026.lrec-1.445/ ; final paper: https://aclanthology.org/2026.lrec-1.445.pdf

[R12] Actual ViMedCSS dataset card and rights caveat: https://huggingface.co/datasets/tensorxt/ViMedCSS

[R13] CanVEC paper: https://aclanthology.org/2020.lrec-1.507/

[R14] CanVEC author repository/access: https://github.com/Bak3rLi/CanVEC

[R15] PEFT Whisper int8/LoRA example: https://huggingface.co/docs/peft/main/task_guides/int8-asr
