function summary = photometry_phase_summary(data)
%PHOTOMETRY_PHASE_SUMMARY One row per phase: how much data is left and its basic statistics.
%
%   summary = photometry_phase_summary(data)
%
% Columns
%   phase
%   start_day, start_zt_hours, end_day, end_zt_hours   start and end as
%                           Zeitgeber time (0-24, restarting at every
%                           lights ON) and day (see photometry_zt)
%   duration_min
%   samples                 samples in the phase
%   trimmed_samples         set to missing by the edge trims (Step 5)
%   removed_by_hand         removed in the manual review (Step 10)
%   other_missing           missing for another reason (e.g. a phase
%                           excluded from the bleaching correction)
%   valid_samples, valid_percent   samples with a dF/F value
%   bleaching_method        what Step 8 used in this phase
%   sawtooth_windows_removed / sawtooth_windows   Step 6, windows changed / all windows
%   artifact_suggestions    automatic suggestions in this phase (Step 9)
%   mean_dF_F_pct, sd_dF_F_pct            dF/F without rolling median (%)
%   sd_dF_F_rolling_median_pct            dF/F after the rolling median (%)

n = size(data.phase_windows, 1);
h0 = data.crop_info.start_hours_from_lights_on;   % time zero in hours from the first lights ON
trimmed = logical(data.trim_mask(:));
by_hand = logical(data.manual_mask(:)) & ~trimmed;
valid = isfinite(data.dF_F(:));
other = ~valid & ~trimmed & ~by_hand;

[start_zt, start_day, end_zt, end_day, duration_min, samples, trimmed_n, by_hand_n, other_n, ...
    valid_n, saw_applied, saw_total, suggestions, mean_pct, sd_pct, sd_median_pct] = deal(nan(n, 1));
windows = table();
if isfield(data, 'sawtooth_info') && isfield(data.sawtooth_info, 'windows')
    windows = data.sawtooth_info.windows;
end
for p = 1:n
    idx = data.phase_windows(p, 1):data.phase_windows(p, 2);
    [start_zt(p), start_day(p)] = photometry_zt(h0 + data.time_s(idx(1))/3600);
    [end_zt(p), end_day(p)] = photometry_zt(h0 + data.time_s(idx(end))/3600);
    duration_min(p) = (data.time_s(idx(end)) - data.time_s(idx(1)))/60;
    samples(p) = numel(idx);
    trimmed_n(p) = nnz(trimmed(idx));
    by_hand_n(p) = nnz(by_hand(idx));
    other_n(p) = nnz(other(idx));
    valid_n(p) = nnz(valid(idx));
    if ~isempty(windows)
        in_phase = windows.phase == p;
        saw_applied(p) = nnz(windows.applied(in_phase));
        saw_total(p) = nnz(in_phase);
    else
        saw_applied(p) = 0; saw_total(p) = 0;
    end
    suggestions(p) = nnz(data.artifact_suggestions.phase == p);
    y = 100*data.dF_F(idx); y = y(isfinite(y));
    if ~isempty(y), mean_pct(p) = mean(y); sd_pct(p) = std(y); end
    y = 100*data.dF_F_rolling_median(idx); y = y(isfinite(y));
    if ~isempty(y), sd_median_pct(p) = std(y); end
end

summary = table((1:n)', start_day, start_zt, end_day, end_zt, duration_min, samples, trimmed_n, ...
    by_hand_n, other_n, valid_n, 100*valid_n./samples, data.bleaching_info.method, saw_applied, ...
    saw_total, suggestions, mean_pct, sd_pct, sd_median_pct, 'VariableNames', { ...
    'phase', 'start_day', 'start_zt_hours', 'end_day', 'end_zt_hours', 'duration_min', ...
    'samples', 'trimmed_samples', ...
    'removed_by_hand', 'other_missing', 'valid_samples', 'valid_percent', 'bleaching_method', ...
    'sawtooth_windows_removed', 'sawtooth_windows', 'artifact_suggestions', ...
    'mean_dF_F_pct', 'sd_dF_F_pct', 'sd_dF_F_rolling_median_pct'});
end
