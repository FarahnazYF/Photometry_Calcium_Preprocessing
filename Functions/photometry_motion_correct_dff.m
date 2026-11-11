function data = photometry_motion_correct_dff(data, cfg)
%PHOTOMETRY_MOTION_CORRECT_DFF Fit 405 to 470 (IRLS) and calculate dF/F.
%
%   data = photometry_motion_correct_dff(data, cfg)
%
% Why
%   Movement, tissue changes and other non-neural effects change the 405
%   (isosbestic) and 470 (calcium) signals in the same way. 405 does not
%   depend on calcium, so a scaled copy of 405 shows how 470 would look
%   without calcium activity.
%
% How
%   1. Samples used: present in both bleaching-corrected channels and not
%      removed by hand in Step 10 (data.manual_mask).
%   2. One straight line, fitted 405 = slope x 405 + intercept, is fitted to
%      all these samples of the whole recording by IRLS with Tukey's
%      bisquare weights, tuning constant cfg.irls_tuning_constant (1.4)
%      (photometry_irls_fit). Calcium transients get weight 0 and do not
%      pull the line.
%   3. dF/F = (470 - fitted 405) / fitted 405
%      a fraction (0.05 = 5%); NaN where a sample is missing or removed.
%
% Output
%   data.dF_F         dF/F per sample (fraction)
%   data.fitted405    the fitted 405 (slope x 405 + intercept)
%   data.valid_mask   true where dF/F has a value
%   data.motion_fit   slope, intercept, tuning constant, the share of
%                     samples with weight 0, and robustfit's note

c405 = data.corrected405(:);
c470 = data.corrected470(:);
valid = isfinite(c405) & isfinite(c470) & ~data.manual_mask(:);
if nnz(valid) < 2
    error('photometry:Motion', 'Too few samples are left to fit 405 to 470.');
end

fprintf('Motion correction: IRLS fit of 405 to 470 on %d samples ...\n', nnz(valid));
[coefficients, weights, note, step_change] = photometry_irls_fit(c405(valid), c470(valid), ...
    cfg.irls_tuning_constant);

data.fitted405 = polyval(coefficients, c405);
data.dF_F = (c470 - data.fitted405)./data.fitted405;
data.dF_F(~valid) = NaN;
data.valid_mask = valid;

data.motion_fit.method = 'IRLS, Tukey bisquare (robustfit)';
data.motion_fit.slope = coefficients(1);
data.motion_fit.intercept = coefficients(2);
data.motion_fit.tuning_constant = cfg.irls_tuning_constant;
data.motion_fit.samples_used = nnz(valid);
data.motion_fit.zero_weight_percent = 100*mean(weights == 0);
data.motion_fit.note = char(note);
data.motion_fit.next_step_relative_change = step_change;

fprintf('  fitted 405 = %.4g x 405 + %.4g; %.1f%% of samples got weight 0.\n', ...
    coefficients(1), coefficients(2), data.motion_fit.zero_weight_percent);
if strlength(note) > 0
    fprintf('  robustfit: "%s" (one more step would change the slope by %.2g, relative).\n', ...
        note, step_change);
end
fprintf('  dF/F: %.1f%% of samples valid; SD %.2f%%.\n', 100*mean(valid), 100*std(data.dF_F(valid)));
data = photometry_note_step(data, 11, cfg, {'irls_tuning_constant'});
end
