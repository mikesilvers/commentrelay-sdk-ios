# Feedback sheet: user-dismissible

## Problem
`CommentRelayView` never uses `dismiss` — there is no way to exit the feedback
sheet from any screen. On macOS there is no swipe-to-dismiss, so the user is
trapped (picker, form, history, and even the thank-you screen, whose "Done"
button only reloads back to the picker).

## Fix
- Add `@Environment(\.dismiss)` to `CommentRelayView`.
- Add a single persistent toolbar **Cancel** button at `.cancellationAction`
  placement (natural leading/cancel spot on iOS and macOS; coexists with the
  existing history button at primaryAction/topBarTrailing). Available on every
  route; it closes the sheet without submitting feedback (nothing is sent
  unless Submit is tapped).
- Change the `doneAction` passed to `ThankYouView` from `reload()` to
  `dismiss()` so "Done" after a successful submission also closes the sheet.
  `ThankYouView`'s public API is unchanged.
- New localized string `crl.sheet.cancel` ("Cancel" / "Cancelar") with a
  `Strings` accessor, added to `en` and `es-419`.

One "Cancel" label everywhere (not a separate "Close") — avoids redundant,
differently-named controls and makes the no-send behavior explicit.

## Verification
`swift build`, then run the sample: confirm a Cancel control on picker/form/
history that dismisses the sheet without sending, and that "Done" on the
thank-you screen dismisses it.
