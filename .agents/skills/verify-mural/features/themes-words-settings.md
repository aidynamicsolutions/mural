# Themes, words, and settings

## User outcome

The learner can choose a conversation theme, move between Talk, Themes, and Words without losing the choice, switch learning languages, and reach secure key/settings and license information.

## How to get to it

Use the preview app on the selected simulator. For visual fixtures:

Use `--preview --screenshot=themes` or `--preview --screenshot=words` **inside a single bounded interaction script**, as described in the parent skill. No standalone boot/launch/mirror calls between tool turns. The focused Make command below handles build, exact ownership, default profile, results and verified shutdown.

Run the focused native checks when the changed behavior is navigation, language selection, settings, or notices:

```sh
make agent-verify SIM_UDID="$SIM_UDID" \
  TESTS='testThemeSurvivesNavigationToWords testThemeSearchFiltersLocally testLanguageSwitchUpdatesGreetingThemesAndWords testSettingsOfferSecureKeyEntryAndBackups'
```

Use the exact test target spelling from `xcodebuild -list` if Xcode reports an unknown selector. The reliable settings test names are also listed in `UITests/MuralUITests.swift`; run `testSettingsOfferSecureKeyEntryAndBackups` and `testSettingsKeepLicensesInNoticesWithoutTransportDetails` separately when needed.

## How to drive it

1. Launch `--preview` and tap Themes.
2. Select the `A coffee?` theme.
3. Open Words and return to Talk.
4. Confirm `A coffee?` remains selected and `Your words.` is visible.
5. Open Settings and expand `Use your own API key`.
6. Confirm the secure field, Done action, backups, privacy links, and open-source notices are reachable.
7. When checking language isolation, select Spanish, inspect Themes and Words, then restore Norwegian through the picker.

## Proof

Capture the changed screens and accessibility output. Success is a visible selected theme after returning to Talk, the expected language-specific Words heading, and a passing focused UI test. A secure text field's existence proves the disclosure is reachable, not that a real key was saved.

## Gotchas

- Preview data is synthetic and in memory. It is safe for visual checks but does not prove persistence across a relaunch.
- Never enter a real key during simulator verification. For key persistence, use the physical device UI only with an explicitly authorized key.
- Do not infer that a selected menu item proves language-specific themes or words; inspect both tabs.

## Simulator evidence boundary

Use an explicitly owned, initially Shutdown simulator. Default slimming is validated for this synthetic UI flow; use `SIMULATOR_MODE=stock` for affected system integrations. Preview History is temporary, not reboot-persistence proof. Microphone, actual model execution, speech output and native background/drain remain physical-only checks. Require cleanup PASS/Shutdown before reviewing artifacts.
