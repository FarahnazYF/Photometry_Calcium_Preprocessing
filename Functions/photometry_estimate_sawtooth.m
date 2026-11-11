function [cleaned, sawtooth, info] = photometry_estimate_sawtooth(x, t, phase_windows, sample_rate_hz, settings)
%PHOTOMETRY_ESTIMATE_SAWTOOTH Estimate and subtract a periodic ripple of drifting timing.
%
%   [cleaned, sawtooth, info] = photometry_estimate_sawtooth(x, t, phase_windows, sample_rate_hz, settings)
%
% Inputs
%   x               the signal (here: the trimmed 405), NaN = missing
%   t               time of each sample (seconds, increasing)
%   phase_windows   [first last] sample number of each phase
%   sample_rate_hz  samples per second
%   settings        struct; missing fields use these defaults:
%     period_sec      23.5  expected period (s)
%     search_sec      1     the period is searched within +/- this (s)
%     window_sec      600   length of the sliding estimation windows (s)
%     period_span_sec 1800  span around each window used to find its period (s)
%     min_snr         4     a window is changed only if ripple >= min_snr x noise
%     harmonics       8     harmonics used to find and judge the ripple
%     bins            47    points used to describe the shape of one cycle
%     min_cycles      5     shorter stretches are left unchanged
%
% Outputs
%   cleaned   x - sawtooth
%   sawtooth  the estimated ripple (0 where nothing was subtracted, NaN
%             where x is missing)
%   info      .windows: one row per window (phase, times, period_s,
%             sawtooth_rms, noise_rms, snr, valid_fraction, applied) and
%             the settings used
%
% How it works, step by step
%   1. Each phase and each gap-free stretch inside it (a gap = a pause of
%      more than 1.5 samples) is handled on its own: nothing is estimated
%      or subtracted across a gap. Stretches shorter than min_cycles
%      periods are left unchanged.
%   2. Slow trends (slower than 3 periods) are removed first with a moving
%      mean. This copy is only used for the estimation.
%   3. The stretch is covered by windows of window_sec that overlap by
%      half (one window if the stretch is shorter).
%   4. The exact period of each window is searched over a longer span
%      around it (period_span_sec): first in 0.01-s steps on a 5-Hz copy,
%      then in 0.002-s steps at full rate, refined with a parabola. The
%      period drifts during a recording, so it is found again in every
%      window. (A 10-minute window alone pins the period only to about
%      +/-0.02 s, which would blur the sharp part of the sawtooth.)
%   5. The shape of one cycle is the average of the window's samples
%      grouped by their position in the cycle (time modulo the period),
%      in `bins` bins.
%   6. Strength test: the size of that shape (first `harmonics`
%      harmonics only, about 0-0.35 Hz) must be at least min_snr times the
%      "noise", i.e. the same measure at five unrelated periods. Otherwise
%      the shape of this window is not used. (Using only the first
%      harmonics stops an unrelated rhythm, e.g. at 0.37 Hz, from being
%      mistaken for the ripple.) This is a threshold on a noisy measure:
%      it makes a false detection unlikely, not impossible.
%   7. The shape (all bins, so the sharp fall is kept) is subtracted.
%      Windows overlap by half and are blended with triangular weights, so
%      the estimate changes smoothly from one window to the next. Where a
%      window whose shape is used overlaps a window whose shape is not
%      used, a weighted part of the shape is subtracted, fading to zero.
% Missing samples never contribute to a shape and stay missing.
%
% Limits
%   - Slow trends are removed with a moving mean (step 2). Where the signal
%     falls steeply (the first minutes after the LED is switched on), some
%     trend remains and raises the "noise", so a window there can fail the
%     strength test and keep its ripple. The table of windows shows this
%     (applied = false).
%   - Any stable rhythm with a period inside the search range is treated
%     as the ripple, whatever its cause.

defaults = struct('period_sec', 23.5, 'search_sec', 1, 'window_sec', 600, ...
    'min_snr', 4, 'bins', 47, 'min_cycles', 5, 'harmonics', 8, 'period_span_sec', 1800);
if nargin < 5 || isempty(settings), settings = struct(); end
names = fieldnames(defaults);
for k = 1:numel(names)
    if ~isfield(settings, names{k}), settings.(names{k}) = defaults.(names{k}); end
end

