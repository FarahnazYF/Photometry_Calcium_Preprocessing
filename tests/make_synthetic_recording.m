function [file, truth] = make_synthetic_recording(folder, varargin)
%MAKE_SYNTHETIC_RECORDING Write a small fake raw recording for testing.
%
%   [file, truth] = make_synthetic_recording(folder)
%   [file, truth] = make_synthetic_recording(folder, 'Name', value, ...)
%
% Creates <folder>/synthetic_recording.mat (MAT v7.3) laid out like a real
% recording: Raw (PMT), Raw_2 (405 LED monitor) and Raw_3 (470 LED monitor)
% at 1000 Hz, with alternating 10-ms LED pulses (50 per second per LED),
% and a variable RecordingStartTime = '06:30:00'.
%
% Content (two phases separated by a 31-minute pause of the LEDs):
%   - both channels bleach (double exponential decay);
%   - movement: a slow wobble, plus a few short artifacts (dips) that are
%     larger in 470 than in 405;
%   - calcium transients in 470 only;
%   - a 23.5-s sawtooth (0.4% of the level) in 405 only;
%   - a little white noise.
%
% Options: 'PhaseMinutes' (12), 'GapMinutes' (31), 'Sawtooth' (true), 'Seed' (1),
%          'Drop470' ([] = none; [from to] in seconds: the 470 LED is off
%          between these two times while the 405 LED keeps flashing)
%          'LedPause' ([] = none; [from to] in seconds: both LEDs are off
%          between these two times, a short pause inside a phase)
% truth: the times of the movement dips and the transients, and the true
%        sawtooth (a function of time, in PMT units).
%
% Note: the bleaching in this recording is mild (the fast part decays over
% 8 to 10 minutes). Real recordings can fall more steeply in the first
% minutes after the LEDs are switched on.

options = struct('PhaseMinutes', 12, 'GapMinutes', 31, 'Sawtooth', true, 'Seed', 1, 'Drop470', [], ...
    'LedPause', []);
for k = 1:2:numel(varargin), options.(varargin{k}) = varargin{k+1}; end
rng(options.Seed);

fs = 1000;
phase_samples = round(options.PhaseMinutes*60*fs);
gap_samples = round(options.GapMinutes*60*fs);
n = 2*phase_samples + gap_samples;
t = (0:n-1)'/fs;                                     % seconds
active = true(n, 1);
active(phase_samples+1:phase_samples+gap_samples) = false;   % LEDs off between phases
if ~isempty(options.LedPause)
    active(t >= options.LedPause(1) & t < options.LedPause(2)) = false;   % both LEDs pause
end

% LED monitors: 405 on for samples 0-9, 470 on for 10-19 of every 20.
cycle = mod((0:n-1)', 20);
Raw_2 = double(cycle < 10 & active);
Raw_3 = double(cycle >= 10 & active);
if ~isempty(options.Drop470)
    Raw_3(t >= options.Drop470(1) & t < options.Drop470(2)) = 0;   % the 470 LED drops out
end

% Movement: a slow wobble in both channels (470 moves 0.7x as much as 405,
% which the motion correction removes), and short artifacts (about 2 s)
% that the correction cannot remove: -4% in 405 but -12% in 470.
phase2_start = (phase_samples + gap_samples)/fs;     % seconds
dips = [150; 400; 600; phase2_start + [120; 520]];   % seconds: three in phase 1, two in phase 2
dips = dips(dips < n/fs);
movement = 0.01*sin(2*pi*t/40);
artifact = zeros(n, 1);
for k = 1:numel(dips)
    artifact = artifact - exp(-((t - dips(k))/0.7).^2);
end
% Calcium transients (470 only): 3% bumps, ~1 s wide, every ~15 s.
transient_times = sort(rand(round(n/fs/15), 1)*n/fs);
transients = zeros(n, 1);
for k = 1:numel(transient_times)
    near = abs(t - transient_times(k)) < 4;
    transients(near) = transients(near) + 0.03*exp(-((t(near) - transient_times(k))/0.5).^2);
end
% Sawtooth (405 only): rises over 19.5 s, falls over 4 s; 1.4% from
% bottom to top, about 0.4% RMS of the level (as in our recordings).
period = 23.5;
sawtooth_shape = @(time) 0.014*(((mod(time, period) <= 19.5).*(mod(time, period)/19.5) + ...
    (mod(time, period) > 19.5).*(1 - (mod(time, period) - 19.5)/4)) - 0.5)*options.Sawtooth;
sawtooth = sawtooth_shape(t);
% Bleaching: a faster and a slower decay (time in minutes).
bleaching405 = @(time) 0.3*exp(-time/60/8) + 0.2*exp(-time/60/300) + 0.5;
bleaching470 = @(time) 0.25*exp(-time/60/10) + 0.3*exp(-time/60/400) + 0.6;
bleach405 = bleaching405(t);
bleach470 = bleaching470(t);

Raw = zeros(n, 1);
on405 = Raw_2 > 0;
on470 = Raw_3 > 0;
Raw(on405) = 500*bleach405(on405).*(1 + movement(on405) + 0.04*artifact(on405) + sawtooth(on405)) ...
    + 0.5*randn(nnz(on405), 1);
Raw(on470) = 900*bleach470(on470).*(1 + 0.7*movement(on470) + 0.12*artifact(on470) + transients(on470)) ...
    + 0.5*randn(nnz(on470), 1);

RecordingStartTime = '06:30:00';
if ~isfolder(folder), mkdir(folder); end
file = fullfile(folder, 'synthetic_recording.mat');
save(file, 'Raw', 'Raw_2', 'Raw_3', 'RecordingStartTime', '-v7.3');

truth.fs = fs;
truth.samples = n;
truth.duration_hours = n/fs/3600;
truth.dip_times_s = dips;
truth.transient_times_s = transient_times;
truth.sawtooth_period_s = period;
truth.sawtooth405 = @(time) 500*bleaching405(time).*sawtooth_shape(time);   % in PMT units
truth.recording_start = '06:30:00';
end
