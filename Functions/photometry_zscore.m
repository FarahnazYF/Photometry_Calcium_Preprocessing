function [z, z_robust, info] = photometry_zscore(signal)
%PHOTOMETRY_ZSCORE Standard and robust z-scores over the whole recording.
%
%   [z, z_robust, info] = photometry_zscore(signal)
%
%   z        = (signal - mean) / SD
%   z_robust = (signal - median) / (1.4826 x MAD)
% MAD is the median absolute deviation from the median. 1.4826 x MAD equals
% the SD for normally distributed data, but large calcium transients and
% leftover artifacts barely change it, so the robust z-score is less
% affected by them.
%
% One mean, SD, median and MAD are calculated over all valid samples of
% the recording (all phases together). Missing samples (NaN) stay NaN. If
% the SD or MAD is zero, the scores are NaN (and info says so).
%
% Output
%   z, z_robust  column vectors, the same length as signal
%   info         mean, std, median, robust_sd, number_of_valid_samples,
%                standard_defined, robust_defined

x = signal(:);
valid = isfinite(x);
z = nan(size(x));
z_robust = nan(size(x));
info.number_of_valid_samples = nnz(valid);
info.mean = NaN; info.std = NaN; info.median = NaN; info.robust_sd = NaN;
info.standard_defined = false;
info.robust_defined = false;
info.scope = 'all valid samples of the recording, all phases together';
if ~any(valid), return; end

y = x(valid);
info.mean = mean(y);
info.std = std(y);
info.median = median(y);
info.robust_sd = 1.4826*mad(y, 1);      % mad(y,1) = median absolute deviation
if numel(y) > 1 && isfinite(info.std) && info.std > 0
    z(valid) = (y - info.mean)/info.std;
    info.standard_defined = true;
end
if isfinite(info.robust_sd) && info.robust_sd > 0
    z_robust(valid) = (y - info.median)/info.robust_sd;
    info.robust_defined = true;
end
end
