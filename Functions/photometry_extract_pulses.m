function data = photometry_extract_pulses(raw, cfg)
%PHOTOMETRY_EXTRACT_PULSES One 405 and one 470 value per LED pulse.
%
%   data = photometry_extract_pulses(raw, cfg)
%
% The 405-nm and 470-nm LEDs flash in turn, and one photodetector (PMT)
% records the light of both. The LED monitor channels show when each LED is
% on. For each LED:
%   1. Find its pulses. The LED counts as on when its monitor is above a
%      threshold halfway between its "off" level and its "on" level.
%      - Normally the two levels are the 5th and the 95th percentile of
%        the monitor. This is right when the LED is on for 5% to 95% of
%        the analysis window.
%      - If the LED is on more rarely (or nearly always), both percentiles
%        show the same level. The levels are then the medians of the low
%        and of the high monitor values. The Command Window says so.
%      A 3-sample median filter removes single-sample flickers, and pulses
%      shorter than half of cfg.pulse_width_ms are ignored.
%   2. Take the median of the PMT signal during each pulse (from the sample
%      after the onset to the last "on" sample).
% Result: one value per pulse, i.e. cfg.sample_rate_hz values per second
% for each channel.
%
% Output (all column vectors)
%   data.raw405, data.raw470    the extracted fluorescence (PMT units)
%   data.time_s                 time of each 405 pulse (its onset), seconds
%                               after the start of the analysis window
%                               (gaps kept)
%   data.time470_s              time of each 470 pulse (same clock)
%   data.crop_info              copied from raw
%   data.pulse_info             levels, thresholds, pulse counts, measured rates
%
% Stops with an error if fewer than two pulses of an LED are found, or if
% the measured pulse rate of an LED differs from cfg.sample_rate_hz by more
% than 2% (wrong settings or wrong channels). If the cause is a monitor
% that does not show two clearly different levels (wrong channel, or the
% LED was never on in the analysis window), the message says so.

width_samples = cfg.pulse_width_ms/1000*raw.fs;   % pulse width in raw samples
[on405, off405, levels405] = detect_pulses(raw.led405, width_samples);
[on470, off470, levels470] = detect_pulses(raw.led470, width_samples);

% ---- Check the pulses ---------------------------------------------------------
rate405 = pulse_rate(on405, raw.fs);              % pulses per second (NaN if fewer than 2 pulses)
rate470 = pulse_rate(on470, raw.fs);
too_few = numel(on405) < 2 || numel(on470) < 2;
rate_is_wrong = @(rate) ~(abs(rate - cfg.sample_rate_hz)/cfg.sample_rate_hz <= 0.02);
if too_few || rate_is_wrong(rate405) || rate_is_wrong(rate470)
    % Something is wrong. If a monitor is the cause, say that first.
    explain_monitor_problem(raw.led405, levels405, '405', cfg.led405_variable);
    explain_monitor_problem(raw.led470, levels470, '470', cfg.led470_variable);
    if too_few
        error('photometry:Pulses', ['Fewer than two LED pulses were found in one or both LED ' ...
            'monitor channels. Check cfg.led405_variable and cfg.led470_variable.']);
    end
    error('photometry:Rate', ['The measured pulse rate (%.3f per second for 405, %.3f for 470) ' ...
        'differs from cfg.sample_rate_hz (%g). Check cfg.sample_rate_hz, cfg.raw_sampling_rate_hz ' ...
        'and the LED monitor variable names in Step 1.'], rate405, rate470, cfg.sample_rate_hz);
end

% ---- One value per pulse --------------------------------------------------------
data.raw405 = pulse_medians(raw.pmt, on405, off405);
data.raw470 = pulse_medians(raw.pmt, on470, off470);
% Time zero is the first sample of the analysis window, even if the first
% pulse comes a little later.
data.time_s    = (on405-1)/raw.fs;
data.time470_s = (on470-1)/raw.fs;
data.crop_info = raw.crop_info;

data.pulse_info.threshold405 = levels405.threshold;
data.pulse_info.threshold470 = levels470.threshold;
data.pulse_info.off_level405 = levels405.off;
data.pulse_info.on_level405  = levels405.on;
data.pulse_info.off_level470 = levels470.off;
data.pulse_info.on_level470  = levels470.on;
data.pulse_info.level_method405 = levels405.method;
data.pulse_info.level_method470 = levels470.method;
data.pulse_info.pulses405 = numel(on405);
data.pulse_info.pulses470 = numel(on470);
data.pulse_info.first_pulse_sec = data.time_s(1);
data.pulse_info.measured_rate_hz = rate405;
data.pulse_info.measured_rate470_hz = rate470;

fprintf('Pulses found: %d (405) and %d (470); %.3f pulses per second.\n', ...
    numel(on405), numel(on470), rate405);
if ~levels405.from_percentiles || ~levels470.from_percentiles
    fprintf(['  An LED is on for less than 5%% (or more than 95%%) of the analysis window: its off ' ...
        'and on levels\n  were taken from the medians of the low and the high monitor values.\n']);
