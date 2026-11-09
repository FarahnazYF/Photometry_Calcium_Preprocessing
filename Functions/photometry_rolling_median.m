function [detrended, baseline, info] = photometry_rolling_median(signal, time_s, phase_windows, sample_rate_hz, window_sec)
%PHOTOMETRY_ROLLING_MEDIAN Subtract a centred rolling median (removes slow changes).
%
%   [detrended, baseline, info] = photometry_rolling_median(signal, time_s, ...
%                                     phase_windows, sample_rate_hz, window_sec)
%
% For every sample, the median of the samples within +/- window_sec/2
% around it is the "baseline"; the result is signal - baseline.
% With window_sec = 60 (1 minute):
%   - changes slower than about a minute (slow drifts, slow changes in the
%     signal level) are removed;
%   - fast transients (a few seconds) are kept at full height, because a
%     median ignores short excursions.
%
% Details
%   - Each phase, and each gap-free stretch inside it (gap = a pause of
%     more than 1.5 samples), is processed on its own: the window never
%     crosses a phase boundary or a recording gap.
%   - Missing samples (NaN) are ignored in the medians and stay missing.
%   - Near the edge of a stretch the window shrinks (no padding).
%   - The window is rounded to a whole, odd number of samples (at least 3).
%   - This is a SUBTRACTION (dF/F units stay the same), not a division.
%
% Inputs
%   signal          e.g. dF/F (column vector)
%   time_s          time of each sample (seconds)
%   phase_windows   [first last] sample number of each phase
%   sample_rate_hz  samples per second
%   window_sec      window length in seconds
%
% Outputs
%   detrended  signal - baseline
%   baseline   the rolling median that was subtracted
%   info       window in samples and seconds, and the stretches used

validateattributes(signal, {'numeric'}, {'vector', 'real', 'nonempty'});
validateattributes(sample_rate_hz, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(window_sec, {'numeric'}, {'scalar', 'finite', 'positive'});
x = signal(:);
t = time_s(:);
if numel(t) ~= numel(x) || any(~isfinite(t)) || any(diff(t) <= 0)
    error('photometry:Time', 'One finite, increasing time is needed for every sample.');
end
starts = phase_windows(:, 1);
ends = phase_windows(:, 2);
if any(ends < starts) || any(ends > numel(x)) || any(starts(2:end) <= ends(1:end-1))
    error('photometry:Phases', 'Phase windows must be ordered, non-overlapping and inside the signal.');
end

window = max(3, round(window_sec*sample_rate_hz));     % seconds -> samples
if mod(window, 2) == 0, window = window + 1; end        % odd, so it is centred
gap = 1.5/sample_rate_hz;
baseline = nan(size(x));
detrended = nan(size(x));
segments = zeros(0, 2);
for p = 1:numel(starts)
    a = starts(p); b = ends(p);
    split = find(diff(t(a:b)) > gap);                  % gaps inside the phase
    segment_starts = [a; a+split];
    segment_ends = [a+split-1; b];
    for k = 1:numel(segment_starts)
        idx = segment_starts(k):segment_ends(k);
        values = x(idx);
        values(~isfinite(values)) = NaN;
        local = movmedian(values, window, 'omitnan', 'Endpoints', 'shrink');
        local(~isfinite(values)) = NaN;                 % missing samples stay missing
        baseline(idx) = local;
        detrended(idx) = values - local;
    end
    segments = [segments; segment_starts, segment_ends]; %#ok<AGROW>
end

info.method = 'centred rolling median, subtracted';
info.window_sec = window_sec;
info.window_samples = window;
info.effective_window_sec = window/sample_rate_hz;
info.edge_behaviour = 'window shrinks at the edges of each phase and gap-free stretch';
info.segments = segments;
end
