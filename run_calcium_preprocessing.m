%% CALCIUM FIBRE-PHOTOMETRY PREPROCESSING  -  START HERE
%
% HOW TO RUN
%   1. In MATLAB, open the folder that contains this file.
%   2. Open this file and click "Run" (Editor tab).
%   3. Answer the dialogs: choose your raw MAT recording, then type the time
%      the lights turn ON. Everything else runs by itself.
%
% WHAT IT DOES (one section per step; read the comments of each section)
%    1. Settings (change them here, nowhere else)
%    2. Choose the recording and type lights ON
%    3. Load the raw recording and cut it to the analysis window
%    4. Extract one 405 and one 470 value from every LED pulse
%    5. Find the recording phases, align 470 to 405, trim the phase edges
%    6. Remove the sawtooth from the 405 channel
%    7. Low-pass filter (default: 3-Hz Butterworth; option: rolling mean)
%    8. Correct photobleaching (double exponential)
%    9. Detect artifacts automatically (suggestions only)
%   10. Remove artifacts by hand (optional, one figure per phase)
%   11. Motion correction (IRLS fit of 405 to 470) and dF/F
%   12. z-scores (standard and robust)
%   13. 1-minute rolling median (a second version of the results)
%   14. Save the results
%
% REQUIREMENTS
%   MATLAB R2020a or newer with the Signal Processing, Statistics and
%   Machine Learning, and Curve Fitting toolboxes. See README.md.
%
% All helper functions are in the "Functions" folder next to this file.
% Each one starts with a comment that explains what it does; type, for
% example, "help photometry_correct_bleaching" in the Command Window.

%% 0. Prepare MATLAB
clearvars;   % start from an empty Workspace
clc;         % clear the Command Window
pipeline_folder = fileparts(mfilename('fullpath'));
addpath(fullfile(pipeline_folder, 'Functions'));   % so MATLAB finds the helper functions
photometry_check_requirements();                    % stops now if a toolbox is missing

%% 1. Settings  -  the only place you need to change anything
% The defaults below are the values used for our recordings. If you are
% new to this pipeline, keep them and only answer the dialogs.

% --- How the raw recording was acquired --------------------------------
cfg.raw_sampling_rate_hz = 1000;  % samples per second of the raw channels
cfg.pulse_width_ms       = 10;    % length of one LED pulse (milliseconds)
cfg.sample_rate_hz       = 50;    % 405 (or 470) pulses per second; = values per second after Step 4
cfg.pmt_variable    = 'Raw';      % name in the MAT file: photodetector (PMT) signal
cfg.led405_variable = 'Raw_2';    % name in the MAT file: 405-nm LED monitor (shows when 405 is on)
cfg.led470_variable = 'Raw_3';    % name in the MAT file: 470-nm LED monitor (shows when 470 is on)

% --- Which part of the recording to analyse (Step 3) -------------------
cfg.lights_on              = '08:00'; % default answer shown in the "Lights ON" dialog
cfg.hours_before_lights_on = 1;       % analysis starts this many hours before lights ON (1 = ZT-1, i.e. ZT 23)
cfg.duration_hours         = 49;      % hours to keep; Inf = keep everything to the end
cfg.recording_start        = '';      % leave empty: the clock time of the first sample is read
                                      % from the MAT file or its EDF. Type it (e.g. '06:56:16')
                                      % only if your files do not store it.

% --- Phases and trimming (Step 5) --------------------------------------
cfg.phase_gap_sec  = 30*60;  % a pause in the LED pulses longer than this starts a new phase (seconds)
cfg.trim_start_sec = 15;     % ignore the first 15 s of every phase (LED switching on)
cfg.trim_end_sec   = 5;      % ignore the last 5 s of every phase

% --- Sawtooth removal from the 405 channel (Step 6) --------------------
cfg.remove_sawtooth          = true;  % false = skip this step
cfg.sawtooth_period_sec      = 23.5;  % expected period of the sawtooth (seconds)
cfg.sawtooth_search_sec      = 1;     % the period is searched within +/- this (seconds)
cfg.sawtooth_window_sec      = 600;   % the shape is re-estimated in sliding 10-minute windows
cfg.sawtooth_period_span_sec = 1800;  % the period of each window is found over 30 minutes around it
cfg.sawtooth_min_snr         = 4;     % a window is changed only if the sawtooth is >= 4 x the noise
cfg.sawtooth_harmonics       = 8;     % harmonics used to find and judge the sawtooth