end

% Settings used so far (Step 3 and this step); saved with the results.
if isfield(raw, 'applied_settings'), data.applied_settings = raw.applied_settings; end
data = photometry_note_step(data, 4, cfg, {'pulse_width_ms', 'sample_rate_hz'});
end

% ==========================================================================
function [on, off, levels] = detect_pulses(monitor, width_samples)
% First and last raw sample of every pulse of one LED.

% ---- The "off" and the "on" level of the monitor --------------------------
split = split_low_high(monitor);                    % separates the low from the high values
percentiles = prctile(monitor, [5 95]);
levels.from_percentiles = percentiles(1) < split && percentiles(2) >= split;
if levels.from_percentiles
    % The usual case: the 5th percentile is an "off" value and the 95th
    % percentile an "on" value (the LED is on for 5% to 95% of the samples).
    levels.off = percentiles(1);
    levels.on  = percentiles(2);
    levels.method = '5th and 95th percentile of the monitor';
else
    % The LED is rarely on (or nearly always on): both percentiles lie in
    % the same group. Take the middle value of each group instead.
    levels.off = median(monitor(monitor < split));
    levels.on  = median(monitor(monitor >= split));
    levels.method = 'medians of the low and of the high monitor values';
end
levels.threshold = (levels.off + levels.on)/2;

% ---- On/off state, with a 3-sample median filter ---------------------------
% A sample is "on" if at least two of the three samples (before, itself,
% after) are above the threshold. This removes single-sample flickers.
is_on  = monitor > levels.threshold;
before = [false; is_on(1:end-1)];
after  = [is_on(2:end); false];
state  = (before & is_on) | (before & after) | (is_on & after);

on  = find(state & ~[false; state(1:end-1)]);      % first "on" sample of each pulse
off = find(state & ~[state(2:end); false]);        % last "on" sample of each pulse
keep = (off - on) >= width_samples*0.5;            % ignore very short blips
on = on(keep);
off = off(keep);
end

function split = split_low_high(monitor)
% The value that best separates the monitor values into a low and a high
% group (Otsu's method on a histogram with 256 bins). It does not depend on
% how often the LED is on.
lowest = min(monitor);
highest = max(monitor);
split = lowest;
if ~(highest > lowest), return; end                % a constant monitor: only one level
edges = linspace(lowest, highest, 257);
counts = histcounts(monitor, edges)';
share = counts/sum(counts);                         % share of the samples in each bin
centres = (edges(1:end-1) + edges(2:end))'/2;
share_low = cumsum(share);                          % share of the samples up to each bin
sum_low = cumsum(share.*centres);
% How far apart the means of the two groups are, weighted by the group
% sizes, for a split after each bin (the "between-class variance").
separation = (sum_low(end)*share_low - sum_low).^2./(share_low.*(1 - share_low));
separation(~isfinite(separation)) = 0;
best = find(separation >= max(separation)*(1 - 1e-9));   % equally good bins: an empty range between the groups
split = edges(best(ceil(numel(best)/2)) + 1);       % the middle of that range
end

function rate = pulse_rate(on, fs)
% Pulses per second, from the typical time between two pulse onsets.
rate = NaN;
if numel(on) >= 2, rate = fs/median(diff(on)); end
end

function explain_monitor_problem(monitor, levels, led, variable)
% Called only when the pulses could not be found properly. A monitor with
% two clear levels has few samples in the middle half between them (only
% the rising and falling edges of the pulses). If this monitor has many, or
% only one level, stop with a message that names it.
span = levels.on - levels.off;
in_the_middle = 1;
if span > 0
    in_the_middle = nnz(monitor > levels.off + 0.25*span & monitor < levels.on - 0.25*span)/numel(monitor);
end
if in_the_middle > 0.2
    error('photometry:Monitor', ['The %s LED monitor ("%s") does not show two clearly different ' ...
        'levels (LED off and LED on) in the analysis window. Check that cfg.led%s_variable names ' ...
        'the right channel and that this LED was on during the window.'], led, variable, led);
end
end

function values = pulse_medians(pmt, on, off)
% Median PMT value of every pulse, from sample on+1 to sample off.
% Pulses of the same width are processed together (much faster than one
% loop step per pulse); unusually long pulses are done one by one.
values = nan(numel(on), 1);
widths = off - on;
for width = unique(widths(:))'
    selected = find(widths == width);
    if width > 1000
        for k = selected'
            values(k) = median(pmt(on(k)+1:off(k)));
        end
        continue;
    end
    batch_size = max(1, min(100000, floor(1e6/max(width, 1))));   % limits memory use
    for first = 1:batch_size:numel(selected)
        ids = selected(first:min(first+batch_size-1, numel(selected)));
        indices = (1:width)' + on(ids)';          % one column per pulse
        values(ids) = median(reshape(pmt(indices), width, []), 1)';
    end
end
end
