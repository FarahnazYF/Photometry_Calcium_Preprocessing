function [first, last, info] = photometry_crop_indices(recording_start, lights_on, fs, duration_hours, hours_before_lights_on)
%PHOTOMETRY_CROP_INDICES Which raw samples to keep, from clock times.
%
%   [first, last, info] = photometry_crop_indices(recording_start, lights_on, fs, ...
%                                                 duration_hours, hours_before_lights_on)
%
% The analysis window starts hours_before_lights_on hours before lights ON
% (default 1 hour, i.e. ZT-1, which is ZT 23 of the previous day) and lasts
% duration_hours hours.
%
% Inputs
%   recording_start         clock time of the first raw sample, 'HH:mm' or
%                           'HH:mm:ss' (fractions of a second allowed)
%   lights_on               clock time the lights turn ON, 'HH:mm'
%   fs                      raw samples per second
%   duration_hours          hours to keep (Inf = everything to the end)
%   hours_before_lights_on  (optional, default 1)
%
% Outputs
%   first, last  first and last raw sample to keep (last is Inf when
%                duration_hours is Inf; the caller then uses the end)
%   info         the same numbers in words: reference_clock (clock time of
%                the first kept sample), offset_sec (seconds skipped at the
%                start), start_hours_from_lights_on (-1 = the first kept
%                sample is 1 hour before the first lights ON, i.e. ZT 23), ...
%
% Example: recording start 06:56:16, lights ON 08:00, 1 hour before lights
% ON -> the analysis starts at 07:00:00 (ZT-1); 224 s are skipped.
% If the target time is earlier than the recording start, its next
% occurrence (the following day) is used.

if nargin < 5 || isempty(hours_before_lights_on), hours_before_lights_on = 1; end
validateattributes(fs, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(duration_hours, {'numeric'}, {'scalar', 'positive', 'nonnan'});
validateattributes(hours_before_lights_on, {'numeric'}, {'scalar', 'finite', '>=', 0, '<', 24});

start_sec  = parse_clock(recording_start);
lights_sec = parse_clock(lights_on);
reference_sec = mod(lights_sec - 3600*hours_before_lights_on, 86400);  % clock time of the crop start
offset_sec    = mod(reference_sec - start_sec, 86400);                 % seconds after the recording start

first = round(offset_sec*fs) + 1;
last  = first + round(duration_hours*3600*fs) - 1;

info.recording_start   = char(recording_start);
info.lights_on         = char(lights_on);
info.reference_clock   = format_clock(reference_sec);
info.offset_sec        = offset_sec;
info.start_hours_from_lights_on = -hours_before_lights_on;   % time 0 of the analysis, in hours from the first lights ON
info.first_raw_sample  = first;
info.last_raw_sample   = last;
info.duration_hours    = duration_hours;
end

% ==========================================================================
function seconds = parse_clock(value)
% 'HH:mm' or 'HH:mm:ss(.sss)' -> seconds after midnight.
value = char(value);
if isempty(regexp(value, '^\d{1,2}:\d{2}(:\d{2}(\.\d+)?)?$', 'once'))
    error('photometry:Clock', 'Enter a 24-hour time as HH:mm or HH:mm:ss (you typed "%s").', value);
end
v = str2double(strsplit(value, ':'));
if numel(v) == 2, v(3) = 0; end
if v(1) > 23 || v(2) > 59 || v(3) >= 60
    error('photometry:Clock', 'The time must be between 00:00:00 and 23:59:59 (you typed "%s").', value);
end
seconds = 3600*v(1) + 60*v(2) + v(3);
end

function text = format_clock(seconds)
% Seconds after midnight -> 'HH:mm:ss' (with decimals only when needed).
hh = floor(seconds/3600);
mm = floor(mod(seconds, 3600)/60);
ss = mod(seconds, 60);
if ss == fix(ss)
    text = sprintf('%02d:%02d:%02d', hh, mm, ss);
else
    text = sprintf('%02d:%02d:%06.3f', hh, mm, ss);
end
end
