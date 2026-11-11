# Changelog

What changed in each version: results, saved fields and how the pipeline is
used. The version of the code that made a result file is saved in
`results.pipeline_version`.

## 1.1.0 (2026-11-11)

This version fixes the defects found in a review of version 1.0.0.

### Results that change

- **Low-pass filter (Step 7).** The Butterworth filter is now applied to each
  phase on its own, and to each stretch between two short pauses of the LEDs.
  In 1.0.0 all phases were joined before filtering, so the first and last
  samples of every phase were pulled towards the level of the neighbouring
  phase.
  - What changes: the first and last 0.3 s that are kept in each phase (after
    the trims), and the same short stretch on each side of a short LED pause
    inside a phase.
  - How much, measured on 6 hours of a real recording (two phases, SD of dF/F
    2.6%): the very first or last kept sample of a phase changed by up to 1.4
    dF/F percentage points; from 0.3 s inside the phase onwards the change
    was below 0.02 points.
  - Everything else: all samples more than 1 s away from a phase edge or a
    pause changed by less than 0.001 points (the bleaching fit and the motion
    fit change very slightly).
- **Rolling-mean option (Step 7, not the default).** The window is now rounded
  to an odd number of samples (51 instead of 50 for 1 s at 50 per second), so
  the mean is centred on each sample. In 1.0.0 it was shifted by half a
  sample (10 ms). With this option every sample changes a little: on the same
  real recording the new dF/F correlated 0.99995 with that of 1.0.0, and the
  largest difference was 0.19 points.
- **Samples without a 470 value (Step 5).** 470 values are no longer
  extrapolated, and no longer interpolated across a gap of two or more
  missing 470 pulses. The first sample after the LEDs switch on therefore has
  no 470 value and no dF/F: one sample at the start of each phase (inside the
  trim, so nothing changes there) and one or two samples next to each short
  LED pause inside a phase.

Unchanged: pulse extraction (Step 4) gives exactly the same pulses and values
as 1.0.0 in ordinary recordings (LEDs on for 5% to 95% of the analysis
window); sawtooth removal, bleaching correction, IRLS fit, dF/F formula,
z-scores and rolling median are the same calculations as before.

### Fixed

- **Step 4, pulse detection.** Pulses are now also found when an LED is on for
  less than 5% (or more than 95%) of the analysis window. The pulse rate of
  the 470 LED is checked too, and a monitor channel that does not show two
  levels gives its own error message.
- **Step 5, alignment.** Where the 470 LED is off while the 405 LED keeps
  flashing, the 470 value is missing (`NaN`) instead of an interpolated
  number, and a warning is shown. Short pauses of both LEDs inside a phase
  are reported in the Command Window. (In our recordings the first 405 pulse
  after such a pause is 25 to 33% dimmer than the pulses before it. That
  sample now has no 470 value, so it is left out.)
- **Figures.** The ZT tick labels always belong to their ticks, also after
  zooming in and resizing the figure. Data tips never show "ZT 24".
- **Step 14, saving.** Saving again in the same MATLAB session no longer
  overwrites the first results: the new results go to a folder ending in
  `_2`. Step 14 does not save when a step is out of date (an earlier section
  was run again but not the later ones). The saved settings are the values
  that were really used.
- **Recording start from an EDF file.** The check that the EDF belongs to the
  MAT file uses the variable names of the settings, also works when the
  channel names of the two files differ, and the preview dialog says when the
  check was not possible.
- **Memory.** Step 4 needs less working memory: about 6 GB instead of about
  9 GB at the peak for 49 hours at 1000 Hz (measured on a 2.5-hour test
  recording and scaled).

### Added

- `photometry_version.m`: the version number is no longer typed in the main
  script.
- New fields in the saved `results`: `format_version` (2), `code_checksum`,
  `alignment`, `rolling_median.window_samples`, and more details in
  `pulse_info` and `lowpass`. `results.settings` no longer has a
  `pipeline_version` field (use `results.pipeline_version`).
- More tests (22 instead of 9).

### Documentation

- README: new section "What the results can and cannot show". Version 1.0.0
  said that the results without the rolling median keep slow changes "across
  the light-dark cycle". They do not: the bleaching correction brings every
  phase to the same level, so signal levels cannot be compared between phases.
- README: memory needed, sawtooth removal, tests and the methods paragraph
  were corrected.

### Reading result files of version 1.0.0

Files of version 1.0.0 have no `results.format_version`. Two layouts carry
the label 1.0.0:

- Files made with the first published code (9 November 2026, before the
  Zeitgeber-time change): `results.zt_hours` counts hours from the first
  lights ON without restarting (negative before it, above 24 on the second
  day), there is no `results.day`, and `results.crop_info` has `reference_zt`
  instead of `start_hours_from_lights_on`. Convert with
  `mod(results.zt_hours, 24)`.
- Files made after that change: `results.zt_hours` runs from 0 to 24 and
  `results.day` exists, as in 1.1.0.

So a file without `results.day` uses the first layout.

## 1.0.0 (2026-11-09)

First public version.
