function output_file = photometry_save_results(data, cfg)
%PHOTOMETRY_SAVE_RESULTS Save the results (MAT file and CSV tables).
%
%   output_file = photometry_save_results(data, cfg)
%
% Writes into cfg.output_folder (a new folder for every run, so nothing is
% overwritten); file names: see photometry_output_files.
%
% The MAT file holds one variable, "results". Every per-sample field is a
% column vector with one value per 405 pulse (cfg.sample_rate_hz values
% per second); NaN = missing (trimmed, removed or excluded).
%
%   results.time_s            seconds since the start of the analysis window
%                             (gaps between phases are kept)
%   results.zt_hours          the same time as Zeitgeber time (lights ON = 0)
%   results.phase_windows     [first last] sample number of each phase
%
%   results.no_rolling_median.dF_F       dF/F (fraction; x100 = %)
%   results.no_rolling_median.z          standard z-score of that dF/F
%   results.no_rolling_median.z_robust   robust z-score (median / MAD)
%   results.no_rolling_median.z_info     mean, SD, median and robust SD used
%
%   results.rolling_median.dF_F          dF/F minus its 1-minute rolling median
%   results.rolling_median.z, .z_robust, .z_info   z-scores of that
%   results.rolling_median.window_sec    the window (60 s)
%
%   results.valid_mask, .trim_mask, .manual_mask, .artifact_suggestion_mask
%   results.phase_summary, .artifact_suggestions, .manual_windows (tables)
%   results.motion_fit, .bleaching, .sawtooth, .lowpass, .pulse_info
%   results.crop_info         recording start, lights ON, where the window starts
%                             (offset_sec = seconds after the recording start)
%   results.settings          every setting used (cfg)
%
% To match the EEG (or any signal recorded on the same clock), the time of a
% sample since the START OF THE RAW RECORDING is
%   results.time_s + results.crop_info.offset_sec

files = photometry_output_files(cfg);
if files.longest_path > 259
    error('photometry:PathTooLong', ['The results path is too long for Windows (%d of at most ' ...
        '259 characters). Set cfg.output_root to a shorter folder.'], files.longest_path);
end
if ~isfolder(files.folder), mkdir(files.folder); end

zt0 = data.crop_info.reference_zt;
results = struct();
results.description = ['Calcium fibre-photometry preprocessing: LED-pulse extraction, ' ...
    'phase-edge trims, 405 sawtooth removal, low-pass filter, double-exponential bleaching ' ...
    'correction, manual artifact removal, IRLS motion correction, dF/F, standard and robust ' ...
    'z-scores, without and with a rolling median.'];
results.recording = cfg.filebase;
results.input_file = cfg.input_file;
results.created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
results.pipeline_version = cfg.pipeline_version;
results.matlab_version = version;
results.sample_rate_hz = cfg.sample_rate_hz;

% ---- Time --------------------------------------------------------------------
results.time_s = data.time_s(:);
results.zt_hours = zt0 + data.time_s(:)/3600;
results.phase_windows = data.phase_windows;
results.phase_names = data.phase_names;

% ---- The two versions of the results -----------------------------------------
results.no_rolling_median.dF_F = data.dF_F(:);
results.no_rolling_median.z = data.z(:);
results.no_rolling_median.z_robust = data.z_robust(:);
results.no_rolling_median.z_info = data.z_info;

results.rolling_median.window_sec = cfg.rolling_median_window_sec;
results.rolling_median.dF_F = data.dF_F_rolling_median(:);
results.rolling_median.z = data.z_rolling_median(:);
results.rolling_median.z_robust = data.z_robust_rolling_median(:);
results.rolling_median.z_info = data.z_info_rolling_median;

% ---- Which samples were used -------------------------------------------------
results.valid_mask = data.valid_mask(:);
results.trim_mask = data.trim_mask(:);
results.manual_mask = data.manual_mask(:);
results.artifact_suggestion_mask = data.artifact_suggestion_mask(:);

% ---- Tables and details of each step -------------------------------------------
results.phase_summary = photometry_phase_summary(data);
results.artifact_suggestions = data.artifact_suggestions;
results.manual_windows = data.manual_windows;
results.motion_fit = data.motion_fit;
results.bleaching = data.bleaching_info;
results.sawtooth.removed = data.sawtooth_removed;
results.sawtooth.windows = data.sawtooth_info.windows;
if isfield(data.sawtooth_info, 'settings'), results.sawtooth.settings = data.sawtooth_info.settings; end
results.lowpass = data.lowpass_info;
results.pulse_info = data.pulse_info;
results.crop_info = data.crop_info;
results.settings = cfg;

% ---- Write --------------------------------------------------------------------
fprintf('Saving results ...\n');
save(files.mat, 'results', '-v7.3');   % -v7.3: needed for files over 2 GB; readable in part
writetable(results.phase_summary, files.phase_summary);
writetable(results.artifact_suggestions, files.artifact_suggestions);
if ~isempty(results.manual_windows)
    writetable(results.manual_windows, files.manual_windows);
end
if ~isempty(results.sawtooth.windows)
    writetable(results.sawtooth.windows, files.sawtooth_windows);
end
if cfg.save_trace_csv
    fprintf('Writing every sample to a CSV file (this can take a few minutes) ...\n');
    trace = table(results.time_s, results.zt_hours, ...
        results.no_rolling_median.dF_F, results.no_rolling_median.z, results.no_rolling_median.z_robust, ...
        results.rolling_median.dF_F, results.rolling_median.z, results.rolling_median.z_robust, ...
        'VariableNames', {'time_s', 'zt_hours', 'dF_F', 'z', 'z_robust', ...
        'dF_F_rolling_median', 'z_rolling_median', 'z_robust_rolling_median'});
    writetable(trace, files.trace_csv);
end
output_file = files.mat;
end