% --- Low-pass filter (Step 7) ------------------------------------------
cfg.lowpass_method          = 'butterworth';  % 'butterworth' (default) or 'rolling_mean'
cfg.butterworth_cutoff_hz   = 3;              % Butterworth cut-off frequency (Hz)
cfg.butterworth_order       = 2;              % Butterworth order
cfg.rolling_mean_window_sec = 1;              % window of the rolling mean (seconds), only used
                                              % when cfg.lowpass_method = 'rolling_mean'

% --- Photobleaching correction (Step 8) --------------------------------
cfg.min_fit_samples     = 20;   % fewer valid samples than this in a phase: no fit
cfg.low_signal_fraction = 0.2;  % a phase whose 405 median is below 20% of the whole recording's
                                % median has lost its signal and is excluded (set to missing)

% --- Automatic artifact detection (Step 9) -----------------------------
cfg.artifact_prominence_mad        = 3.5; % candidate peaks: at least 3.5 robust SDs prominent
cfg.artifact_huge_peak_mad         = 8;   % artifacts: candidates far above the typical peak (robust SDs)
cfg.artifact_min_peak_distance_sec = 1;   % candidate peaks at least 1 s apart
cfg.artifact_width_fraction        = 0.5; % an artifact lasts while the trace is above half its peak
cfg.artifact_max_duration_sec      = 40;  % longer events are not suggested (probably real activity)

% --- Motion correction (Step 11) ----------------------------------------
cfg.irls_tuning_constant = 1.4;  % IRLS (Tukey bisquare) tuning constant c; smaller = stricter

% --- Rolling median (Step 13) ------------------------------------------
cfg.rolling_median_window_sec = 60;  % 1 minute

% --- Figures and saving ------------------------------------------------
cfg.show_figures    = true;   % show the quality-control figures
cfg.save_figures    = false;  % also save them as PNG files in the results folder
cfg.max_plot_points = 20000;  % figures only: long traces are drawn with fewer points (the
                              % analysis always uses every sample)
cfg.save_trace_csv  = false;  % also save every sample as a CSV file (large: ~1 GB for 49 h)
cfg.output_root     = '';     % empty = a "calcium_preprocessing_results" folder next to the raw file

cfg.pipeline_version = '1.0.0';

%% 2. Choose the recording and type lights ON
% Dialogs ask for the raw MAT file and the lights-ON time, read the
% recording start, show where the recording will be cut, and ask whether
% you want to remove artifacts by hand (Step 10).
cfg = photometry_select_recording(cfg);
if isempty(cfg)
    disp('Cancelled. Nothing was processed.');
    return;
end
pipeline_timer = tic;

%% 3. Load the raw recording and cut it to the analysis window
% The analysis window starts cfg.hours_before_lights_on hours before
% lights ON (ZT-1 by default) and lasts cfg.duration_hours hours. Only the
% three channels named in Step 1 are loaded.
raw = photometry_load_and_crop(cfg);

%% 4. Extract one 405 and one 470 value from every LED pulse
% The two LEDs flash in turn. The LED monitor channels show when each LED
% is on; during each pulse the median of the photodetector (PMT) signal is
% taken. Result: two signals of cfg.sample_rate_hz values per second,
% data.raw405 (isosbestic control) and data.raw470 (calcium signal).
data = photometry_extract_pulses(raw, cfg);
clear raw;   % the raw 1000-Hz channels are large and no longer needed
photometry_plot_qc('extracted', data, cfg);   % Figure 1

%% 5. Find the recording phases, align 470 to 405, and trim the phase edges
% Phases: the LEDs were switched off between recording blocks; every pause
% longer than cfg.phase_gap_sec starts a new phase. Each phase is corrected
% on its own in the next steps.
% Alignment: the 470 pulses fall between the 405 pulses; 470 is
% interpolated onto the 405 pulse times so both channels share one time axis.
% Trimming: the first and last seconds of each phase are marked as missing
% (data.trim_mask). Nothing is deleted: missing samples are NaN, so the
% time of every sample stays correct.
data = photometry_find_phases_and_trim(data, cfg);

%% 6. Remove the sawtooth from the 405 channel
% Our 405 channel carries a small sawtooth-shaped ripple (period ~23.5 s)
% that is not in the 470 channel. Without this step, the motion correction
% (Step 11) would copy it, upside down, into dF/F. Its shape is estimated
% in sliding 10-minute windows and subtracted from 405 only. A window is
% changed only where the sawtooth is clearly present, so this step is safe
% for recordings without it. Set cfg.remove_sawtooth = false to skip it.
data = photometry_remove_sawtooth(data, cfg);
photometry_plot_qc('sawtooth', data, cfg);    % Figure 2

