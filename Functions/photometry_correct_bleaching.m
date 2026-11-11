function data = photometry_correct_bleaching(data, cfg)
%PHOTOMETRY_CORRECT_BLEACHING Divide each channel by a double exponential, per phase.
%
%   data = photometry_correct_bleaching(data, cfg)
%
% Why
%   Under constant light the fluorophores slowly bleach, so both signals
%   decay over time, fast at first and then more slowly. This slow decay
%   is not neural activity.
%
% How
%   In every phase and for each channel separately, a double exponential
%       trend(t) = a*exp(b*t) + c*exp(d*t)     (t = minutes since phase start)
%   is fitted to the filtered signal (least squares, Curve Fitting
%   Toolbox), and the signal is divided by it:
%       corrected = filtered / trend
%   so the corrected signal hovers around 1.
%   - If the fit fails for either channel of a phase, a straight line is
%     fitted to both channels of that phase instead (a warning says so).
%   - A phase whose 405 median is below cfg.low_signal_fraction (20%) of
%     the median of the whole recording has lost its signal (e.g. a
%     disconnected fibre). It is excluded: all its samples become missing.
%
% What this means for slow changes (important when you interpret results)
%   Every phase gets its own fit, and both channels end up around 1 in
%   every phase. So:
%   - A difference in signal LEVEL between two phases is removed. dF/F of
%     one phase cannot be compared in level with dF/F of another phase.
%   - A smooth change that lasts as long as a phase (tens of minutes to
%     hours) is taken for bleaching and is partly removed. The four
%     coefficients may take either sign, so a slow rise is removed too.
%   - Changes over seconds to a few minutes are far too fast for the
%     fitted curve and are kept.
%   Dividing (not subtracting) assumes that the bleaching comes mainly
%   from the indicator and not from autofluorescence.
%
% Output
%   data.corrected405, data.corrected470   bleaching-corrected (around 1)
%   data.bleaching_trend405, ..._trend470  the fitted trends
%   data.bleaching_info                    one row per phase: the method
%                                          used and the coefficients a-d

n_phases = size(data.phase_windows, 1);
data.corrected405 = nan(size(data.filtered405));
data.corrected470 = nan(size(data.filtered470));
data.bleaching_trend405 = nan(size(data.filtered405));
data.bleaching_trend470 = nan(size(data.filtered470));
method = strings(n_phases, 1);
coefficients = nan(n_phases, 4, 2);       % [a b c d] for 405 (:,:,1) and 470 (:,:,2)
recording_median405 = median(data.filtered405, 'omitnan');

for p = 1:n_phases
    idx = data.phase_windows(p, 1):data.phase_windows(p, 2);
    t = data.time_s(idx);                                  % seconds
    values = [data.filtered405(idx), data.filtered470(idx)];

    % ---- Has this phase lost its signal? ----------------------------------
    phase_median405 = median(values(:, 1), 'omitnan');
    if isnan(phase_median405) || phase_median405 < cfg.low_signal_fraction*recording_median405
        method(p) = "excluded (405 signal lost)";
        fprintf('Phase %d excluded: its 405 signal is too low (signal lost).\n', p);
        continue;
    end

    % ---- Double exponential ------------------------------------------------
    t_min = (t - t(1))/60;                                 % minutes since phase start
    trend = nan(size(values));
    try
        for ch = 1:2
            valid = ~isnan(values(:, ch));
            if nnz(valid) < cfg.min_fit_samples
                error('photometry:FitSamples', 'Too few valid samples.');
            end
            y = values(valid, ch);
            options = fitoptions('Method', 'NonlinearLeastSquares', ...
                'StartPoint', [range(y)/2, -0.1, range(y)/2, -0.001], ...
                'Lower', [-Inf, -Inf, -Inf, -Inf]);
            model = fit(t_min(valid), y, fittype('exp2'), options);
            trend(:, ch) = model(t_min);
            coefficients(p, :, ch) = coeffvalues(model);
        end
        method(p) = "double exponential";
    catch err
        % ---- Fallback: a straight line through both channels ---------------
        trend = nan(size(values));
        coefficients(p, :, :) = NaN;
        for ch = 1:2
            valid = ~isnan(values(:, ch));
            if nnz(valid) >= cfg.min_fit_samples
                straight = polyfit(t(valid), values(valid, ch), 1);   % [slope intercept]
                trend(:, ch) = polyval(straight, t);
            end
        end
        method(p) = "straight line (double exponential failed)";
        warning('photometry:BleachingFallback', ...
            'Phase %d: the double exponential failed (%s). A straight line was used instead.', ...
            p, err.message);
    end

    data.bleaching_trend405(idx) = trend(:, 1);
    data.bleaching_trend470(idx) = trend(:, 2);
    data.corrected405(idx) = values(:, 1)./trend(:, 1);
    data.corrected470(idx) = values(:, 2)./trend(:, 2);
end

data.bleaching_info = table((1:n_phases)', method, ...
    coefficients(:,1,1), coefficients(:,2,1), coefficients(:,3,1), coefficients(:,4,1), ...
    coefficients(:,1,2), coefficients(:,2,2), coefficients(:,3,2), coefficients(:,4,2), ...
    'VariableNames', {'phase', 'method', 'a405', 'b405', 'c405', 'd405', ...
    'a470', 'b470', 'c470', 'd470'});
fprintf('Bleaching corrected: double exponential in %d of %d phases.\n', ...
    nnz(method == "double exponential"), n_phases);
data = photometry_note_step(data, 8, cfg, {'min_fit_samples', 'low_signal_fraction'});
end
