function data = photometry_find_phases_and_trim(data, cfg)
%PHOTOMETRY_FIND_PHASES_AND_TRIM Find phases, align 470 to 405, mark the phase edges.
%
%   data = photometry_find_phases_and_trim(data, cfg)
%
% Phases
%   The LEDs were switched off between recording blocks. Every pause in the
%   405 pulses longer than cfg.phase_gap_sec starts a new phase. Later
%   steps (sawtooth removal, bleaching correction, rolling median) treat
%   each phase separately.
%   -> data.phase_windows  [first last] sample number of each phase (one row per phase)
%      data.phase_names    'Phase 1', 'Phase 2', ...
%
% Alignment
%   The 470 pulses fall between the 405 pulses. The 470 values are
%   interpolated (pchip) onto the 405 pulse times, so both channels share
%   one time axis, data.time_s.
%   -> data.aligned470
%
% Trimming
%   The first cfg.trim_start_sec and the last cfg.trim_end_sec seconds of
%   every phase are often unstable (LED warming up or switching off). They
%   are marked in data.trim_mask (true = trimmed). The signals are NOT
%   shortened: later steps set trimmed samples to NaN (missing), so every
%   sample keeps its time.

% ---- Phases ---------------------------------------------------------------
breaks = find(diff(data.time_s) > cfg.phase_gap_sec);   % last sample before each pause
data.phase_windows = [[1; breaks+1], [breaks; numel(data.time_s)]];
n_phases = size(data.phase_windows, 1);
data.phase_names = arrayfun(@(k) sprintf('Phase %d', k), 1:n_phases, 'UniformOutput', false);

% ---- Align 470 onto the 405 pulse times -----------------------------------
inside = data.time470_s >= data.time_s(1) & data.time470_s <= data.time_s(end);
if nnz(inside) < 2
    error('photometry:Alignment', 'Too few 470 pulses fall inside the 405 recording time.');
end
data.aligned470 = interp1(data.time470_s(inside), data.raw470(inside), data.time_s, 'pchip', 'extrap');

% ---- Mark the phase edges -------------------------------------------------
data.trim_mask = false(size(data.time_s));
n_start = round(cfg.trim_start_sec*cfg.sample_rate_hz);   % seconds -> samples
n_end   = round(cfg.trim_end_sec*cfg.sample_rate_hz);
h0 = data.crop_info.start_hours_from_lights_on;   % time zero in hours from the first lights ON (e.g. -1)
for p = 1:n_phases
    a = data.phase_windows(p, 1);
    b = data.phase_windows(p, 2);
    data.trim_mask(a:min(a+n_start-1, b)) = true;
    data.trim_mask(max(a, b-n_end+1):b) = true;
    [~, ~, from] = photometry_zt(h0 + data.time_s(a)/3600);
    [~, ~, to] = photometry_zt(h0 + data.time_s(b)/3600);
    fprintf('Phase %d: %s to %s, %.1f minutes.\n', p, from, to, (data.time_s(b)-data.time_s(a))/60);
end
end
