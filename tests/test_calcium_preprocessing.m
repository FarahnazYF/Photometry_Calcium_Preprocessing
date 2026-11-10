function tests = test_calcium_preprocessing
%TEST_CALCIUM_PREPROCESSING Automatic checks of the pipeline on a synthetic recording.
%
% Run from the repository folder:
%     results = runtests('tests');
%     table(results)
%
% You do not need these tests to analyse your data. They check that every
% step still works after a change to the code. They make a small fake
% recording (make_synthetic_recording.m) in a temporary folder and run all
% steps without dialogs (the manual review is emulated). Nothing is
% written outside the temporary folder.
tests = functiontests(localfunctions);
end

% ==========================================================================
function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'Functions')));
folder = tempname;
mkdir(folder);
testCase.TestData.folder = folder;
[testCase.TestData.file, testCase.TestData.truth] = make_synthetic_recording(folder);
testCase.addTeardown(@() rmdir(folder, 's'));
end

function cfg = make_settings(testCase)
% The settings of Step 1 of run_calcium_preprocessing.m, plus what the
% dialogs of Step 2 would fill in.
cfg.raw_sampling_rate_hz = 1000;
cfg.pulse_width_ms = 10;
cfg.sample_rate_hz = 50;
cfg.pmt_variable = 'Raw';
cfg.led405_variable = 'Raw_2';
cfg.led470_variable = 'Raw_3';
cfg.lights_on = '07:30';
cfg.hours_before_lights_on = 1;
cfg.duration_hours = Inf;
cfg.recording_start = '';
cfg.phase_gap_sec = 30*60;
cfg.trim_start_sec = 15;
cfg.trim_end_sec = 5;
cfg.remove_sawtooth = true;
cfg.sawtooth_period_sec = 23.5;
cfg.sawtooth_search_sec = 1;
cfg.sawtooth_window_sec = 600;
cfg.sawtooth_period_span_sec = 1800;
cfg.sawtooth_min_snr = 4;
cfg.sawtooth_harmonics = 8;
cfg.lowpass_method = 'butterworth';
cfg.butterworth_cutoff_hz = 3;
cfg.butterworth_order = 2;
cfg.rolling_mean_window_sec = 1;
cfg.min_fit_samples = 20;
cfg.low_signal_fraction = 0.2;
cfg.artifact_prominence_mad = 3.5;
cfg.artifact_huge_peak_mad = 8;
cfg.artifact_min_peak_distance_sec = 1;
cfg.artifact_width_fraction = 0.5;
cfg.artifact_max_duration_sec = 40;
cfg.irls_tuning_constant = 1.4;
cfg.rolling_median_window_sec = 60;
cfg.show_figures = false;
cfg.save_figures = false;
cfg.max_plot_points = 20000;
cfg.save_trace_csv = false;
cfg.output_root = '';
cfg.pipeline_version = 'test';
% What photometry_select_recording fills in:
cfg.input_file = testCase.TestData.file;
[cfg.data_folder, cfg.filebase] = fileparts(testCase.TestData.file);
[cfg.recording_start, cfg.recording_start_info] = photometry_find_recording_start(cfg.input_file);
cfg.manual_review = false;
cfg.output_folder = fullfile(testCase.TestData.folder, 'results', char(java.util.UUID.randomUUID));
end

function data = run_steps(cfg, manual_mask)
% Steps 3-13 of run_calcium_preprocessing.m, without dialogs. A manual
% review is emulated by passing the samples to remove.
% Figures are only drawn (invisibly) when cfg.save_figures is true.
raw = photometry_load_and_crop(cfg);
data = photometry_extract_pulses(raw, cfg);
photometry_plot_qc('extracted', data, cfg);
data = photometry_find_phases_and_trim(data, cfg);
data = photometry_remove_sawtooth(data, cfg);
photometry_plot_qc('sawtooth', data, cfg);
data = photometry_lowpass_filter(data, cfg);
photometry_plot_qc('lowpass', data, cfg);
data = photometry_correct_bleaching(data, cfg);
photometry_plot_qc('bleaching', data, cfg);
data = photometry_detect_artifacts(data, cfg);
photometry_plot_qc('artifacts', data, cfg);
data = photometry_review_artifacts(data, cfg);          % cfg.manual_review = false: no review figures
if nargin > 1
    data.manual_mask = manual_mask;
