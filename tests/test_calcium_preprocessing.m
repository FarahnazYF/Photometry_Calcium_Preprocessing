function tests = test_calcium_preprocessing
%TEST_CALCIUM_PREPROCESSING Automatic checks of the pipeline.
%
% Run from the repository folder:
%     results = runtests('tests');
%     table(results)
%
% You do not need these tests to analyse your data. They check that the
% code still works after a change. Most of them use a small synthetic
% recording (make_synthetic_recording.m) in a temporary folder and run the
% steps without dialogs. Nothing is written outside the temporary folder.
%
% Not covered: the dialogs of Step 2 and the interactive review of Step 10
% (they need a person at the screen), real recordings, and the memory and
% time a long recording needs.
tests = functiontests(localfunctions);
end

% ==========================================================================
% Shared set-up and helpers
% ==========================================================================
function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'Functions')));
folder = tempname;
mkdir(folder);
testCase.TestData.folder = folder;
[testCase.TestData.file, testCase.TestData.truth] = make_synthetic_recording(folder);
testCase.addTeardown(@() rmdir(folder, 's'));
% One complete run that several tests share (they only read it).
testCase.TestData.reference = run_steps(make_settings(testCase));
end

function cfg = make_settings(testCase)
% The settings of Step 1 of run_calcium_preprocessing.m, plus what the
% dialogs of Step 2 would fill in. Every call gets its own results folder.
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
% What photometry_select_recording fills in:
cfg.input_file = testCase.TestData.file;
[cfg.data_folder, cfg.filebase] = fileparts(testCase.TestData.file);
[cfg.recording_start, cfg.recording_start_info] = photometry_find_recording_start(cfg.input_file);
cfg.manual_review = false;
cfg.output_folder = fullfile(testCase.TestData.folder, 'results', char(java.util.UUID.randomUUID));
end

function data = run_steps(cfg, manual_mask)
% Steps 3-13 of run_calcium_preprocessing.m, without dialogs.
% Figures are only drawn (invisibly) when cfg.save_figures is true.
if nargin < 2, manual_mask = []; end
raw = photometry_load_and_crop(cfg);
data = photometry_extract_pulses(raw, cfg);
photometry_plot_qc('extracted', data, cfg);
data = photometry_find_phases_and_trim(data, cfg);
data = continue_steps(data, cfg, 6, manual_mask);
end

function data = continue_steps(data, cfg, first_step, manual_mask)
% Steps first_step to 13 (first_step = 6 to 11), as when sections of the
% main script are run again. A manual review is emulated by passing the
% samples to remove.
if nargin < 4, manual_mask = []; end
if first_step <= 6
    data = photometry_remove_sawtooth(data, cfg);
    photometry_plot_qc('sawtooth', data, cfg);
end
if first_step <= 7
    data = photometry_lowpass_filter(data, cfg);
    photometry_plot_qc('lowpass', data, cfg);
end
if first_step <= 8
    data = photometry_correct_bleaching(data, cfg);
    photometry_plot_qc('bleaching', data, cfg);
end
if first_step <= 9
    data = photometry_detect_artifacts(data, cfg);
    photometry_plot_qc('artifacts', data, cfg);
end
if first_step <= 10
    data = photometry_review_artifacts(data, cfg);      % cfg.manual_review = false: no review figures
    if ~isempty(manual_mask), data.manual_mask = manual_mask; end
end
data = photometry_motion_correct_dff(data, cfg);
photometry_plot_qc('motion', data, cfg);
[data.z, data.z_robust, data.z_info] = photometry_zscore(data.dF_F);
[data.dF_F_rolling_median, data.rolling_median_baseline, data.rolling_median_info] = photometry_rolling_median( ...
    data.dF_F, data.time_s, data.phase_windows, cfg.sample_rate_hz, cfg.rolling_median_window_sec);
[data.z_rolling_median, data.z_robust_rolling_median, data.z_info_rolling_median] = ...
    photometry_zscore(data.dF_F_rolling_median);
photometry_plot_qc('final', data, cfg);
end

function [data, cfg, expected] = constant_level_data()
% Two phases whose stretches each have their own constant level. If a
% filter mixed two stretches, the output would leave that level.
%   phase 1: samples 1-1000, with pulse gaps after samples 500, 600 and 605
%            (so samples 601-605 form a stretch of only 5 samples)
%   phase 2: samples 1001-2000, one hour later
% The first 50 and last 20 samples of each phase are trimmed (NaN).
fs = 50;
t = (0:1999)'/fs;
t(501:end)  = t(501:end) + 1;
t(601:end)  = t(601:end) + 1;
t(606:end)  = t(606:end) + 1;
t(1001:end) = t(1001:end) + 3600;
expected = [2*ones(500, 1); 3*ones(100, 1); 4*ones(5, 1); 6*ones(395, 1); 9*ones(1000, 1)];
expected([1:50, 981:1000, 1001:1050, 1981:2000]) = NaN;
data.cleaned405 = expected;
data.trimmed470 = 10*expected;
data.time_s = t;
data.phase_windows = [1 1000; 1001 2000];
cfg = struct('lowpass_method', 'butterworth', 'sample_rate_hz', fs, 'butterworth_cutoff_hz', 3, ...
    'butterworth_order', 2, 'rolling_mean_window_sec', 1);
