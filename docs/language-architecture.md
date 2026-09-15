# How Mural keeps languages independent

A learner can be comfortable in Norwegian and new to Spanish. Mural therefore gives each conversation an immutable language ID and projects vocabulary, challenge level and capability observations from that language's evidence only. Identical word forms have different vocabulary keys across languages, so hiding or recalling a word in one language does not affect another.

Language-specific content lives in `Core/Languages/`. Each module defines its greeting, regional speech guidance, writing conventions, lemma rules, six teaching stages and cultural theme overrides. `LanguageRegistry` supplies the available choices to the UI. Spanish targets Spain; Norwegian uses Bokmål and an Eastern Norwegian voice target; French targets France; English accepts international usage with consistent spelling within a conversation. Regional pronunciation is a model instruction and still needs listening checks.

`TeachingPolicy` combines a module with the shared teaching rules. Voice, assessment, typed replies, help, word lookup, subtitles and current-topic search all use that policy. The audio transport and provider connection remain shared. A module can override selected theme IDs while inheriting the common conversation catalog.

Switching is allowed between conversations. It clears the current screen context and invalidates pending language-dependent work. Previous messages and sourced topic briefs are selected only from the active language. Learner replies can use a support language; the meaning-subtitle language is a separate preference. Vocabulary definitions remain in English, independently of subtitle language. Word identity uses language plus a case- and whitespace-normalized lemma, not the generated definition. Repeated words share recall evidence across conversations, with the latest definition and example displayed. Progress is word-level, not sense-specific. Legacy hidden-word IDs containing definitions still hide the corresponding word without rewriting saved evidence.

Archive version 2 stores language IDs explicitly. Version 1 records migrate to Norwegian, and their hidden-word keys gain the same namespace as new evidence. The SwiftData record itself retains its original identity. Before persisting that migration, the app saves a protected copy of the original payload in its Application Support/Mural directory. The API key stays in Keychain. Backups with unknown language IDs or mixed-language topic attachments are rejected without replacing existing data.

These are compiled modules. Adding one ships with an app update; there is no remote module download or extra service. Different scripts may require additional word-selection and layout work, and every new language needs a native-speaker teaching and pronunciation review.

See [how to add a language](add-language.md) for the implementation steps.
