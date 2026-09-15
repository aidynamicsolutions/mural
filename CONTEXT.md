# Mural Conversation UX Context

This context defines the language and boundaries for Mural's conversation surface, Settings, and local diagnostics.

## Language

**Meaning subtitles**:
A persistent preference that controls whether a translated meaning appears beneath assistant passages; it is changed in Settings, not in Talk.
_Avoid_: Hide meaning button, inline meaning control

**Word lookup**:
An on-demand contextual explanation opened by tapping an English word in an assistant passage; it is distinct from Meaning subtitles.
_Avoid_: sentence meaning, meaning toggle

**On-device conversation**:
An English practice session processed locally on the iPhone with Vietnamese support.
_Avoid_: local chat, offline chat

**On-device details & diagnostics**:
A collapsed secondary disclosure for technical local status and troubleshooting information, not primary conversation content.
_Avoid_: technical copy on the main Talk surface

**Inactivity timeout**:
A Mural timer that ends GPT-Live after 120 seconds without tracked activity to limit ongoing voice usage; it is not an iOS memory-reclamation mechanism and is removed from On-device conversations.
_Avoid_: RAM timeout, system resource timeout

**User message**:
A non-empty finalized spoken or typed learner turn that qualifies a session for saved history.
_Avoid_: assistant greeting, Help response

**Eligible transcript**:
A saved conversation containing at least one User message.
_Avoid_: assistant-only transcript

**System interruption**:
A closure forced by iOS, audio, or the connection rather than by user inactivity.
_Avoid_: inactivity ending

**New conversation**:
A user-invoked action after a conversation ends that clears the current Talk state for a fresh session without deleting saved history.
_Avoid_: reset conversation, conversation list

## Relationships

- An **On-device conversation** can show **Meaning subtitles** and **Word lookup**.
- **Meaning subtitles** are configured only in Settings.
- **On-device details & diagnostics** is secondary to the conversation surface and remains collapsed by default.
- An **Eligible transcript** requires at least one **User message**, whether spoken or typed.
- A **System interruption** may close a live session, but it does not make an assistant-only session eligible for history.
- On-device conversations have no automatic inactivity or elapsed-time ending and should keep the same session, return to Ready, and resume across backgrounding when possible.
- If iOS kills an On-device session, restore only eligible saved text and require a new session after relaunch.
- GPT-Live retains its existing cost-protection behavior, including its inactivity and maximum-duration limits and current background handling.
- **New conversation** clears the active Talk state but preserves eligible conversation history.
- Ending after only an assistant greeting returns to idle without Transcript, New conversation, or history.
- Ending after a **User message** keeps Transcript and New conversation available; there is no automatic 15-second reset.
- The Conversation limit setting is shown only for GPT-Live because it has no effect in On-device mode.

## Example dialogue

> **Dev:** "Why did the meaning button disappear from Talk?"
> **Domain expert:** "Meaning subtitles are a Settings preference. Word lookup remains a separate contextual action on an English word."
>
> **Dev:** "What does New conversation delete?"
> **Domain expert:** "It clears the current Talk state for a fresh session. It does not delete saved history."

## Flagged ambiguities

- "Hide meaning" previously referred both to sentence-level subtitles and to a Talk button. Resolved: the canonical preference is **Meaning subtitles**, configured in Settings.
- "New conversation" was mistaken for a new conversation-management feature. Resolved: it is the explicit post-end action for starting fresh while preserving history.
- Technical local state belongs in **On-device details & diagnostics**, not on the main Talk surface.
- The 120-second **Inactivity timeout** was an app-level voice-usage guard, not a response to iPhone RAM pressure.
- The **Inactivity timeout** and configurable conversation limit are removed for On-device but retained for GPT-Live.
- GPT-Live inactivity and maximum-duration clocks keep their existing behavior because active GPT-Live usage costs money; On-device backgrounding may pause and resume instead.
- A forced system, audio, or network closure with a User message saves the Eligible transcript and reports a recoverable System interruption, never inactivity.
- On-device backgrounding is a pause/resume lifecycle, not a conversation ending; GPT-Live keeps its existing cost-protective background behavior.
