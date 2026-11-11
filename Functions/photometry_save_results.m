function output_file = photometry_save_results(data, cfg)
%PHOTOMETRY_SAVE_RESULTS Save the results (MAT file and CSV tables).
%
%   output_file = photometry_save_results(data, cfg)
%
% Every save goes into a folder that holds no results yet, so nothing is
% ever overwritten: cfg.output_folder the first time, <folder>_2 if you
% save again in the same MATLAB session (see photometry_output_files).
%
% Two checks are made before anything is written:
%   - Every step must have been run after the steps before it. If you ran
%     one section of the main script again, the later sections must be run
%     again too. Otherwise nothing is saved and the message names the steps
%     that are out of date.
%   - The saved settings are the ones that were really used. If a setting
%     was changed after its step had run, the value that was used is saved
%     and a warning lists the settings concerned.
%
% The MAT file holds one variable, "results". Every per-sample field is a
% column vector with one value per 405 pulse (sample_rate_hz values per
% second); NaN = missing (trimmed, removed or excluded).
%
%   results.pipeline_version  version of the code (photometry_version)
%   results.format_version    version of this list of fields (CHANGELOG.md)
%   results.code_checksum     fingerprint of the functions that were used
%
%   results.time_s            seconds since the start of the analysis window
%                             (gaps between phases are kept; keeps increasing,
%                             so use it to put samples in order or to plot)
%   results.zt_hours          Zeitgeber time in hours, 0 to 24: restarts at 0
%                             at every lights ON (ZT 24 = ZT 0 of the next day)
%   results.day               which lights ON the sample follows: 1, 2, 3, ...
%                             (0 = before the first lights ON, e.g. ZT 23 when
%                             the analysis starts 1 hour before lights ON)
%   results.phase_windows     [first last] sample number of each phase
%
%   results.no_rolling_median.dF_F       dF/F (fraction; x100 = %)
%   results.no_rolling_median.z          standard z-score of that dF/F
%   results.no_rolling_median.z_robust   robust z-score (median / MAD)
%   results.no_rolling_median.z_info     mean, SD, median and robust SD used
%
%   results.rolling_median.dF_F          dF/F minus its 1-minute rolling median
%   results.rolling_median.z, .z_robust, .z_info   z-scores of that
%   results.rolling_median.window_sec    the window that was used (60 s)
%
%   results.valid_mask, .trim_mask, .manual_mask, .artifact_suggestion_mask
%   results.phase_summary, .artifact_suggestions, .manual_windows (tables)
%   results.motion_fit, .bleaching, .sawtooth, .lowpass, .alignment, .pulse_info
%   results.crop_info         recording start, lights ON, where the window starts
%                             (offset_sec = seconds after the recording start)
%   results.settings          every setting, with the values that were used
%
% To match the EEG (or any signal recorded on the same clock), the time of a
% sample since the START OF THE RAW RECORDING is
%   results.time_s + results.crop_info.offset_sec

check_steps_are_up_to_date(data);
[settings, changed] = settings_that_were_used(cfg, data);
if ~isempty(changed)
    warning('photometry:SettingsChanged', ['These settings were changed after the step that uses ' ...
        'them had run: %s.\nThe saved settings list the values that were actually used.'], ...
        strjoin(changed, ', '));
end

files = photometry_output_files(cfg);
if files.longest_path > 259
    error('photometry:PathTooLong', ['The results path is too long for Windows (%d of at most ' ...
        '259 characters). Set cfg.output_root to a shorter folder.'], files.longest_path);
end
if files.save_number > 1
    fprintf(['Results were already saved in\n  %s\nThey are kept. This save goes to a new folder ' ...
        '(ending in _%d).\n'], cfg.output_folder, files.save_number);
end
if ~isfolder(files.folder), mkdir(files.folder); end

version_info = photometry_version();
h0 = data.crop_info.start_hours_from_lights_on;   % time zero in hours from the first lights ON
results = struct();
results.description = ['Calcium fibre-photometry preprocessing: LED-pulse extraction, ' ...
    'phase-edge trims, 405 sawtooth removal, low-pass filter, double-exponential bleaching ' ...
    'correction, manual artifact removal, IRLS motion correction, dF/F, standard and robust ' ...
    'z-scores, without and with a rolling median.'];
results.recording = cfg.filebase;
results.input_file = settings.input_file;
results.created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
results.pipeline_version = version_info.version;
results.format_version = version_info.format_version;
results.code_checksum = version_info.code_checksum;
results.matlab_version = version;
results.sample_rate_hz = settings.sample_rate_hz;

