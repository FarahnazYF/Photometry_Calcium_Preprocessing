function data = photometry_lowpass_filter(data, cfg)
%PHOTOMETRY_LOWPASS_FILTER Remove fast noise from both channels.
%
%   data = photometry_lowpass_filter(data, cfg)
%
% Input:  data.cleaned405 and data.trimmed470 (Step 6)
% Output: data.filtered405 and data.filtered470 (missing samples stay NaN)
%         data.lowpass_info (method and settings)
%
% Both methods work on one "stretch" at a time. A stretch is a run of
% consecutive valid samples inside one phase, without a pause in the LED
% pulses. Nothing is filtered across a phase boundary, a pulse gap or a
% missing sample, so the end of one phase cannot leak into the start of the
% next. Choose the method with cfg.lowpass_method in Step 1:
%
% 'butterworth' (default)
%   A Butterworth low-pass filter of order cfg.butterworth_order (2) with
%   cut-off cfg.butterworth_cutoff_hz (3 Hz), run forwards and then
%   backwards (filtfilt). Running it both ways means the signal is not
%   shifted in time, and the filter acts twice: half of the power is kept
%   at about 0.8 x the cut-off (about 2.4 Hz for 3 Hz). Removes, for
%   example, the heartbeat (~11 Hz) and the fast noise of the 405 channel.
%   A sample must be present in both channels to be filtered. A stretch
%   that is too short for the filter (6 samples or fewer for order 2) is
%   set to missing; the Command Window says how many samples that is.
%
% 'rolling_mean'
%   A centred rolling (moving) mean over cfg.rolling_mean_window_sec
%   seconds (1 s), used INSTEAD of the Butterworth. The window is rounded
%   to a whole, odd number of samples (51 for 1 s at 50 per second), so
%   that it is centred on each sample. Missing samples are ignored in the
%   means and stay missing. Near the edges of a stretch the window shrinks.

x405 = data.cleaned405(:);
x470 = data.trimmed470(:);
method = lower(strtrim(char(cfg.lowpass_method)));
switch method
    case 'butterworth'
        [data.filtered405, data.filtered470, info] = butterworth_filter(x405, x470, ...
            data.time_s, data.phase_windows, cfg);
        fprintf(['Low-pass: Butterworth, order %d, cut-off %g Hz, forwards and backwards ' ...
            '(half power kept at %.2f Hz), in %d separate stretches.\n'], ...
            info.order, info.cutoff_hz, info.half_power_hz, info.stretches);
        if info.samples_in_short_stretches > 0
            fprintf('  %d samples in stretches shorter than %d samples were set to missing.\n', ...
                info.samples_in_short_stretches, info.shortest_stretch_filtered);
        end
    case 'rolling_mean'
        [data.filtered405, info] = rolling_mean_filter(x405, data.time_s, data.phase_windows, ...
            cfg.sample_rate_hz, cfg.rolling_mean_window_sec);
        data.filtered470 = rolling_mean_filter(x470, data.time_s, data.phase_windows, ...
            cfg.sample_rate_hz, cfg.rolling_mean_window_sec);
        fprintf('Low-pass: centred rolling mean over %d samples (%.2f s).\n', ...
            info.window_samples, info.effective_window_sec);
    otherwise
        error('photometry:LowpassMethod', ...
            'cfg.lowpass_method must be ''butterworth'' or ''rolling_mean'', not ''%s''.', method);
end
data.lowpass_info = info;
data = photometry_note_step(data, 7, cfg, {'lowpass_method', 'butterworth_cutoff_hz', ...
    'butterworth_order', 'rolling_mean_window_sec'});
end

% ==========================================================================
function [f405, f470, info] = butterworth_filter(x405, x470, time_s, phase_windows, cfg)
fs = cfg.sample_rate_hz;
if cfg.butterworth_cutoff_hz <= 0 || cfg.butterworth_cutoff_hz >= fs/2
    error('photometry:Lowpass', 'cfg.butterworth_cutoff_hz must be between 0 and %g Hz.', fs/2);
end
[b, a] = butter(cfg.butterworth_order, cfg.butterworth_cutoff_hz/(fs/2), 'low');
shortest = 3*max(numel(a)-1, numel(b)-1) + 1;        % filtfilt needs more than 3 x order samples

% Filter each stretch on its own.
valid = isfinite(x405) & isfinite(x470);             % samples present in both channels
[first, last] = find_stretches(valid, time_s, phase_windows, fs);
f405 = nan(size(x405));
f470 = nan(size(x470));
too_short = 0;
for s = 1:numel(first)
    idx = first(s):last(s);
    if numel(idx) < shortest
        too_short = too_short + numel(idx);          % stays missing
        continue;
    end
    f405(idx) = filtfilt(b, a, x405(idx));
    f470(idx) = filtfilt(b, a, x470(idx));
end
if ~any(isfinite(f405))
    error('photometry:Lowpass', 'Too few valid samples to filter.');
end

% Frequency at which forwards+backwards filtering keeps half the power.
[h, f] = freqz(b, a, 2^14, fs);
gain = abs(h).^4;                                    % power gain, applied twice
info.method = 'butterworth';
info.order = cfg.butterworth_order;
info.cutoff_hz = cfg.butterworth_cutoff_hz;
info.half_power_hz = f(find(gain <= 0.5, 1));
info.b = b;
info.a = a;
info.stretches = numel(first);
info.shortest_stretch_filtered = shortest;
info.samples_in_short_stretches = too_short;
info.note = 'filtfilt within each stretch: consecutive valid samples of one phase without a pulse gap';
end

function [smoothed, info] = rolling_mean_filter(signal, time_s, phase_windows, fs, window_sec)
validateattributes(window_sec, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
x = signal(:);
window = max(1, round(window_sec*fs));               % seconds -> samples
if mod(window, 2) == 0, window = window + 1; end     % odd, so it is centred on the sample

% movmean ignores missing samples, so only phase boundaries and pulse gaps
% separate the stretches here.
[first, last] = find_stretches(true(size(x)), time_s, phase_windows, fs);
smoothed = nan(size(x));
for s = 1:numel(first)
    idx = first(s):last(s);
    values = x(idx);
    valid = isfinite(values);
    values(~valid) = NaN;
    means = movmean(values, window, 'omitnan', 'Endpoints', 'shrink');
    means(~valid) = NaN;                             % missing samples stay missing
    smoothed(idx) = means;
end
info.method = 'rolling_mean';
info.window_sec = window_sec;
info.window_samples = window;
info.effective_window_sec = window/fs;
info.stretches = numel(first);
info.note = 'centred rolling mean within each phase and gap-free stretch; window shrinks at the edges';
end

function [first, last] = find_stretches(valid, time_s, phase_windows, fs)
% First and last sample of every stretch: a run of consecutive samples with
% valid = true, inside one phase and without a pause in the pulses (a pause
% is more than 1.5 sample intervals between two pulses).
valid = valid(:);
breaks_here = false(numel(valid), 1);                % true where a new stretch must start
breaks_here(phase_windows(:, 1)) = true;             % the first sample of a phase
breaks_here([false; diff(time_s(:)) > 1.5/fs]) = true;   % the first sample after a pulse gap
first = find(valid & (breaks_here | [true; ~valid(1:end-1)]));
last  = find(valid & ([breaks_here(2:end); true] | [~valid(2:end); true]));
end
