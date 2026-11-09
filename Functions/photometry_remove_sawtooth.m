function data = photometry_remove_sawtooth(data, cfg)
%PHOTOMETRY_REMOVE_SAWTOOTH Remove the periodic sawtooth from the 405 channel.
%
%   data = photometry_remove_sawtooth(data, cfg)
%
% Why
%   Our 405 channel carries a small sawtooth-shaped ripple (period about
%   23.5 s, about 0.4% of the 405 level; a slow rise over ~19.5 s and a
%   fall over ~4 s). It is not in the 470 channel. The motion correction
%   (Step 11) subtracts a scaled copy of 405 from 470, so it would copy the
%   sawtooth, upside down, into dF/F. A low-pass filter cannot remove it:
%   its frequencies (0.04-0.35 Hz) are far below any cut-off.
%
% How (details in photometry_estimate_sawtooth)
%   The trimmed 405 is split into phases and gap-free stretches. In sliding
%   10-minute windows the exact period is found, the average shape of one
%   cycle is measured, and that shape is subtracted. A window is changed
%   only if the sawtooth is clearly stronger than the noise
%   (cfg.sawtooth_min_snr), so recordings without a sawtooth stay unchanged.
%
% What changes
%   Only 405. No sample is removed or added; missing samples stay missing.
%
% Output
%   data.trimmed470         470 with the trimmed samples set to NaN
%   data.cleaned405         405 with the trimmed samples set to NaN and the
%                           sawtooth subtracted (= trimmed 405 if skipped)
%   data.sawtooth_estimate  what was subtracted (NaN where 405 is missing)
%   data.sawtooth_removed   true if this step ran
%   data.sawtooth_info      one row per window (period, size, noise, whether
%                           it was subtracted) and the settings used
% Set cfg.remove_sawtooth = false in Step 1 to skip this step.

% Trimmed samples (Step 5) become missing in both channels.
trimmed405 = data.raw405(:);
trimmed405(data.trim_mask) = NaN;
data.trimmed470 = data.aligned470(:);
data.trimmed470(data.trim_mask) = NaN;

if ~cfg.remove_sawtooth
    data.cleaned405 = trimmed405;
    data.sawtooth_estimate = zeros(size(trimmed405));
    data.sawtooth_estimate(isnan(trimmed405)) = NaN;
    data.sawtooth_removed = false;
    data.sawtooth_info = struct('windows', table(), 'windows_applied', 0, 'windows_total', 0);
    fprintf('Sawtooth removal skipped (cfg.remove_sawtooth = false).\n');
    return;
end

settings = struct( ...
    'period_sec',      cfg.sawtooth_period_sec, ...
    'search_sec',      cfg.sawtooth_search_sec, ...
    'window_sec',      cfg.sawtooth_window_sec, ...
    'period_span_sec', cfg.sawtooth_period_span_sec, ...
    'min_snr',         cfg.sawtooth_min_snr, ...
    'harmonics',       cfg.sawtooth_harmonics);
[data.cleaned405, data.sawtooth_estimate, data.sawtooth_info] = photometry_estimate_sawtooth( ...
    trimmed405, data.time_s, data.phase_windows, cfg.sample_rate_hz, settings);
data.sawtooth_removed = true;

% ---- Report ----------------------------------------------------------------
w = data.sawtooth_info.windows;
if isempty(w)
    fprintf('Sawtooth: no stretch is long enough (5 cycles); 405 unchanged.\n');
elseif any(w.applied)
    used = logical(w.applied);
    level = median(trimmed405, 'omitnan');
    fprintf(['Sawtooth removed in %d of %d windows (period %.2f-%.2f s); ' ...
        'typical size %.3g%% of the 405 level (RMS).\n'], nnz(used), height(w), ...
        min(w.period_s(used)), max(w.period_s(used)), 100*median(w.sawtooth_rms(used), 'omitnan')/level);
else
    fprintf('Sawtooth: not clearly present in any of the %d windows; 405 unchanged.\n', height(w));
end
end