end
data = photometry_motion_correct_dff(data, cfg);
photometry_plot_qc('motion', data, cfg);
[data.z, data.z_robust, data.z_info] = photometry_zscore(data.dF_F);
[data.dF_F_rolling_median, data.rolling_median_baseline] = photometry_rolling_median( ...
    data.dF_F, data.time_s, data.phase_windows, cfg.sample_rate_hz, cfg.rolling_median_window_sec);
[data.z_rolling_median, data.z_robust_rolling_median, data.z_info_rolling_median] = ...
    photometry_zscore(data.dF_F_rolling_median);
photometry_plot_qc('final', data, cfg);
end

% ==========================================================================
function testCropIndices(testCase)
[first, last, info] = photometry_crop_indices('06:55', '08:00', 1000, 49);
verifyEqual(testCase, first, 300001);                       % 5 minutes skipped
verifyEqual(testCase, last - first + 1, 49*3600*1000);
verifyEqual(testCase, info.reference_clock, '07:00:00');    % ZT-1 (= ZT 23)
verifyEqual(testCase, info.start_hours_from_lights_on, -1);
[first, ~, info] = photometry_crop_indices('06:56:16', '08:00', 1000, 49);
verifyEqual(testCase, info.offset_sec, 224);
verifyEqual(testCase, first, 224001);
[~, ~, info] = photometry_crop_indices('23:55', '01:00', 1000, 49);   % across midnight
verifyEqual(testCase, info.offset_sec, 300);
[~, ~, info] = photometry_crop_indices('05:00', '08:00', 1000, 49, 2);  % 2 hours before lights ON
verifyEqual(testCase, info.reference_clock, '06:00:00');
verifyEqual(testCase, info.start_hours_from_lights_on, -2);
[~, last] = photometry_crop_indices('06:55', '08:00', 1000, Inf);
verifyEqual(testCase, last, Inf);
verifyError(testCase, @() photometry_crop_indices('26:00', '08:00', 1000, 49), 'photometry:Clock');
end

function testZeitgeberTimeRestartsAtEveryLightsOn(testCase)
% ZT runs from 0 to 24 and restarts: 24 h after lights ON is ZT 0 of day 2,
% 36 h after it is ZT 12 (never ZT 24 or ZT 36).
[zt, day, label] = photometry_zt([-1; -0.5; 0; 11.5; 23.99; 24; 36; 47.5; 48]);
verifyEqual(testCase, zt, [23; 23.5; 0; 11.5; 23.99; 0; 12; 23.5; 0], 'AbsTol', 1e-12);
verifyEqual(testCase, day, [0; 0; 1; 1; 1; 2; 2; 2; 3]);
verifyEqual(testCase, label{7}, 'ZT 12.00 (day 2)');
[~, ~, label] = photometry_zt(47.9999);                 % last sample of a 49-h recording
verifyEqual(testCase, label, 'ZT 23.99 (day 2)');        % never shown as 24.00
[zt, day] = photometry_zt(24 - 1e-12);                    % rounding just below a lights ON
verifyEqual(testCase, [zt day], [0 2]);
end

