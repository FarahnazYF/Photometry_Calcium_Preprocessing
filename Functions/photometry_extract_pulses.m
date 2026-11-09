function data = photometry_extract_pulses(raw, cfg)
%PHOTOMETRY_EXTRACT_PULSES One 405 and one 470 value per LED pulse.
%
%   data = photometry_extract_pulses(raw, cfg)
%
% The 405-nm and 470-nm LEDs flash in turn, and one photodetector (PMT)
% records the light of both. The LED monitor channels show when each LED is
% on. For each LED:
%   1. Find its pulses: the monitor is "on" above a threshold halfway
%      between its 5th and 95th percentile (a 3-sample median filter removes
%      single-sample flickers). Pulses shorter than half of
%      cfg.pulse_width_ms are ignored.
%   2. Take the median of the PMT signal during each pulse (from the sample
%      after the onset to the last "on" sample).
% Result: one value per pulse, i.e. cfg.sample_rate_hz values per second
% for each channel.
%
% Output (all column vectors)
%   data.raw405, data.raw470    the extracted fluorescence (PMT units)
%   data.time_s                 time of each 405 pulse, seconds after the
%                               start of the analysis window (gaps kept)
%   data.time470_s              time of each 470 pulse (same clock)
%   data.crop_info              copied from raw
%   data.pulse_info             thresholds, pulse counts, measured rate
% Stops with an error if the measured pulse rate differs from
% cfg.sample_rate_hz by more than 2% (wrong settings or wrong channels).

width_samples = cfg.pulse_width_ms/1000*raw.fs;   % pulse width in raw samples
[on405, off405, threshold405] = detect_pulses(raw.led405, width_samples);
[on470, off470, threshold470] = detect_pulses(raw.led470, width_samples);
if numel(on405) < 2 || numel(on470) < 2
    error('photometry:Pulses', ['Fewer than two LED pulses were found in one or both LED ' ...
        'monitor channels. Check cfg.led405_variable and cfg.led470_variable.']);
end

data.raw405 = pulse_medians(raw.pmt, on405, off405);
data.raw470 = pulse_medians(raw.pmt, on470, off470);
% Time zero is the first sample of the analysis window, even if the first
% pulse comes a little later.
data.time_s    = (on405-1)/raw.fs;
data.time470_s = (on470-1)/raw.fs;
data.crop_info = raw.crop_info;

data.pulse_info.threshold405 = threshold405;
data.pulse_info.threshold470 = threshold470;
data.pulse_info.pulses405 = numel(on405);
data.pulse_info.pulses470 = numel(on470);
data.pulse_info.first_pulse_sec = data.time_s(1);
data.pulse_info.measured_rate_hz = 1/median(diff(data.time_s));

fprintf('Pulses found: %d (405) and %d (470); %.3f pulses per second.\n', ...
    numel(on405), numel(on470), data.pulse_info.measured_rate_hz);
if abs(data.pulse_info.measured_rate_hz - cfg.sample_rate_hz)/cfg.sample_rate_hz > 0.02
    error('photometry:Rate', ['The measured pulse rate (%.3f per second) differs from ' ...
        'cfg.sample_rate_hz (%g). Check the settings in Step 1.'], ...
        data.pulse_info.measured_rate_hz, cfg.sample_rate_hz);
end
end

% ==========================================================================
function [on, off, threshold] = detect_pulses(monitor, width_samples)
% First and last raw sample of every pulse of one LED.
threshold = (prctile(monitor, 5) + prctile(monitor, 95))/2;
state = medfilt1(double(monitor > threshold), 3);   % 1 = LED on
edges = diff([0; state; 0]);
on  = find(edges == 1);
off = find(edges == -1) - 1;
keep = (off - on) >= width_samples*0.5;              % ignore very short blips
on = on(keep);
off = off(keep);
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
