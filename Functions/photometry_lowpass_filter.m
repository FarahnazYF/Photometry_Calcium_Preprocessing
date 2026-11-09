function data = photometry_lowpass_filter(data, cfg)
%PHOTOMETRY_LOWPASS_FILTER Remove fast noise from both channels.
%
%   data = photometry_lowpass_filter(data, cfg)
%
% Input:  data.cleaned405 and data.trimmed470 (Step 6)
% Output: data.filtered405 and data.filtered470 (missing samples stay NaN)
%         data.lowpass_info (method and settings)
%
% Two methods; choose with cfg.lowpass_method in Step 1:
%
% 'butterworth' (default)
%   A Butterworth low-pass filter of order cfg.butterworth_order (2) with
%   cut-off cfg.butterworth_cutoff_hz (3 Hz), run forwards and then
%   backwards (filtfilt). Running it both ways means the signal is not
%   shifted in time, and the filter acts twice: half of the power is kept
%   at about 0.8 x the cut-off (about 2.4 Hz for 3 Hz). Removes, for
%   example, the heartbeat (~11 Hz) and the fast noise of the 405 channel.
%   As in our original pipeline, the filter runs over the valid samples
%   joined together (samples missing in either channel are left out and
%   stay NaN).
%
% 'rolling_mean'
%   A centred rolling (moving) mean over cfg.rolling_mean_window_sec
%   seconds (1 s), used INSTEAD of the Butterworth. It is calculated within
%   each phase and gap-free stretch separately; missing samples are ignored
%   in the means and stay missing. Near the edges the window shrinks.

x405 = data.cleaned405(:);
x470 = data.trimmed470(:);
method = lower(strtrim(char(cfg.lowpass_method)));
switch method
    case 'butterworth'
        [data.filtered405, data.filtered470, info] = butterworth_filter(x405, x470, cfg);
        fprintf(['Low-pass: Butterworth, order %d, cut-off %g Hz, forwards and backwards ' ...
            '(half power kept at %.2f Hz).\n'], info.order, info.cutoff_hz, info.half_power_hz);
    case 'rolling_mean'
        [data.filtered405, info] = rolling_mean_filter(x405, data.time_s, data.phase_windows, ...
            cfg.sample_rate_hz, cfg.rolling_mean_window_sec);
        data.filtered470 = rolling_mean_filter(x470, data.time_s, data.phase_windows, ...
            cfg.sample_rate_hz, cfg.rolling_mean_window_sec);
        fprintf('Low-pass: centred rolling mean over %g s (%d samples).\n', ...
            info.window_sec, info.window_samples);
    otherwise
        error('photometry:LowpassMethod', ...
            'cfg.lowpass_method must be ''butterworth'' or ''rolling_mean'', not ''%s''.', method);
end
data.lowpass_info = info;
end

% ==========================================================================
function [f405, f470, info] = butterworth_filter(x405, x470, cfg)
fs = cfg.sample_rate_hz;
if cfg.butterworth_cutoff_hz <= 0 || cfg.butterworth_cutoff_hz >= fs/2
    error('photometry:Lowpass', 'cfg.butterworth_cutoff_hz must be between 0 and %g Hz.', fs/2);
end
[b, a] = butter(cfg.butterworth_order, cfg.butterworth_cutoff_hz/(fs/2), 'low');
valid = ~isnan(x405) & ~isnan(x470);                 % samples present in both channels
if nnz(valid) <= 3*max(numel(a)-1, numel(b)-1)
    error('photometry:Lowpass', 'Too few valid samples to filter.');
end
f405 = nan(size(x405));
f470 = nan(size(x470));
f405(valid) = filtfilt(b, a, x405(valid));
f470(valid) = filtfilt(b, a, x470(valid));

% Frequency at which forwards+backwards filtering keeps half the power.
[h, f] = freqz(b, a, 2^14, fs);
gain = abs(h).^4;                                    % power gain, applied twice
info.method = 'butterworth';
info.order = cfg.butterworth_order;
info.cutoff_hz = cfg.butterworth_cutoff_hz;
info.half_power_hz = f(find(gain <= 0.5, 1));
info.b = b;
info.a = a;
info.note = 'filtfilt over the valid samples of both channels joined together';
end

function [smoothed, info] = rolling_mean_filter(signal, time_s, phase_windows, fs, window_sec)
validateattributes(window_sec, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
x = signal(:); t = time_s(:);
window = max(1, round(window_sec*fs));               % seconds -> samples
smoothed = nan(size(x));
for p = 1:size(phase_windows, 1)
    a = phase_windows(p, 1); b = phase_windows(p, 2);
    split = find(diff(t(a:b)) > 1.5/fs);             % gaps inside the phase
    starts = [a; a+split];
    ends = [a+split-1; b];
    for k = 1:numel(starts)
        idx = starts(k):ends(k);
        values = x(idx);
        valid = isfinite(values);
        values(~valid) = NaN;
        means = movmean(values, window, 'omitnan', 'Endpoints', 'shrink');
        means(~valid) = NaN;                         % missing samples stay missing
        smoothed(idx) = means;
    end
end
info.method = 'rolling_mean';
info.window_sec = window_sec;
info.window_samples = window;
info.note = 'centred rolling mean per phase and gap-free stretch; window shrinks at the edges';
end
