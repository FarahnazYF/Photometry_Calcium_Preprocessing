function data = photometry_find_phases_and_trim(data, cfg)
%PHOTOMETRY_FIND_PHASES_AND_TRIM Find phases, align 470 to 405, mark the phase edges.
%
%   data = photometry_find_phases_and_trim(data, cfg)
%
% Phases
%   The LEDs were switched off between recording blocks. Every pause in the
%   405 pulses longer than cfg.phase_gap_sec starts a new phase. Later
%   steps (sawtooth removal, filtering, bleaching correction, rolling
%   median) treat each phase separately.
%   -> data.phase_windows  [first last] sample number of each phase (one row per phase)
%      data.phase_names    'Phase 1', 'Phase 2', ...
%
% Short pauses inside a phase
%   A shorter pause of the LEDs (for example a fraction of a second when
%   the LED program restarts) does not start a new phase and is not
%   trimmed. It stays as a small gap in time: no samples exist there. The
%   Command Window says how many such pauses there are. The filters and
%   rolling windows of the later steps do not run across them.
%
% Trimming
%   The first cfg.trim_start_sec and the last cfg.trim_end_sec seconds of
%   every phase are often unstable (LED warming up or switching off). They
%   are marked in data.trim_mask (true = trimmed). The signals are NOT
%   shortened: later steps set trimmed samples to NaN (missing), so every
%   sample keeps its time.
%
% Alignment
%   The 470 pulses fall between the 405 pulses. The 470 values are
%   interpolated (pchip) onto the 405 pulse times, so both channels share
%   one time axis, data.time_s. A 405 pulse gets a 470 value only if it
%   lies between two 470 pulses that are at most 2.5 pulse periods apart.
%   So one missing 470 pulse is bridged (the two pulses around it are 2
%   periods apart), but a longer gap is not: there the 470 value is NaN.
%   Nothing is interpolated across such a gap and nothing is extrapolated.
%   Two cases:
%   - Next to a pause of both LEDs. The first 405 pulse after the LEDs
%     switch on has no 470 pulse before it, so it gets no 470 value. This
%     is normal: one sample at the start of each phase (trimmed anyway)
%     and one or two samples next to each short pause inside a phase.
%   - Where the 405 LED keeps flashing but 470 pulses are missing (the 470
%     LED started late, stopped early or dropped out). This is a fault of
%     the recording: a warning is shown if it happens outside the trimmed
%     phase edges.
%   -> data.aligned470
%      data.alignment_info  counts of the samples without a 470 value, of
%                           the samples bridged over one missing 470 pulse,
%                           and of the short pauses inside phases

period = 1/cfg.sample_rate_hz;      % time between two pulses of one LED (seconds)
time_s = data.time_s(:);
step = diff(time_s);                % time from each 405 pulse to the next

% ---- Phases ---------------------------------------------------------------
breaks = find(step > cfg.phase_gap_sec);                % last sample before each long pause
data.phase_windows = [[1; breaks+1], [breaks; numel(time_s)]];
n_phases = size(data.phase_windows, 1);
data.phase_names = arrayfun(@(k) sprintf('Phase %d', k), 1:n_phases, 'UniformOutput', false);

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

% ---- Short pauses of the LEDs inside a phase ------------------------------
is_pause = step > 1.5*period;                           % one or more 405 pulses are missing here
short_pauses = step(is_pause & step <= cfg.phase_gap_sec);
if ~isempty(short_pauses)
    fprintf(['Note: the LED pulses pause %d time(s) inside a phase (longest pause: %.2f s). No samples ' ...
        'exist there;\n  the filters and rolling windows of the later steps do not run across these pauses.\n'], ...
        numel(short_pauses), max(short_pauses));
end

% ---- Align 470 onto the 405 pulse times -----------------------------------
max_gap = 2.5*period;               % 470 pulses further apart than this: two or more pulses are missing in between
[data.aligned470, paired, bracket] = align_470(time_s, data.time470_s(:), data.raw470(:), max_gap);
if ~any(paired)
    error('photometry:Alignment', ['No 405 pulse lies between two regular 470 pulses. ' ...
        'Check cfg.led405_variable, cfg.led470_variable and cfg.sample_rate_hz.']);
end
data.aligned470 = reshape(data.aligned470, size(data.time_s));

% Samples without a 470 value: next to a pause of both LEDs (normal), or
% where the 405 LED kept flashing (470 pulses are missing: a fault).
next_to_pause = [true; is_pause] | [is_pause; true];    % first or last 405 pulse of a run of pulses
outside_trims = ~data.trim_mask(:);
missing_while_405_on = ~paired & ~next_to_pause;
data.alignment_info.max_470_gap_sec = max_gap;
data.alignment_info.samples_without_470 = nnz(~paired);
data.alignment_info.samples_without_470_outside_trims = nnz(~paired & outside_trims);
data.alignment_info.samples_without_470_while_405_on = nnz(missing_while_405_on);
data.alignment_info.samples_bridged_over_one_missing_470_pulse = nnz(paired & bracket > 1.5*period);
data.alignment_info.short_pauses_inside_phases = numel(short_pauses);
data.alignment_info.longest_short_pause_sec = max([short_pauses; 0]);
if any(missing_while_405_on & outside_trims)
    warning('photometry:Missing470', ['%d samples outside the trimmed phase edges have a 405 pulse but ' ...
        'no 470 pulse next to it (the 470 LED started late, stopped early or dropped out). Their 470 ' ...
        'value is set to missing, so they get no dF/F. Compare the two channels in Figure 1.'], ...
        nnz(missing_while_405_on & outside_trims));
end

data = photometry_note_step(data, 5, cfg, {'phase_gap_sec', 'trim_start_sec', 'trim_end_sec'});
end

% ==========================================================================
function [aligned, paired, bracket] = align_470(t405, t470, y470, max_gap)
% A 470 value for every 405 pulse that lies between two nearby 470 pulses.
%   paired  true where the two 470 pulses around a 405 pulse are at most
%           max_gap seconds apart
%   aligned the 470 values interpolated at those 405 pulses (NaN elsewhere)
%   bracket the time between those two 470 pulses (Inf if one is missing)
n470 = numel(t470);
aligned = nan(size(t405));
paired = false(size(t405));
bracket = inf(size(t405));
if n470 < 2, return; end

% The two 470 pulses around each 405 pulse, and the time between them.
before = discretize(t405, [t470; Inf]);        % number of the last 470 pulse at or before each 405 pulse
has_both = ~isnan(before) & before < n470;     % there is also a 470 pulse after it
bracket(has_both) = t470(before(has_both) + 1) - t470(before(has_both));
paired = has_both & bracket <= max_gap;
if ~any(paired), return; end

% The 470 pulses form "runs" without a longer gap. Interpolate inside each
% run only, so that values on the other side of a gap have no influence.
new_run = [true; diff(t470) > max_gap];
run_of_470 = cumsum(new_run);                  % run number of every 470 pulse
run_first = find(new_run);
run_last = [run_first(2:end) - 1; n470];
members = find(paired);
run_of_405 = run_of_470(before(members));      % run number of every paired 405 pulse
starts = [1; find(diff(run_of_405) ~= 0) + 1];
stops = [starts(2:end) - 1; numel(members)];
for g = 1:numel(starts)
    idx = members(starts(g):stops(g));
    r = run_of_405(starts(g));
    pulses = run_first(r):run_last(r);
    aligned(idx) = interp1(t470(pulses), y470(pulses), t405(idx), 'pchip');
end
end
