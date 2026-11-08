<!--
Two kinds of pull request land here; say which this is.

- Plan / design doc: a document under docs/, labelled `plan`. Plans are merged on a light read so
  they're visible for review and comment; merging one records the proposal, not approval of the code
  it describes.
- Code: targets `next`. Xcode Cloud builds, tests and archives `next` after the merge (the
  `HotMess | Next` checks); it doesn't build pull request branches, so verify on a Mac first with
  `scripts/verify-apple.sh hotmess` from the AudienceKit checkout (README, "CI").
-->

## Kind

- [ ] Plan / design doc (label `plan`)
- [ ] Code

## What and why

<!-- The change, and the problem it solves. Link the plan or issue it implements, if any. -->

## How it was verified

<!-- e.g. `scripts/verify-apple.sh hotmess`, `xcodebuild test -scheme "HotMess Debug"`, run on device/simulator against next. Say what was *not* tested. -->

## Review

<!-- Anything to look at closely: API/SDK version changes, payments, sign-in, App Clip. Screenshots for UI changes. -->
