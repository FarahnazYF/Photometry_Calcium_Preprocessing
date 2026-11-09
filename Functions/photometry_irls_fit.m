function [coefficients, weights, note, step_change] = photometry_irls_fit(x, y, c)
%PHOTOMETRY_IRLS_FIT Robust straight line y = slope*x + intercept (IRLS, Tukey bisquare).
%
%   [coefficients, weights, note, step_change] = photometry_irls_fit(x, y, c)
%
% Fits one straight line by iteratively reweighted least squares (IRLS),
% MATLAB's robustfit(x, y, 'bisquare', c):
%   1. Start with an ordinary least-squares line.
%   2. Divide every residual by c times a robust SD of the residuals
%      (MAD/0.6745) to get u. Give each sample the weight (1 - u^2)^2 if
%      |u| < 1, otherwise 0 (Tukey's bisquare).
%   3. Refit the line with these weights; repeat until it stops changing.
% With c = 1.4, samples further than about 1.4 robust SDs from the line
% (for example calcium transients in the 470 channel) get weight 0, so the
% line follows the shared, movement-related part of the two signals.
%
% Inputs
%   x  405 values (column vector, no NaN)
%   y  470 values (same length, no NaN)
%   c  tuning constant (MATLAB's default for robustfit is 4.685; we use 1.4)
%
% Outputs
%   coefficients  [slope intercept]  (the order polyval expects)
%   weights       final weight of every sample (0 to 1)
%   note          robustfit's warning, "" if none
%   step_change   how much one more IRLS step would change the slope
%                 (relative). robustfit stops after 50 steps and warns
%                 "Iteration limit reached"; a tiny step_change (e.g. 1e-6)
%                 shows that warning is harmless. Not calculated if you
%                 ask for fewer than 4 outputs.

% robustfit's "Iteration limit reached" warning is kept in `note` rather
% than printed.
lastwarn('');
state = warning('off', 'stats:statrobustfit:IterationLimit');
restore = onCleanup(@() warning(state));
[b, stats] = robustfit(x, y, 'bisquare', c);   % b = [intercept; slope]
clear restore
note = string(lastwarn);
coefficients = [b(2) b(1)];
weights = stats.w;
clear stats
if nargout < 4, return; end

% One more IRLS step exactly as robustfit takes it: leverage-adjusted
% residuals, scale = MAD / 0.6745, bisquare weights, weighted least squares.
n = numel(x);
centred = x - mean(x);
h = min(0.9999, 1/n + centred.^2/sum(centred.^2));   % leverage
r = (y - b(1) - b(2)*x)./sqrt(1 - h);
sorted = sort(abs(r));
s = max(median(sorted(2:end))/0.6745, 1e-6*std(y));
u = r/(s*c);
root_w = sqrt((abs(u) < 1).*(1 - u.^2).^2);
next = [root_w root_w.*x]\(root_w.*y);
step_change = abs(next(2) - b(2))/max(abs(b(2)), eps);
end
