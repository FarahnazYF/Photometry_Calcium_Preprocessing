function [zt, day, label] = photometry_zt(hours_from_lights_on)
%PHOTOMETRY_ZT Zeitgeber time (ZT) that restarts at 0 at every lights ON.
%
%   [zt, day, label] = photometry_zt(hours_from_lights_on)
%
% Input
%   hours_from_lights_on  time in hours counted from the FIRST lights ON of
%                         the recording (negative before it). For a sample of
%                         the pipeline: data.crop_info.start_hours_from_lights_on
%                         + data.time_s/3600.
%
% Outputs
%   zt     Zeitgeber time in hours, from 0 up to (not including) 24.
%          ZT 0 = lights ON. ZT runs to 24, which is ZT 0 of the next day:
%          36 hours after the first lights ON is ZT 12, not ZT 36.
%   day    which lights ON the sample follows: 1 from the first lights ON,
%          2 from the second, ... and 0 before the first lights ON (e.g. the
%          hour before it, ZT 23, when the analysis starts at ZT-1).
%   label  the same as text, e.g. 'ZT 12.00 (day 2)' (a cell array of
%          texts if the input has more than one value)
%
% Examples
%   photometry_zt(-1)   -> zt 23, day 0   (ZT-1 = ZT 23 of the previous day)
%   photometry_zt(0)    -> zt 0,  day 1
%   photometry_zt(24)   -> zt 0,  day 2
%   photometry_zt(36)   -> zt 12, day 2

h = hours_from_lights_on;
zt = mod(h, 24);
zt(zt > 24 - 1e-9) = 0;              % rounding: 23.999999999999 h is ZT 0
day = round((h - zt)/24) + 1;          % h - zt is a whole number of days
if nargout > 2
    % Rounded DOWN to 2 decimals, so ZT 23.999 is shown as 23.99, never 24.00.
    label = arrayfun(@(z, d) sprintf('ZT %.2f (day %d)', floor(z*100 + 1e-9)/100, d), ...
        zt, day, 'UniformOutput', false);
    if isscalar(label), label = label{1}; end
end
end