%% 7. Low-pass filter
% Removes fast noise (e.g. the heartbeat at ~11 Hz) from both channels.
%   'butterworth' (default): 2nd-order Butterworth, 3 Hz, run forwards and
%                            backwards, so the signal is not shifted in time.
%   'rolling_mean':          centred rolling mean of cfg.rolling_mean_window_sec
%                            seconds, used INSTEAD of the Butterworth.
data = photometry_lowpass_filter(data, cfg);
photometry_plot_qc('lowpass', data, cfg);     % Figure 3

%% 8. Correct photobleaching (double exponential)
% Both signals slowly decay as the fluorophore bleaches. In every phase,
% a double exponential a*exp(b*t) + c*exp(d*t) is fitted to each channel,
% and the channel is divided by it. Afterwards both channels hover around 1.
% If the fit fails in a phase, a straight line is used there instead (a
% warning says so).
data = photometry_correct_bleaching(data, cfg);
photometry_plot_qc('bleaching', data, cfg);   % Figure 4

%% 9. Detect artifacts automatically (suggestions only)
% A preliminary motion correction (IRLS, as in Step 11) is made, and
% unusually large and short deflections are marked. These marks are only
% SUGGESTIONS: they are shown in red in Figure 5 and in the review figures
% of Step 10, and saved in a CSV file. Nothing is removed here.
data = photometry_detect_artifacts(data, cfg);
photometry_plot_qc('artifacts', data, cfg);   % Figure 5

%% 10. Remove artifacts by hand (optional)
% If you chose "Review" in Step 2, one figure opens per phase:
%   - drag over bad stretches of the 470 trace (green) to select them
%     (red dots are the automatic suggestions of Step 9; hold Shift to
%     select several stretches; after zooming, click the Brush icon in the
%     figure toolbar again before selecting);
%   - Apply : the selected stretches become missing (NaN) in both channels;
%   - Skip  : no change in this phase;
%   - Done  : stop reviewing; the remaining phases are not changed.
% The removed windows are listed in data.manual_windows and saved.
data = photometry_review_artifacts(data, cfg);

%% 11. Motion correction (IRLS) and dF/F
% Movement changes both channels in the same way, but only 470 reports
% calcium. One straight line, fitted 405 = slope x 405 + intercept, is
% fitted to all valid samples by IRLS (iteratively reweighted least
% squares, Tukey bisquare weights): samples far from the line, such as
% calcium transients, get weight 0 and do not pull the fit. Then
%   dF/F = (470 - fitted 405) / fitted 405
% (a fraction; x100 gives percent). Trimmed samples, excluded phases and
% the stretches removed in Step 10 are missing (NaN).
data = photometry_motion_correct_dff(data, cfg);
photometry_plot_qc('motion', data, cfg);      % Figure 6

%% 12. z-scores (standard and robust)
% Standard z = (dF/F - mean) / SD
% Robust z   = (dF/F - median) / (1.4826 x MAD)   (less affected by large transients)
% One mean, SD, median and MAD over all valid samples of the recording.
% This puts every animal on the same scale, but it also removes real
% differences in overall signal size between animals (see README.md,
% "A note on z-scores").
[data.z, data.z_robust, data.z_info] = photometry_zscore(data.dF_F);

%% 13. 1-minute rolling median (a second version of the results)
% A centred rolling median of dF/F over cfg.rolling_median_window_sec
% seconds is SUBTRACTED from dF/F. This removes slow changes (slower than
% about a minute) and keeps fast transients. It never crosses a phase
% boundary or a recording gap. Both versions are saved; choose the one
% that suits your question (slow changes in the signal level are only in
% the version WITHOUT the rolling median).
[data.dF_F_rolling_median, data.rolling_median_baseline] = photometry_rolling_median( ...
    data.dF_F, data.time_s, data.phase_windows, cfg.sample_rate_hz, cfg.rolling_median_window_sec);
[data.z_rolling_median, data.z_robust_rolling_median, data.z_info_rolling_median] = ...
    photometry_zscore(data.dF_F_rolling_median);
photometry_plot_qc('final', data, cfg);       % Figure 7

%% 14. Save the results
% Writes a new results folder (nothing is overwritten) with:
%   <recording>_calcium_preprocessed.mat   the results (variable "results")
%   <recording>_phase_summary.csv          one row per phase
%   <recording>_artifact_suggestions.csv   the automatic suggestions (Step 9)
%   <recording>_manual_removed_windows.csv the stretches you removed (Step 10)
%   <recording>_sawtooth_windows.csv       the sawtooth windows (Step 6)
% See README.md ("Output") for every field of "results".
output_file = photometry_save_results(data, cfg);
fprintf('\nFinished in %.1f minutes.\nResults saved in:\n  %s\n', toc(pipeline_timer)/60, output_file);