% ---- Check the inputs ---------------------------------------------------------
validateattributes(x, {'numeric'}, {'vector', 'real', 'nonempty'});
validateattributes(sample_rate_hz, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
validateattributes(settings.period_sec, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
validateattributes(settings.search_sec, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'});
if settings.search_sec >= settings.period_sec
    error('photometry:SawtoothSettings', 'sawtooth_search_sec must be smaller than sawtooth_period_sec.');
end
validateattributes(settings.window_sec, {'numeric'}, {'scalar', 'real', 'finite', '>=', 2*settings.period_sec});
validateattributes(settings.period_span_sec, {'numeric'}, {'scalar', 'real', 'finite', '>=', settings.window_sec});
validateattributes(settings.min_snr, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'});
validateattributes(settings.bins, {'numeric'}, {'scalar', 'integer', '>=', 8});
validateattributes(settings.harmonics, {'numeric'}, {'scalar', 'integer', 'positive', '<', settings.bins/2});
x = x(:); t = t(:); n = numel(x);
if numel(t) ~= n || any(~isfinite(t)) || any(diff(t) <= 0)
    error('photometry:Time', 'One finite, increasing time is needed for every sample.');
end
validateattributes(phase_windows, {'numeric'}, {'2d', 'nonempty', 'integer', 'positive', 'finite'});
if size(phase_windows, 2) ~= 2 || any(phase_windows(:,2) < phase_windows(:,1)) || ...
        any(phase_windows(:,2) > n) || any(phase_windows(2:end,1) <= phase_windows(1:end-1,2))
    error('photometry:Phases', 'Phase windows must be ordered, non-overlapping and inside the signal.');
end

% ---- Constants --------------------------------------------------------------
P0 = settings.period_sec;
nb = settings.bins;
K  = settings.harmonics;
noise_factors = [0.6131 0.7311 0.8419 1.1931 1.3172];   % periods unrelated to the ripple
step = max(1, round(sample_rate_hz/5));                 % for the fast 5-Hz search copy
coarse = (P0 - settings.search_sec):0.01:(P0 + settings.search_sec);
W = max(1, round(settings.window_sec*sample_rate_hz));  % window length (samples)
H = max(1, round(W/2));                                 % hop between windows (samples)
S = max(W, round(settings.period_span_sec*sample_rate_hz));
min_len = ceil(settings.min_cycles*P0*sample_rate_hz);

sawtooth = zeros(n, 1);
rows = cell(0, 1);
segments = zeros(0, 3);
for p = 1:size(phase_windows, 1)
    a = phase_windows(p, 1); b = phase_windows(p, 2);
    split = find(diff(t(a:b)) > 1.5/sample_rate_hz);          % gaps inside the phase
    seg_start = [a; a+split];
    seg_end = [a+split-1; b];
    for g = 1:numel(seg_start)
        idx = (seg_start(g):seg_end(g))';
        segments(end+1, :) = [p seg_start(g) seg_end(g)]; %#ok<AGROW>
        L = numel(idx);
        if L < min_len, continue; end                         % too short: unchanged
        xs = x(idx); xs(~isfinite(xs)) = NaN;
        ts = t(idx);
        % Step 2: remove slow trends (only for the estimation).
        hp = xs - movmean(xs, max(3, round(3*P0*sample_rate_hz)), 'omitnan', 'Endpoints', 'shrink');
        % Step 3: window starts.
        if L <= W
            starts = 1; len = L;
        else
            starts = 1:H:(L-W+1);
            if starts(end)+W-1 < L, starts(end+1) = L-W+1; end %#ok<AGROW>
            len = W;
        end
        num = zeros(L, 1);
        den = zeros(L, 1);
        for s = starts
            wi = (s:s+len-1)';
            u = ((1:len)' - 0.5)/len;
            weight = 1 - abs(2*u - 1);                   % triangular, never zero
            den(wi) = den(wi) + weight;
            valid_fraction = mean(isfinite(hp(wi)));
            period = NaN; ripple_rms = NaN; noise_rms = NaN; applied = false;
            if valid_fraction >= 0.5
                % Step 4: the period, from a longer span centred on the window.
                centre = s + floor(len/2);
                si = (max(1, centre-floor(S/2)):min(L, centre+floor(S/2)))';
                m = floor(numel(si)/step)*step;
                xd = mean(reshape(hp(si(1:m)), step, []), 1, 'omitnan')';
                td = mean(reshape(ts(si(1:m)), step, []), 1)';
                period = search_period(xd, td, coarse, nb, K);
                period = search_period(hp(si), ts(si), (period-0.02):0.002:(period+0.02), nb, K, true);
                % Step 5: the shape of one cycle.
                template = cycle_average(hp(wi), ts(wi), period, nb);
                % Step 6: is it clearly stronger than the noise?
                ripple_rms = band_rms(template, K);
                noise_rms = median(arrayfun(@(f) band_rms(cycle_average( ...
                    hp(wi), ts(wi), f*period, nb), K), noise_factors), 'omitnan');
                applied = isfinite(ripple_rms) && isfinite(noise_rms) && ...
                    ripple_rms >= settings.min_snr*noise_rms;
                % Step 7: add this window's shape, weighted, to the estimate.
                if applied
                    template = fill_circular(template);
                    num(wi) = num(wi) + weight.*evaluate(template, ts(wi), period);
                end
            end
            rows{end+1, 1} = {p, ts(1), ts(wi(1)), ts(wi(end)), idx(wi(1)), idx(wi(end)), ...
                period, ripple_rms, noise_rms, ripple_rms/noise_rms, valid_fraction, applied}; %#ok<AGROW>
        end
        sawtooth(idx) = num./den;
    end
end
sawtooth(~isfinite(x)) = NaN;
cleaned = x - sawtooth;

% ---- Summary table ------------------------------------------------------------
names = {'phase', 'segment_start_s', 'window_start_s', 'window_end_s', 'first_index', ...
    'last_index', 'period_s', 'sawtooth_rms', 'noise_rms', 'snr', 'valid_fraction', 'applied'};
if isempty(rows)
    types = [repmat({'double'}, 1, numel(names)-1), {'logical'}];
    info.windows = table('Size', [0 numel(names)], 'VariableTypes', types, 'VariableNames', names);
else
    info.windows = cell2table(vertcat(rows{:}), 'VariableNames', names);
end
info.segments = array2table(segments, 'VariableNames', {'phase', 'first_index', 'last_index'});
info.settings = settings;
info.window_samples = W;
info.hop_samples = H;
info.min_segment_samples = min_len;
info.windows_applied = nnz(info.windows.applied);
info.windows_total = height(info.windows);
info.method = ['sliding cycle-average template per phase and gap-free stretch; ' ...
    'triangular blending of overlapping windows; subtracted; missing samples kept missing'];
end

% ==========================================================================
function best = search_period(x, t, periods, nb, K, refine)
% The candidate period whose cycle average has the largest ripple.
score = zeros(size(periods));
for k = 1:numel(periods)
    score(k) = band_rms(cycle_average(x, t, periods(k), nb), K);
end
[~, k] = max(score);
best = periods(k);
% Optional: a parabola through the best point and its two neighbours.
if nargin > 5 && refine && k > 1 && k < numel(periods) && all(isfinite(score(k-1:k+1)))
    y = score(k-1:k+1);
    curvature = y(1) - 2*y(2) + y(3);
    if curvature < 0
        best = best + 0.5*(y(1)-y(3))/curvature*(periods(2)-periods(1));
    end
end
end

function w = cycle_average(x, t, period_sec, bins)
% Average of x by position in the cycle: samples are grouped by
% mod(t, period) into equal bins; the overall mean is removed. Missing
% samples are ignored; an empty bin is NaN.
x = x(:); t = t(:);
ok = isfinite(x) & isfinite(t);
bin = floor(mod(t(ok), period_sec)/period_sec*bins) + 1;
bin = min(max(bin, 1), bins);                 % guard rounding at the cycle edge
w = accumarray(bin, x(ok), [bins 1])./accumarray(bin, 1, [bins 1]);
w = w - mean(w, 'omitnan');
end

function r = band_rms(w, K)
% RMS of harmonics 1..K of a cycle average (Parseval). Empty bins are
% filled around the cycle first; with fewer than half the bins filled the
% result is NaN.
w = w(:); nb = numel(w); ok = isfinite(w);
if nnz(ok) < nb/2, r = NaN; return; end
if ~all(ok)
    pos = (1:nb)'; known = pos(ok);
    w(~ok) = interp1([known-nb; known; known+nb], repmat(w(ok), 3, 1), pos(~ok), 'linear');
end
F = fft(w);
r = sqrt(2*sum(abs(F(2:K+1)).^2))/nb;
end

function w = fill_circular(w)
% Fill empty bins by linear interpolation around the cycle.
nb = numel(w); ok = isfinite(w);
if all(ok), return; end
pos = (1:nb)'; known = pos(ok);
w(~ok) = interp1([known-nb; known; known+nb], repmat(w(ok), 3, 1), pos(~ok), 'linear');
end

function r = evaluate(template, t, period)
% The cycle shape at times t: linear interpolation between bin centres,
% wrapping around the end of the cycle.
nb = numel(template);
position = mod(t, period)/period*nb;              % 0..nb; bin centres at k-0.5
centres = [-0.5; (0.5:1:nb-0.5)'; nb+0.5];
r = interp1(centres, [template(end); template; template(1)], position, 'linear');
end
