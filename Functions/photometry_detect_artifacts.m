function data = photometry_detect_artifacts(data, cfg)
%PHOTOMETRY_DETECT_ARTIFACTS Suggest likely movement artifacts (nothing is removed).
%
%   data = photometry_detect_artifacts(data, cfg)
%
% 1. Preliminary motion correction: 405 is fitted to 470 with the same
%    IRLS method as the final correction (Step 11), and the fit is
%    subtracted: residual = corrected 470 - fitted 405.
% 2. In each phase, peaks of |residual - median| are found (both upward
%    and downward deflections) that stand out by at least
%    cfg.artifact_prominence_mad robust SDs.
% 3. Among those peaks, only the unusually large ones are kept: higher
%    than the median peak + cfg.artifact_huge_peak_mad x the MAD of the
%    peaks.
% 4. Each kept peak is widened while the residual stays above
%    cfg.artifact_width_fraction (half) of the peak. Events longer than
%    cfg.artifact_max_duration_sec are dropped (more likely real activity).
%
% These are SUGGESTIONS only. They are shown in red in Figure 5 and in the
% review figures of Step 10; you decide there what to remove.
%
% Output
%   data.preliminary_residual        the residual of step 1
%   data.preliminary_fit             [slope intercept] of the preliminary fit
%   data.artifact_suggestion_mask    true inside a suggested event
%   data.artifact_suggestions        one row per event (phase, start, end and
%                                    peak time in seconds, peak time as ZT
%                                    hours (0-24) and day, duration, peak size)

% ---- 1. Preliminary motion correction (IRLS) ------------------------------
valid = isfinite(data.corrected405) & isfinite(data.corrected470);
if nnz(valid) < 2, error('photometry:Artifacts', 'Too few valid samples to fit 405 to 470.'); end
fprintf('Preliminary motion correction (IRLS) for the artifact suggestions ...\n');
data.preliminary_fit = photometry_irls_fit(data.corrected405(valid), data.corrected470(valid), ...
    cfg.irls_tuning_constant);
data.preliminary_residual = data.corrected470 - polyval(data.preliminary_fit, data.corrected405);

% ---- 2-4. Detect events, phase by phase -----------------------------------
robust_sd = @(y) 1.4826*mad(y, 1);
min_distance = max(1, round(cfg.artifact_min_peak_distance_sec*cfg.sample_rate_hz));
min_samples = max(10, round(40*cfg.sample_rate_hz));    % phases with < 40 s of data are skipped
h0 = data.crop_info.start_hours_from_lights_on;   % time zero in hours from the first lights ON
data.artifact_suggestion_mask = false(size(data.preliminary_residual));
rows = cell(0, 1);
for p = 1:size(data.phase_windows, 1)
    idx = (data.phase_windows(p, 1):data.phase_windows(p, 2))';
    y = data.preliminary_residual(idx);
    keep = ~isnan(y);
    if nnz(keep) < min_samples, continue; end
    y = y(keep);
    full_idx = idx(keep);                     % sample numbers in the whole recording

    centre = median(y);
    noise = robust_sd(y);
    if noise == 0, noise = std(y); end
    if noise == 0, continue; end              % a flat phase: nothing to detect
    deflection = abs(y - centre);             % upward and downward deflections
    prominence = cfg.artifact_prominence_mad*robust_sd(deflection);
    if prominence == 0, prominence = cfg.artifact_prominence_mad*std(deflection); end
    [peaks, locations] = findpeaks(deflection, 'MinPeakProminence', prominence, ...
        'MinPeakDistance', min_distance);
    if isempty(peaks), continue; end

    % Only peaks far above the typical peak are suggested.
    peak_median = median(peaks);
    peak_mad = mad(peaks, 1);
    if peak_mad == 0, peak_mad = std(peaks); end
    if peak_mad == 0, peak_mad = eps; end
    threshold = peak_median + cfg.artifact_huge_peak_mad*peak_mad;

    for k = find(peaks >= threshold)'
        loc = locations(k);
        % Widen the event while the residual stays above half the peak (same sign).
        above = ((y - centre)*sign(y(loc) - centre)) >= cfg.artifact_width_fraction*abs(y(loc) - centre);
        left = loc; right = loc;
        while left > 1 && above(left-1), left = left - 1; end
        while right < numel(above) && above(right+1), right = right + 1; end
        a = full_idx(left); b = full_idx(right); peak = full_idx(loc);
        duration = data.time_s(b) - data.time_s(a);
        if duration <= cfg.artifact_max_duration_sec
            data.artifact_suggestion_mask(a:b) = true;
            [peak_zt, peak_day] = photometry_zt(h0 + data.time_s(peak)/3600);
            rows{end+1, 1} = {p, data.time_s(a), data.time_s(b), data.time_s(peak), ...
                peak_zt, peak_day, duration, y(loc) - centre}; %#ok<AGROW>
        end
    end
end

names = {'phase', 'start_s', 'end_s', 'peak_s', 'peak_zt_hours', 'peak_day', 'duration_s', 'peak_size'};
if isempty(rows)
    data.artifact_suggestions = table('Size', [0 numel(names)], ...
        'VariableTypes', repmat({'double'}, 1, numel(names)), 'VariableNames', names);
else
    data.artifact_suggestions = sortrows(cell2table(vertcat(rows{:}), 'VariableNames', names), 'peak_s');
end
fprintf('Automatic artifact suggestions: %d events (nothing removed yet).\n', ...
    height(data.artifact_suggestions));
data = photometry_note_step(data, 9, cfg, {'artifact_prominence_mad', 'artifact_huge_peak_mad', ...
    'artifact_min_peak_distance_sec', 'artifact_width_fraction', 'artifact_max_duration_sec', ...
    'irls_tuning_constant'});
end