function testFigureAxisShowsZeitgeberTime(testCase)
% The time axis of the figures is labelled 0-24 (restarting at every lights
% ON), also after zooming, and the data tips of the traces show ZT and day
% instead of the raw x value (hours from the first lights ON).
f = figure('Visible', 'off');
testCase.addTeardown(@() close(f));
ax = axes(f);
plot(ax, [-1 48], [0 0]);
trace = plot(ax, [-0.5 10 30.25 47.9], [1 2 3 4], 'HandleVisibility', 'off');   % like the figure traces
photometry_zt_axis(ax, [-1 48]);
tip = datatip(trace, 'DataIndex', 3);                   % x = 30.25 h = ZT 6.25 of day 2
verifyEqual(testCase, string(tip.Content), ["ZT (h) 6.25"; "Day 2"; "Y 3"]);
tip = datatip(trace, 'DataIndex', 1);                   % x = -0.5 h = ZT 23.5 before the first lights ON
verifyEqual(testCase, string(tip.Content), ["ZT (h) 23.5"; "Day 0"; "Y 1"]);
delete(findall(ax, 'Type', 'datatip'));
drawnow;
labels = str2double(ax.XTickLabel);
verifyTrue(testCase, all(labels >= 0 & labels < 24));
verifyEqual(testCase, labels(:)', [0 6 12 18 0 6 12 18 0]);
marks = findall(ax, 'Type', 'ConstantLine');             % the dashed lines (hidden from the legend)
verifyEqual(testCase, sort(string({marks.Label})), ...
    sort(["ZT 0 (day 1)", "ZT 12", "ZT 0 (day 2)", "ZT 12", "ZT 0 (day 3)"]));
xlim(ax, [30 36]);                                       % zoom in on day 2, ZT 6-12
drawnow;
verifyEqual(testCase, str2double(ax.XTickLabel)', 6:12);
for view = {[30 31], [23.7 24.2], [-1 -0.5]}            % close-ups, including across lights ON
    xlim(ax, view{1});
    drawnow;
    verifyEqual(testCase, str2double(ax.XTickLabel)', mod(round(mod(ax.XTick, 24), 4), 24), 'AbsTol', 1e-9);
end
end

function testRecordingStartFromMatFile(testCase)
[clock, info] = photometry_find_recording_start(testCase.TestData.file);
verifyEqual(testCase, clock, '06:30:00');
verifySubstring(testCase, info.method, 'MAT file');
end

function testRecordingTooShortGivesClearError(testCase)
cfg = make_settings(testCase);
cfg.duration_hours = 49;
verifyError(testCase, @() photometry_load_and_crop(cfg), 'photometry:Input');
end

function testFullPipeline(testCase)
cfg = make_settings(testCase);
cfg.save_figures = true;                                   % also checks the figure code
truth = testCase.TestData.truth;
data = run_steps(cfg);

% Steps 3-5: two phases, 50 values per second, trims at the phase edges.
verifyEqual(testCase, size(data.phase_windows, 1), 2);
verifyEqual(testCase, data.pulse_info.measured_rate_hz, 50, 'RelTol', 1e-6);
verifyEqual(testCase, nnz(data.trim_mask), 2*(15 + 5)*50);
verifyTrue(testCase, all(isnan(data.dF_F(data.trim_mask))));

% Step 6: the sawtooth is found in every window, with the right period,
% and what is subtracted matches the true sawtooth.
w = data.sawtooth_info.windows;
verifyTrue(testCase, all(w.applied));
verifyEqual(testCase, w.period_s, truth.sawtooth_period_s*ones(height(w), 1), 'AbsTol', 0.05);
for p = 1:2
    idx = data.phase_windows(p, 1):data.phase_windows(p, 2);
    idx = idx(~data.trim_mask(idx));
    true_sawtooth = truth.sawtooth405(data.time_s(idx));
    left_over = rms(data.sawtooth_estimate(idx) - true_sawtooth);
    verifyLessThan(testCase, left_over, 0.25*rms(true_sawtooth), ...
        sprintf('Phase %d: more than 25%% of the sawtooth is left.', p));
end

% Step 8: the corrected channels hover around 1, by double exponential.
verifyEqual(testCase, median(data.corrected405, 'omitnan'), 1, 'AbsTol', 0.02);
verifyEqual(testCase, median(data.corrected470, 'omitnan'), 1, 'AbsTol', 0.02);
verifyTrue(testCase, all(data.bleaching_info.method == "double exponential"));

% Step 9: the large movement dips are suggested.
for k = 1:numel(truth.dip_times_s)
    verifyTrue(testCase, any(abs(data.artifact_suggestions.peak_s - truth.dip_times_s(k)) < 2), ...
        sprintf('The movement dip at %g s was not suggested.', truth.dip_times_s(k)));
end

% Step 11: dF/F follows the definition; the fitted line has the expected slope
% (470 moves 0.7x as much as 405 in the synthetic data).
valid = data.valid_mask;
expected = (data.corrected470 - data.fitted405)./data.fitted405;
verifyEqual(testCase, data.dF_F(valid), expected(valid), 'AbsTol', 1e-15);
verifyEqual(testCase, data.motion_fit.slope, 0.7, 'AbsTol', 0.1);

% Step 12: z-scores.
verifyEqual(testCase, mean(data.z, 'omitnan'), 0, 'AbsTol', 1e-10);
verifyEqual(testCase, std(data.z, 'omitnan'), 1, 'AbsTol', 1e-10);
verifyEqual(testCase, median(data.z_robust, 'omitnan'), 0, 'AbsTol', 1e-10);
verifyEqual(testCase, data.z_robust(valid), ...
    (data.dF_F(valid) - median(data.dF_F(valid)))/(1.4826*mad(data.dF_F(valid), 1)), 'AbsTol', 1e-12);

% Step 13: the rolling median is subtracted, inside each phase only.
verifyEqual(testCase, data.dF_F_rolling_median(valid), ...
    data.dF_F(valid) - data.rolling_median_baseline(valid), 'AbsTol', 1e-15);
verifyTrue(testCase, isequal(isnan(data.dF_F_rolling_median), isnan(data.dF_F)));

% Step 14: the saved file and tables.
file = photometry_save_results(data, cfg);
verifyTrue(testCase, isfile(file));
loaded = load(file, 'results');
r = loaded.results;
verifyEqual(testCase, r.no_rolling_median.dF_F, data.dF_F);
verifyEqual(testCase, r.no_rolling_median.z_robust, data.z_robust);
verifyEqual(testCase, r.rolling_median.dF_F, data.dF_F_rolling_median);
verifyEqual(testCase, r.rolling_median.window_sec, 60);
% Zeitgeber time restarts at 0 at every lights ON; the recording starts at
% ZT-1, i.e. ZT 23 before the first lights ON (day 0).
verifyEqual(testCase, r.zt_hours, mod(-1 + data.time_s/3600, 24), 'AbsTol', 1e-9);
verifyTrue(testCase, all(r.zt_hours >= 0 & r.zt_hours < 24));
verifyEqual(testCase, r.zt_hours(1), 23, 'AbsTol', 1e-12);
verifyTrue(testCase, all(r.day == 0));    % this 55-min recording ends before the first lights ON
verifyEqual(testCase, height(r.phase_summary), 2);
verifyEqual(testCase, r.phase_summary.start_zt_hours(1), 23, 'AbsTol', 1e-12);
verifyTrue(testCase, all(r.artifact_suggestions.peak_zt_hours >= 0 & r.artifact_suggestions.peak_zt_hours < 24));
files = photometry_output_files(cfg);
verifyTrue(testCase, isfile(files.phase_summary));
verifyTrue(testCase, isfile(files.artifact_suggestions));
verifyTrue(testCase, isfile(files.sawtooth_windows));
verifyEqual(testCase, numel(dir(fullfile(files.figures_folder, '*.png'))), 7);
end

function testManualRemovalIsExcludedFromTheFit(testCase)
cfg = make_settings(testCase);
reference = run_steps(cfg);
mask = false(size(reference.time_s));
mask(reference.phase_windows(1, 1) + (5000:5500)) = true;   % 10 s inside phase 1
data = run_steps(cfg, mask);
verifyTrue(testCase, all(isnan(data.dF_F(mask))));
verifyTrue(testCase, all(isnan(data.dF_F_rolling_median(mask))));
% The line is fitted without the removed samples.
keep = isfinite(data.corrected405) & isfinite(data.corrected470) & ~mask;
expected = photometry_irls_fit(data.corrected405(keep), data.corrected470(keep), cfg.irls_tuning_constant);
verifyEqual(testCase, [data.motion_fit.slope data.motion_fit.intercept], expected, 'AbsTol', 1e-12);
% The table of removed windows is filled by photometry_review_artifacts only;
% here the mask was set directly, so the summary counts it.
summary = photometry_phase_summary(data);
verifyEqual(testCase, summary.removed_by_hand(1), nnz(mask));
end

function testRollingMeanFilterOption(testCase)
cfg = make_settings(testCase);
cfg.lowpass_method = 'rolling_mean';
data = run_steps(cfg);
verifyEqual(testCase, data.lowpass_info.method, 'rolling_mean');
verifyEqual(testCase, data.lowpass_info.window_samples, 50);
% A rolling mean by hand, in the middle of phase 1 (far from any edge).
k = data.phase_windows(1, 1) + 10000;
verifyEqual(testCase, data.filtered470(k), mean(data.trimmed470(k-25:k+24)), 'AbsTol', 1e-12);
verifyGreaterThan(testCase, nnz(isfinite(data.dF_F)), 0.9*numel(data.dF_F));
cfg.lowpass_method = 'median';
verifyError(testCase, @() photometry_lowpass_filter(data, cfg), 'photometry:LowpassMethod');
end

function testSawtoothRemovalLeavesCleanDataUnchanged(testCase)
folder = fullfile(testCase.TestData.folder, 'no_sawtooth');
file = make_synthetic_recording(folder, 'Sawtooth', false);
cfg = make_settings(testCase);
cfg.input_file = file;
data = run_steps(cfg);
verifyEqual(testCase, data.sawtooth_info.windows_applied, 0);
kept = ~data.trim_mask;
verifyEqual(testCase, data.cleaned405(kept), data.raw405(kept));     % 405 unchanged
verifyTrue(testCase, all(isnan(data.cleaned405(data.trim_mask))));  % trims still missing
end