% ---- Time --------------------------------------------------------------------
results.time_s = data.time_s(:);
[results.zt_hours, results.day] = photometry_zt(h0 + data.time_s(:)/3600);
results.phase_windows = data.phase_windows;
results.phase_names = data.phase_names;

% ---- The two versions of the results -----------------------------------------
results.no_rolling_median.dF_F = data.dF_F(:);
results.no_rolling_median.z = data.z(:);
results.no_rolling_median.z_robust = data.z_robust(:);
results.no_rolling_median.z_info = data.z_info;

results.rolling_median.window_sec = settings.rolling_median_window_sec;
if isfield(data, 'rolling_median_info')
    results.rolling_median.window_samples = data.rolling_median_info.window_samples;
end
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
results.alignment = data.alignment_info;
results.pulse_info = data.pulse_info;
results.crop_info = data.crop_info;
results.settings = settings;

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
    trace = table(results.time_s, results.day, results.zt_hours, ...
        results.no_rolling_median.dF_F, results.no_rolling_median.z, results.no_rolling_median.z_robust, ...
        results.rolling_median.dF_F, results.rolling_median.z, results.rolling_median.z_robust, ...
        'VariableNames', {'time_s', 'day', 'zt_hours', 'dF_F', 'z', 'z_robust', ...
        'dF_F_rolling_median', 'z_rolling_median', 'z_robust_rolling_median'});
    writetable(trace, files.trace_csv);
end
output_file = files.mat;
end

% ==========================================================================
function check_steps_are_up_to_date(data)
% Stop if the data mix old and new calculations.

% Steps 4 to 11: every function marks its step as done and all later steps
% as not done (photometry_note_step).
steps = 4:11;
if isfield(data, 'steps_done')
    out_of_date = steps(~data.steps_done(steps));
else
    out_of_date = steps;
end
if ~isempty(out_of_date)
    error('photometry:StepsOutOfDate', ['Nothing was saved, because Step(s) %s of the main script ' ...
        'are out of date: an earlier step was run again after them. Run these steps again, in ' ...
        'order, then Steps 12 to 14.'], strjoin(compose('%d', out_of_date), ', '));
end

% Steps 12 and 13 work on data.dF_F directly: check that the z-scores and
% the rolling median were calculated from the dF/F that is saved now.
valid = isfinite(data.dF_F(:));
n_valid = nnz(valid);
current = data.z_info.number_of_valid_samples == n_valid && ...
    data.z_info_rolling_median.number_of_valid_samples == n_valid && ...
    isequal(isfinite(data.dF_F_rolling_median(:)), valid);
if current && n_valid > 0
    current = abs(data.z_info.mean - mean(data.dF_F(valid))) <= 1e-9 && ...
        abs(data.z_info_rolling_median.mean - mean(data.dF_F_rolling_median(valid))) <= 1e-9;
end
if current && n_valid > 0 && isfield(data, 'rolling_median_baseline')
    rebuilt = data.dF_F_rolling_median(valid) + data.rolling_median_baseline(valid);
    current = max(abs(rebuilt - data.dF_F(valid))) <= 1e-9;
end
if ~current
    error('photometry:StepsOutOfDate', ['Nothing was saved, because the z-scores or the rolling ' ...
        'median (Steps 12 and 13) do not belong to the current dF/F: Step 11 was run again after ' ...
        'them. Run Steps 12 to 14 again.']);
end
end

function [settings, changed] = settings_that_were_used(cfg, data)
% The settings to save: cfg, with every processing setting replaced by the
% value its step really used. changed lists the settings that differ.
settings = cfg;
changed = {};
if isfield(data, 'applied_settings')
    applied = data.applied_settings;
else
    applied = struct();
end
if isfield(data, 'rolling_median_info')            % Step 13 is not a function with a data structure
    applied.rolling_median_window_sec = data.rolling_median_info.window_sec;
end
names = fieldnames(applied);
for k = 1:numel(names)
    if ~isfield(cfg, names{k}) || ~isequaln(cfg.(names{k}), applied.(names{k}))
        changed{end+1} = names{k}; %#ok<AGROW>
    end
    settings.(names{k}) = applied.(names{k});
end
% The version belongs to the code, not to the settings (photometry_version).
if isfield(settings, 'pipeline_version'), settings = rmfield(settings, 'pipeline_version'); end
end