end

function check_tick_labels(testCase, ax)
% Every tick label must be the Zeitgeber time of its own tick.
labels = str2double(ax.XTickLabel(:))';
expected = mod(ax.XTick, 24);
expected(expected > 24 - 1e-6) = 0;
verifyEqual(testCase, ax.XTickMode, 'manual');           % positions are fixed together with the labels
verifyEqual(testCase, numel(labels), numel(ax.XTick));
verifyEqual(testCase, labels, expected, 'AbsTol', 1e-6);
verifyTrue(testCase, all(labels >= 0 & labels < 24));
end

function write_edf_header(file, labels, samples_per_record, n_records, record_duration, reserved, onset)
% Write the header of an EDF file (start 09.11.26 at 06.56.16) and, for
% EDF+ (onset not empty), the first time-keeping annotation.
pad = @(s, n) [s, repmat(' ', 1, n - numel(s))];
ns = numel(labels);
fixed = [pad('0', 8), pad('X X X X', 80), pad('Startdate X X X X', 80), '09.11.26', '06.56.16', ...
    pad(sprintf('%d', 256*(1 + ns)), 8), pad(reserved, 44), pad(sprintf('%d', n_records), 8), ...
    pad(sprintf('%g', record_duration), 8), pad(sprintf('%d', ns), 4)];
label_text = cellfun(@(s) pad(s, 16), labels, 'UniformOutput', false);
sample_text = arrayfun(@(s) pad(sprintf('%d', s), 8), samples_per_record, 'UniformOutput', false);
signals = [[label_text{:}], repmat(' ', 1, 80*ns), repmat(pad('uV', 8), 1, ns), ...
    repmat(pad('-1', 8), 1, ns), repmat(pad('1', 8), 1, ns), ...
    repmat(pad('-32768', 8), 1, ns), repmat(pad('32767', 8), 1, ns), ...
    repmat(' ', 1, 80*ns), [sample_text{:}], repmat(' ', 1, 32*ns)];
fid = fopen(file, 'w');
fwrite(fid, [fixed signals], 'uint8');
if ~isempty(onset)
    annotation = find(strcmp(labels, 'EDF Annotations'), 1);
    fwrite(fid, zeros(1, 2*sum(samples_per_record(1:annotation-1))), 'uint8');
    first = [uint8(onset) 20 20 0];
    fwrite(fid, [first zeros(1, 2*samples_per_record(annotation) - numel(first))], 'uint8');
end
fclose(fid);
end

function mat = save_channels(folder, name, n_samples, variable_names)
% A small MAT "recording" whose three channels have n_samples samples.
if nargin < 4, variable_names = {'Raw', 'Raw_2', 'Raw_3'}; end
channels = struct();
for k = 1:3
    channels.(variable_names{k}) = zeros(n_samples, 1);
end
mat = fullfile(folder, [name '.mat']);
save(mat, '-struct', 'channels');
end

% ==========================================================================
% Clock times, Zeitgeber time, figure axis
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
% ON). Tick positions and labels stay together when the view is zoomed and
% when the figure is resized. Data tips show ZT and day, never "ZT 24".
f = figure('Visible', 'off');
testCase.addTeardown(@() close(f));
ax = axes(f);
plot(ax, [-1 48], [0 0]);
trace = plot(ax, [-0.5 10 23.99998 30.25 47.9], [1 2 3 4 5], 'HandleVisibility', 'off');   % like the figure traces
photometry_zt_axis(ax, [-1 48]);

tip = datatip(trace, 'DataIndex', 4);                   % x = 30.25 h = ZT 6.25 of day 2
verifyEqual(testCase, string(tip.Content), ["ZT (h) 6.25"; "Day 2"; "Y 4"]);
tip = datatip(trace, 'DataIndex', 1);                   % x = -0.5 h = ZT 23.5 before the first lights ON
verifyEqual(testCase, string(tip.Content), ["ZT (h) 23.5"; "Day 0"; "Y 1"]);
tip = datatip(trace, 'DataIndex', 3);                   % 0.07 s before the second lights ON
verifyEqual(testCase, string(tip.Content), ["ZT (h) 23.9999"; "Day 1"; "Y 3"]);
delete(findall(ax, 'Type', 'datatip'));

