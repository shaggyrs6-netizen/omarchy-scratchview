# 1.0.1 — Plain-text window-title tooltips

## Report

HANCORE-linux identified an HTML interpretation issue in the 1.0.0 submission at `c28d3d025fd8ae35e0a415de5eb8ed42b077a8e9`: [marketplace review](https://github.com/omacom/omarchy-plugin-marketplace/issues/11237#issuecomment-6129639802).

The card label already used `Text.PlainText`, but its attached Qt tooltip passed the raw window title to the default `AutoText` renderer. An application-controlled title containing an HTML image tag could cause a request when the tooltip was instantiated/rendered. Protecting the visible label did not protect that separate renderer. Bar chip titles also flowed into host-controlled tooltip rendering.

## Fix

- Added `PlainToolTip.qml`, whose content item explicitly sets `textFormat: Text.PlainText`. Original title text is preserved, including angle brackets and ampersands, without interpreting tags or entities.
- Panel window-title hover uses this component instead of the attached automatic-text tooltip.
- Bar chip titles use the same component. Their native `tooltipText` is empty, so the title never reaches a custom bar's potentially automatic-text sink. Full-title hover remains available.
- Backend error strings are no longer passed to the host tooltip. It gets a fixed attention message; other host tooltip text is fixed copy or numeric counts.
- Existing title labels and action-menu titles remain explicitly plain text. Static settings/action tooltips do not include application-controlled strings.

## Verification

`python3 -m unittest discover -s . -q` passes 34 tests. `node test_visibility.cjs` passes seven checks: **41 total**. `omarchy plugin validate .` and whitespace checks pass.

`test_tooltips.py` runs an actual Qt Basic tooltip through offscreen Quickshell and a temporary HTTP listener bound only to `127.0.0.1` on an ephemeral port. An HTML image title makes the standard AutoText tooltip fetch the probe path (positive control); the shared PlainToolTip preserves the original text, reports `Text.PlainText`, and makes **zero requests**. The unsafe control is instantiated only in its own subprocess, because even an invisible automatic-text item may load an image. No external tracking endpoint or user window is involved.

Source guards verify that panel and bar use the shared component and do not pass title/model strings into attached or host tooltip properties. The release panel loaded and exited successfully. A separate bar harness with sample titles loaded the actual fixed widget and reported healthy. This does not constitute an exhaustive hover/placement test on every custom bar or a general security audit.

## Scope

No changes to scratchpad movement, settings, shortcuts, stored window identities, thumbnail assets or installation procedure. Version incremented to 1.0.1. The fix applies to both public release source and the maintainer's existing local prototype; those remain separate installations. Older installed 1.0.0 copies need updating.