% The whole recording: a tick every 6 hours.
drawnow;
verifyEqual(testCase, str2double(ax.XTickLabel(:))', [0 6 12 18 0 6 12 18 0]);
check_tick_labels(testCase, ax);
marks = findall(ax, 'Type', 'ConstantLine');             % the dashed lines (hidden from the legend)
verifyEqual(testCase, sort(string({marks.Label})), ...
    sort(["ZT 0 (day 1)", "ZT 12", "ZT 0 (day 2)", "ZT 12", "ZT 0 (day 3)"]));

% Zoomed views, including across a lights ON and down to half a minute.
xlim(ax, [30 36]);
drawnow;
verifyEqual(testCase, str2double(ax.XTickLabel(:))', 6:12);
views = {[30 31], [23.7 24.2], [-1 -0.5], [10 10.01]};
for k = 1:numel(views)
    xlim(ax, views{k});
    drawnow;
    check_tick_labels(testCase, ax);
end

% Resizing the figure must not separate the labels from their ticks.
xlim(ax, [30 31]);
for new_size = {[320 240], [1500 900]}
    f.Position(3:4) = new_size{1};
    drawnow;
    check_tick_labels(testCase, ax);
end
end

% ==========================================================================
% Recording start time
% ==========================================================================
function testRecordingStartFromMatFile(testCase)
[clock, info] = photometry_find_recording_start(testCase.TestData.file);
verifyEqual(testCase, clock, '06:30:00');
verifySubstring(testCase, info.method, 'MAT file');
verifySubstring(testCase, info.verification_note, 'MAT file');
end

function testRecordingStartFromEdfFile(testCase)
folder = fullfile(testCase.TestData.folder, 'edf');
mkdir(folder);

% A MAT file that is a complete copy of its EDF file: 5 records of 1 s at 1000 Hz.
mat = save_channels(folder, 'complete', 5000);
write_edf_header(fullfile(folder, 'complete.edf'), {'Raw', 'Raw_2', 'Raw_3'}, [1000 1000 1000], 5, 1, '', '');
[clock, info] = photometry_find_recording_start(mat);
verifyEqual(testCase, clock, '06:56:16');
verifySubstring(testCase, info.method, 'EDF');
verifyTrue(testCase, info.mat_length_verified);

% The EDF repeats the name "Raw"; MATLAB calls the copies Raw_2 and Raw_3.
mat = save_channels(folder, 'repeated', 5000);
write_edf_header(fullfile(folder, 'repeated.edf'), {'Raw', 'Raw', 'Raw'}, [1000 1000 1000], 5, 1, '', '');
[~, info] = photometry_find_recording_start(mat);
verifyTrue(testCase, info.mat_length_verified);

% The EDF file is somewhere else and is named explicitly.
mat = save_channels(folder, 'elsewhere', 5000);
[clock, info] = photometry_find_recording_start(mat, fullfile(folder, 'complete.edf'));
verifyEqual(testCase, clock, '06:56:16');
verifyTrue(testCase, info.mat_length_verified);

% A MAT file that is shorter than the EDF recording, or sampled differently: error.
mat = save_channels(folder, 'short', 4000);
write_edf_header(fullfile(folder, 'short.edf'), {'Raw', 'Raw_2', 'Raw_3'}, [1000 1000 1000], 5, 1, '', '');
verifyError(testCase, @() photometry_find_recording_start(mat), 'photometry:EDFLengthMismatch');
mat = save_channels(folder, 'rate', 2500);
write_edf_header(fullfile(folder, 'rate.edf'), {'Raw', 'Raw_2', 'Raw_3'}, [500 500 500], 5, 1, '', '');
verifyError(testCase, @() photometry_find_recording_start(mat), 'photometry:EDFRateMismatch');

% Other channel names in both files: the two durations are compared.
names = {'pmt', 'monitor_a', 'monitor_b'};
mat = save_channels(folder, 'other_names', 5000, names);
write_edf_header(fullfile(folder, 'other_names.edf'), {'Photodetector', 'LED A', 'LED B'}, [1000 1000 1000], 5, 1, '', '');
[~, info] = photometry_find_recording_start(mat, '', 1000, names);
verifyTrue(testCase, info.mat_length_verified);
verifySubstring(testCase, info.verification_note, 'equally long');
mat = save_channels(folder, 'other_short', 3000, names);
write_edf_header(fullfile(folder, 'other_short.edf'), {'Photodetector', 'LED A', 'LED B'}, [1000 1000 1000], 5, 1, '', '');
verifyError(testCase, @() photometry_find_recording_start(mat, '', 1000, names), 'photometry:EDFLengthMismatch');

% An EDF that does not say how long it is: the time is returned, marked as not checked.
mat = save_channels(folder, 'unknown', 5000);
write_edf_header(fullfile(folder, 'unknown.edf'), {'Raw', 'Raw_2', 'Raw_3'}, [1000 1000 1000], -1, 1, '', '');
[clock, info] = photometry_find_recording_start(mat);
verifyEqual(testCase, clock, '06:56:16');
verifyFalse(testCase, info.mat_length_verified);
verifySubstring(testCase, info.verification_note, 'NOT CHECKED');

% EDF+: the first record starts a quarter of a second after the header time.
mat = save_channels(folder, 'plus', 5000);
write_edf_header(fullfile(folder, 'plus.edf'), {'Raw', 'EDF Annotations'}, [1000 30], 5, 1, 'EDF+C', '+0.25');
[clock, info] = photometry_find_recording_start(mat);
verifyEqual(testCase, clock, '06:56:16.250000');
verifyTrue(testCase, info.mat_length_verified);

% EDF+ with gaps in the recording cannot give clock times: error.
mat = save_channels(folder, 'gaps', 5000);
write_edf_header(fullfile(folder, 'gaps.edf'), {'Raw', 'EDF Annotations'}, [1000 30], 5, 1, 'EDF+D', '+0');
verifyError(testCase, @() photometry_find_recording_start(mat), 'photometry:DiscontinuousEDF');

% Neither a start-time variable nor an EDF file.
mat = save_channels(folder, 'alone', 5000);
verifyError(testCase, @() photometry_find_recording_start(mat), 'photometry:MissingRecordingStart');
end

function testRecordingTooShortGivesClearError(testCase)
cfg = make_settings(testCase);
cfg.duration_hours = 49;
verifyError(testCase, @() photometry_load_and_crop(cfg), 'photometry:Input');
end

% ==========================================================================
% Step 4: LED pulses
% ==========================================================================
function testPulseThresholdInAnOrdinaryRecording(testCase)
% Analog monitors like those of real recordings: noisy, with an "on" level
% that drifts, a few much higher values and an in-between sample at some
% pulse edges. The LEDs are on all the time, so the threshold must be
% halfway between the 5th and the 95th percentile, and the pulses must be
% those of MATLAB's own 3-sample median filter (as in version 1.0.0).
rng(5);
fs = 1000;
n = 120*fs;
cycle = mod((0:n-1)', 20);
on405 = cycle < 10;
on470 = cycle >= 10;
drift = 1 + 0.2*sin(2*pi*(0:n-1)'/n);                    % the "on" level drifts by 20%
raw.led405 = 35 + 16*round(randn(n, 1)) + on405.*(1300*drift + 30*randn(n, 1));
raw.led470 = 35 + 16*round(randn(n, 1)) + on470.*(2500*drift + 30*randn(n, 1));
raw.led405(randperm(n, 20)) = 3000;                       % a few much higher values
rising = find(diff(on405) == 1) + 1;                      % first sample of the pulses
raw.led405(rising(1:7:end)) = 600;                        % an in-between sample at some edges
raw.pmt = 100*on405 + 200*on470 + 0.5*randn(n, 1);
raw.fs = fs;
raw.crop_info = struct('start_hours_from_lights_on', -1);
cfg = struct('pulse_width_ms', 10, 'sample_rate_hz', 50, 'led405_variable', 'Raw_2', 'led470_variable', 'Raw_3');
data = photometry_extract_pulses(raw, cfg);

verifySubstring(testCase, data.pulse_info.level_method405, 'percentile');
verifySubstring(testCase, data.pulse_info.level_method470, 'percentile');
threshold = (prctile(raw.led405, 5) + prctile(raw.led405, 95))/2;
verifyEqual(testCase, data.pulse_info.threshold405, threshold);
state = medfilt1(double(raw.led405 > threshold), 3);
steps = diff([0; state; 0]);
first = find(steps == 1);
last = find(steps == -1) - 1;
first = first(last - first >= 5);
verifyEqual(testCase, data.time_s, (first - 1)/fs);
verifyEqual(testCase, data.pulse_info.pulses405, 6000);
verifyEqual(testCase, data.pulse_info.pulses470, 6000);
verifyEqual(testCase, data.raw405, 100*ones(6000, 1), 'AbsTol', 2);
verifyEqual(testCase, data.raw470, 200*ones(6000, 1), 'AbsTol', 2);
end

function testPulsesAreFoundWhenTheLedIsRarelyOn(testCase)
% The LEDs are on for 20 s of a 10-minute window (each LED during 1.7% of
% the samples), and the monitors are noisy analog signals.
rng(3);
fs = 1000;
n = 600*fs;
t = (0:n-1)'/fs;
active = t >= 100 & t < 120;
cycle = mod((0:n-1)', 20);
on405 = cycle < 10 & active;
on470 = cycle >= 10 & active;
raw.led405 = 0.05 + 4.85*on405 + 0.01*randn(n, 1);
raw.led470 = 0.05 + 4.85*on470 + 0.01*randn(n, 1);
raw.pmt = 100*on405 + 200*on470 + 0.5*randn(n, 1);
raw.fs = fs;
raw.crop_info = struct('start_hours_from_lights_on', -1);
cfg = struct('pulse_width_ms', 10, 'sample_rate_hz', 50, 'led405_variable', 'Raw_2', 'led470_variable', 'Raw_3');
data = photometry_extract_pulses(raw, cfg);
verifyEqual(testCase, data.pulse_info.pulses405, 1000);
verifyEqual(testCase, data.pulse_info.pulses470, 1000);
verifyEqual(testCase, data.time_s(1), 100, 'AbsTol', 1e-9);
verifyEqual(testCase, data.raw405, 100*ones(1000, 1), 'AbsTol', 2);
verifyEqual(testCase, data.raw470, 200*ones(1000, 1), 'AbsTol', 2);
verifyEqual(testCase, data.pulse_info.threshold405, 2.475, 'AbsTol', 0.1);    % halfway between off and on
verifySubstring(testCase, data.pulse_info.level_method405, 'medians');        % not the percentiles

% A single-sample flicker is not a pulse, and a single-sample dropout does
% not split a pulse.
raw.led405(50000) = 4.9;                                   % while the LED is off
raw.led405(find(on405, 1) + 4) = 0.05;                     % inside the first pulse
again = photometry_extract_pulses(raw, cfg);
verifyEqual(testCase, again.pulse_info.pulses405, 1000);
verifyEqual(testCase, again.time_s, data.time_s);
end

function testPulseProblemsGiveClearErrors(testCase)
rng(4);
fs = 1000;
n = 60*fs;
cycle = mod((0:n-1)', 20);
good.led405 = double(cycle < 10);
good.led470 = double(cycle >= 10);
good.pmt = randn(n, 1);
good.fs = fs;
good.crop_info = struct('start_hours_from_lights_on', -1);
cfg = struct('pulse_width_ms', 10, 'sample_rate_hz', 50, 'led405_variable', 'Raw_2', 'led470_variable', 'Raw_3');
photometry_extract_pulses(good, cfg);                      % these monitors are fine

% The 405 monitor is only noise (wrong channel, or the LED was never on).
raw = good;
raw.led405 = 0.05 + 0.01*randn(n, 1);
verifyError(testCase, @() photometry_extract_pulses(raw, cfg), 'photometry:Monitor');

% The 470 monitor is constant.
raw = good;
raw.led470 = zeros(n, 1);
verifyError(testCase, @() photometry_extract_pulses(raw, cfg), 'photometry:Monitor');

% The 470 monitor is noise, although the 405 monitor is fine.
raw = good;
raw.led470 = 0.05 + 0.01*randn(n, 1);
verifyError(testCase, @() photometry_extract_pulses(raw, cfg), 'photometry:Monitor');

% Good monitors, but the pulse rate in the settings is wrong.
wrong = cfg;
wrong.sample_rate_hz = 25;
verifyError(testCase, @() photometry_extract_pulses(good, wrong), 'photometry:Rate');
end

% ==========================================================================
% Step 5: alignment of 470 to 405
% ==========================================================================
function testAlignmentBridgesOnlyOneMissing470Pulse(testCase)
% 405 pulses every 20 ms, 470 pulses halfway between them. One 470 pulse is
% missing at one place (bridged) and two in a row at another (not bridged).
cfg = struct('phase_gap_sec', 1800, 'trim_start_sec', 0, 'trim_end_sec', 0, 'sample_rate_hz', 50);
signal = @(t) 5 + sin(2*pi*t/3);                           % a slow, smooth 470 signal
data.time_s = (0:999)'*0.02;
data.raw405 = ones(1000, 1);
data.time470_s = data.time_s + 0.01;
data.time470_s([300 600 601]) = [];                        % pulses at 5.99 s, 11.99 s and 12.01 s
data.raw470 = signal(data.time470_s);
data.crop_info = struct('start_hours_from_lights_on', -1);
data = verifyWarning(testCase, @() photometry_find_phases_and_trim(data, cfg), 'photometry:Missing470');

% No 470 value: the first sample (no 470 pulse before it) and the three
% 405 pulses between 11.97 s and 12.03 s.
verifyEqual(testCase, find(isnan(data.aligned470))', [1 600 601 602]);
verifyEqual(testCase, data.alignment_info.samples_without_470, 4);
verifyEqual(testCase, data.alignment_info.samples_without_470_while_405_on, 3);   % the first sample is at the start
% Bridged: the two 405 pulses around the single missing 470 pulse.
verifyEqual(testCase, data.alignment_info.samples_bridged_over_one_missing_470_pulse, 2);
has_value = ~isnan(data.aligned470);
verifyEqual(testCase, data.aligned470(has_value), signal(data.time_s(has_value)), 'AbsTol', 1e-3);
end

function test470DropoutBecomesMissing(testCase)
% The 470 LED is off from 300 s to 330 s while the 405 LED keeps flashing.
% No 470 values may be invented there.
folder = fullfile(testCase.TestData.folder, 'dropout');
cfg = make_settings(testCase);
cfg.input_file = make_synthetic_recording(folder, 'Drop470', [300 330]);
raw = photometry_load_and_crop(cfg);
data = photometry_extract_pulses(raw, cfg);
data = verifyWarning(testCase, @() photometry_find_phases_and_trim(data, cfg), 'photometry:Missing470');

in_gap = data.time_s >= 300 & data.time_s <= 330;
verifyEqual(testCase, nnz(in_gap), 1501);
verifyTrue(testCase, all(isnan(data.aligned470(in_gap))));
elsewhere = ~in_gap;
elsewhere(data.phase_windows(:, 1)) = false;              % the first sample of a phase has no 470 pulse before it
verifyTrue(testCase, all(isfinite(data.aligned470(elsewhere))));
verifyEqual(testCase, data.alignment_info.samples_without_470_outside_trims, 1501);
verifyEqual(testCase, size(data.phase_windows, 1), 2);    % the 405 pulses go on: still two phases

% The rest of the pipeline runs, and these samples get no dF/F.
data = continue_steps(data, cfg, 6);
verifyTrue(testCase, all(isnan(data.dF_F(in_gap))));
verifyTrue(testCase, all(isnan(data.dF_F_rolling_median(in_gap))));
verifyGreaterThan(testCase, mean(isfinite(data.dF_F)), 0.9);
end

function testShortLedPauseInsideAPhase(testCase)
% Both LEDs pause for 0.3 s inside phase 1 (as when the LED program
% restarts). This is not a fault: no warning, no new phase, a gap in time,
% and the filter does not run across the pause.
folder = fullfile(testCase.TestData.folder, 'pause');
cfg = make_settings(testCase);
cfg.input_file = make_synthetic_recording(folder, 'LedPause', [200 200.3]);
raw = photometry_load_and_crop(cfg);
data = photometry_extract_pulses(raw, cfg);
data = verifyWarningFree(testCase, @() photometry_find_phases_and_trim(data, cfg));

verifyEqual(testCase, size(data.phase_windows, 1), 2);
verifyEqual(testCase, numel(data.time_s), 72000 - 15);    % the 15 pulses of the pause do not exist
verifyEqual(testCase, data.alignment_info.short_pauses_inside_phases, 1);
verifyEqual(testCase, data.alignment_info.longest_short_pause_sec, 0.32, 'AbsTol', 1e-9);
verifyEqual(testCase, data.alignment_info.samples_without_470_while_405_on, 0);
% Only the first 405 pulse after the pause has no 470 pulse before it.
after_pause = find(data.time_s > 200, 1);
verifyEqual(testCase, data.time_s(after_pause), 200.3, 'AbsTol', 1e-9);
verifyEqual(testCase, find(isnan(data.aligned470))', [1 after_pause data.phase_windows(2, 1)]);

data = continue_steps(data, cfg, 6);
verifyEqual(testCase, data.lowpass_info.stretches, 3);     % phase 1 before and after the pause, phase 2
expected_missing = data.trim_mask;
expected_missing(after_pause) = true;
verifyEqual(testCase, isnan(data.dF_F), expected_missing);
% The filter creates no jump at the pause: the filtered 405 next to it
% equals the mean of the unfiltered 405 on the same side.
last_before = after_pause - 1;
first_after = after_pause + 1;
verifyEqual(testCase, data.filtered405(last_before), ...
    mean(data.cleaned405(last_before-9:last_before)), 'RelTol', 3e-3);
verifyEqual(testCase, data.filtered405(first_after), ...
    mean(data.cleaned405(first_after:first_after+9)), 'RelTol', 3e-3);
file = photometry_save_results(data, cfg);
loaded = load(file, 'results');
verifyEqual(testCase, loaded.results.phase_summary.other_missing(1), 1);
end

% ==========================================================================
% Step 7: low-pass filter
% ==========================================================================
function testFilterDoesNotMixPhases(testCase)
% Constant levels must stay exactly constant: nothing may leak across a
% phase boundary, a pulse gap or the trimmed edges.
[data, cfg, expected] = constant_level_data();
filtered = photometry_lowpass_filter(data, cfg);
too_short = false(2000, 1);
too_short(601:605) = true;                    % a stretch of 5 samples cannot be filtered
expected_butterworth = expected;
expected_butterworth(too_short) = NaN;
verifyEqual(testCase, filtered.filtered405, expected_butterworth, 'AbsTol', 1e-9);
verifyEqual(testCase, filtered.filtered470, 10*expected_butterworth, 'AbsTol', 1e-9);
verifyEqual(testCase, filtered.lowpass_info.stretches, 5);
verifyEqual(testCase, filtered.lowpass_info.samples_in_short_stretches, 5);

cfg.lowpass_method = 'rolling_mean';
filtered = photometry_lowpass_filter(data, cfg);
verifyEqual(testCase, filtered.filtered405, expected, 'AbsTol', 1e-12);
verifyEqual(testCase, filtered.filtered470, 10*expected, 'AbsTol', 1e-12);
verifyEqual(testCase, filtered.lowpass_info.stretches, 5);
end

function testRollingMeanIsCentred(testCase)
% A single spike is spread equally to both sides (odd window).
data.time_s = (0:999)'/50;
data.phase_windows = [1 1000];
data.cleaned405 = zeros(1000, 1);
data.cleaned405(500) = 1;
data.trimmed470 = data.cleaned405;
cfg = struct('lowpass_method', 'rolling_mean', 'sample_rate_hz', 50, 'butterworth_cutoff_hz', 3, ...
    'butterworth_order', 2, 'rolling_mean_window_sec', 1);
filtered = photometry_lowpass_filter(data, cfg);
verifyEqual(testCase, filtered.lowpass_info.window_samples, 51);
verifyEqual(testCase, find(filtered.filtered405 > 0)', 475:525);
verifyEqual(testCase, filtered.filtered405(475:499), flipud(filtered.filtered405(501:525)), 'AbsTol', 1e-15);
end

function testRollingMeanFilterOption(testCase)
cfg = make_settings(testCase);
cfg.lowpass_method = 'rolling_mean';
data = continue_steps(testCase.TestData.reference, cfg, 7);   % Step 7 onwards, with the other filter
verifyEqual(testCase, data.lowpass_info.method, 'rolling_mean');
% A rolling mean by hand, in the middle of phase 1 (far from any edge).
k = data.phase_windows(1, 1) + 10000;
verifyEqual(testCase, data.filtered470(k), mean(data.trimmed470(k-25:k+25)), 'AbsTol', 1e-12);
verifyGreaterThan(testCase, nnz(isfinite(data.dF_F)), 0.9*numel(data.dF_F));
cfg.lowpass_method = 'median';
verifyError(testCase, @() photometry_lowpass_filter(data, cfg), 'photometry:LowpassMethod');
end

% ==========================================================================
% The whole pipeline
% ==========================================================================
function testFullPipeline(testCase)
cfg = make_settings(testCase);
cfg.save_figures = true;                                   % also checks the figure code
truth = testCase.TestData.truth;
data = run_steps(cfg);

% Steps 3-5: two phases, 50 values per second, trims at the phase edges,
% and a 470 value for every sample outside the trims.
verifyEqual(testCase, size(data.phase_windows, 1), 2);
verifyEqual(testCase, data.pulse_info.measured_rate_hz, 50, 'RelTol', 1e-6);
verifyEqual(testCase, nnz(data.trim_mask), 2*(15 + 5)*50);
verifyTrue(testCase, all(isnan(data.dF_F(data.trim_mask))));
verifySubstring(testCase, data.pulse_info.level_method405, 'percentile');
verifyEqual(testCase, data.alignment_info.samples_without_470_outside_trims, 0);
verifyEqual(testCase, data.alignment_info.samples_bridged_over_one_missing_470_pulse, 0);

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

% Steps 7-8: the corrected channels hover around 1, by double exponential.
% This also holds for the first and last sample that are kept in each
% phase: the filter does not pull them towards the level of the other phase.
verifyEqual(testCase, median(data.corrected405, 'omitnan'), 1, 'AbsTol', 0.02);
verifyEqual(testCase, median(data.corrected470, 'omitnan'), 1, 'AbsTol', 0.02);
verifyTrue(testCase, all(data.bleaching_info.method == "double exponential"));
kept = ~data.trim_mask;
edges = find(kept & ([true; ~kept(1:end-1)] | [~kept(2:end); true]));
verifyEqual(testCase, numel(edges), 4);
verifyEqual(testCase, data.corrected405(edges), ones(4, 1), 'AbsTol', 0.02);
verifyEqual(testCase, data.corrected470(edges), ones(4, 1), 'AbsTol', 0.02);

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
verifyEqual(testCase, r.alignment.samples_without_470_outside_trims, 0);
% Zeitgeber time restarts at 0 at every lights ON; the recording starts at
% ZT-1, i.e. ZT 23 before the first lights ON (day 0).
verifyEqual(testCase, r.zt_hours, mod(-1 + data.time_s/3600, 24), 'AbsTol', 1e-9);
verifyTrue(testCase, all(r.zt_hours >= 0 & r.zt_hours < 24));
verifyEqual(testCase, r.zt_hours(1), 23, 'AbsTol', 1e-12);
verifyTrue(testCase, all(r.day == 0));    % this 55-min recording ends before the first lights ON
verifyEqual(testCase, height(r.phase_summary), 2);
verifyEqual(testCase, r.phase_summary.start_zt_hours(1), 23, 'AbsTol', 1e-12);
verifyTrue(testCase, all(r.artifact_suggestions.peak_zt_hours >= 0 & r.artifact_suggestions.peak_zt_hours < 24));
% The version of the code and the settings that were used are saved.
version_info = photometry_version();
verifyEqual(testCase, r.pipeline_version, version_info.version);
verifyEqual(testCase, r.format_version, version_info.format_version);
verifyEqual(testCase, r.code_checksum, version_info.code_checksum);
verifyEqual(testCase, r.settings.butterworth_cutoff_hz, 3);
verifyEqual(testCase, r.settings.trim_start_sec, 15);
files = photometry_output_files(cfg);
verifyEqual(testCase, files.save_number, 2);              % the folder of this run now holds results
verifyTrue(testCase, isfile(fullfile(cfg.output_folder, [cfg.filebase '_phase_summary.csv'])));
verifyTrue(testCase, isfile(fullfile(cfg.output_folder, [cfg.filebase '_artifact_suggestions.csv'])));
verifyTrue(testCase, isfile(fullfile(cfg.output_folder, [cfg.filebase '_sawtooth_windows.csv'])));
verifyEqual(testCase, numel(dir(fullfile(cfg.output_folder, 'figures', '*.png'))), 7);
end

function testManualRemovalIsExcludedFromTheFit(testCase)
cfg = make_settings(testCase);
reference = testCase.TestData.reference;
mask = false(size(reference.time_s));
mask(reference.phase_windows(1, 1) + (5000:5500)) = true;   % 10 s inside phase 1
data = continue_steps(reference, cfg, 10, mask);            % Step 10 onwards, with this removal
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

% ==========================================================================
% Step 14: saving
% ==========================================================================
function testSavingNeverOverwrites(testCase)
cfg = make_settings(testCase);
data = testCase.TestData.reference;
first = photometry_save_results(data, cfg);
second = photometry_save_results(data, cfg);
third = photometry_save_results(data, cfg);
verifyEqual(testCase, fileparts(first), cfg.output_folder);
verifyEqual(testCase, fileparts(second), [cfg.output_folder '_2']);
verifyEqual(testCase, fileparts(third), [cfg.output_folder '_3']);
verifyTrue(testCase, isfile(first) && isfile(second) && isfile(third));
end

function testSaveRefusesStepsThatAreOutOfDate(testCase)
cfg = make_settings(testCase);
data = testCase.TestData.reference;

% Step 7 is run again, but not the steps after it.
stale = photometry_lowpass_filter(data, cfg);
verifyError(testCase, @() photometry_save_results(stale, cfg), 'photometry:StepsOutOfDate');

% Step 11 is run again with another setting, but not Steps 12 and 13.
other = cfg;
other.irls_tuning_constant = 3;
stale = photometry_motion_correct_dff(data, other);
verifyError(testCase, @() photometry_save_results(stale, other), 'photometry:StepsOutOfDate');
verifyFalse(testCase, isfolder(cfg.output_folder));       % nothing was written

% When the later steps are run again as well, saving works.
fresh = continue_steps(data, other, 11);
verifyTrue(testCase, isfile(photometry_save_results(fresh, other)));
end

function testSavedSettingsAreTheOnesThatWereUsed(testCase)
cfg = make_settings(testCase);
data = testCase.TestData.reference;
cfg.trim_start_sec = 99;                  % changed after Step 5 had run with 15
cfg.rolling_median_window_sec = 120;      % changed after Step 13 had run with 60
file = verifyWarning(testCase, @() photometry_save_results(data, cfg), 'photometry:SettingsChanged');
loaded = load(file, 'results');
verifyEqual(testCase, loaded.results.settings.trim_start_sec, 15);
verifyEqual(testCase, loaded.results.settings.rolling_median_window_sec, 60);
verifyEqual(testCase, loaded.results.rolling_median.window_sec, 60);
end

function testVersionInformation(testCase)
info = photometry_version();
verifyNotEmpty(testCase, regexp(info.version, '^\d+\.\d+\.\d+$', 'once'));
verifyGreaterThanOrEqual(testCase, info.format_version, 2);
% The fingerprint of the code: 32 hexadecimal characters, the same every time.
verifyNotEmpty(testCase, regexp(info.code_checksum, '^[0-9a-f]{32}$', 'once'));
again = photometry_version();
verifyEqual(testCase, again.code_checksum, info.code_checksum);
end
